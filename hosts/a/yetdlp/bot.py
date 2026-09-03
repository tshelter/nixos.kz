#!/usr/bin/env python3
"""Telegram bot that downloads TikTok / Instagram videos and photos (no ads).

Send it any message containing a TikTok, Instagram or YouTube link and it
replies with the media. Handles short links (vt.tiktok.com), single videos,
Instagram reels and posts, YouTube Shorts, and TikTok / Instagram photo
slideshows (multiple images).

Also works in guest mode (like @mira and similar bots): reply to someone's
message that contains a link and mention @yetdlpbot in the reply, or just
mention @yetdlpbot with a link in your own message, in any chat it isn't a
member of. Requires "Guest Mode" turned on for this bot in BotFather's Mini
App (Bot Settings) -- there's no slash command for this one.

TikTok is fetched via the tikwm.com API (clean, no-watermark, supports photo
slideshows) with a yt-dlp fallback. Instagram is fetched with yt-dlp; drop an
exported cookies.txt into STATE_DIR for private / rate-limited posts.

Config via environment:
  BOT_TOKEN          - Telegram bot token (required)
  ALLOWED_USER_IDS   - space/comma separated user ids; empty = everyone
  STATE_DIR          - writable dir; optional cookies.txt here goes to yt-dlp
  MAX_UPLOAD_MB      - skip files larger than this (default 49, Telegram limit)
  MAX_CONCURRENCY    - simultaneous downloads (default 3)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yt_dlp
from sssig import SssInstagram
from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.client.telegram import TelegramAPIServer
from aiogram.enums import ChatAction, ParseMode
from aiogram.exceptions import TelegramBadRequest, TelegramForbiddenError
from aiogram.filters import Command, CommandStart
from aiogram.types import (
    FSInputFile,
    InlineQueryResultArticle,
    InputMediaPhoto,
    InputMediaVideo,
    InputTextMessageContent,
    Message,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("tgbot-dl")

TOKEN = os.environ["BOT_TOKEN"]
ALLOWED = {
    int(x)
    for x in re.split(r"[,\s]+", os.environ.get("ALLOWED_USER_IDS", "").strip())
    if x
}
STATE_DIR = Path(os.environ.get("STATE_DIR", ".")).resolve()
COOKIES = STATE_DIR / "cookies.txt"
# A local Telegram Bot API server (telegram-bot-api) lifts the 50 MB upload
# cap to 2 GB. Point at it with TELEGRAM_API_BASE=http://127.0.0.1:8081.
TELEGRAM_API_BASE = os.environ.get("TELEGRAM_API_BASE", "").strip()
_default_max = "1900" if TELEGRAM_API_BASE else "49"
MAX_UPLOAD = int(os.environ.get("MAX_UPLOAD_MB", _default_max)) * 1024 * 1024
# Chat used to mint a file_id for guest/inline delivery when the requester has
# never opened a DM with the bot. Falls back to the allowlist otherwise.
STASH_CHAT_ID = os.environ.get("STASH_CHAT_ID", "").strip()

# Daily self-check: download one link of each media shape; ping SELFCHECK_NOTIFY
# only if something breaks. SELFCHECK_AT is HH:MM UTC.
SELFCHECK_ENABLE = os.environ.get("SELFCHECK_ENABLE", "1").lower() not in ("0", "no", "false", "")
SELFCHECK_AT = os.environ.get("SELFCHECK_AT", "09:00").strip()
SELFCHECK_NOTIFY = os.environ.get("SELFCHECK_NOTIFY", "").strip()

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

URL_RE = re.compile(r"https?://\S+", re.I)
TIKTOK_RE = re.compile(r"(?:^|\.)tiktok\.com$|(?:^|\.)douyin\.com$", re.I)
INSTAGRAM_RE = re.compile(r"(?:^|\.)(?:instagram\.com|instagr\.am|ig\.me)$", re.I)
YOUTUBE_RE = re.compile(r"(?:^|\.)(?:youtube\.com|youtu\.be|youtube-nocookie\.com)$", re.I)

VIDEO_EXT = {".mp4", ".mov", ".webm", ".mkv", ".m4v"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXT = {".mp3", ".m4a", ".opus", ".ogg", ".wav", ".flac"}
MEDIA_EXT = VIDEO_EXT | IMAGE_EXT | AUDIO_EXT

_sem = asyncio.Semaphore(int(os.environ.get("MAX_CONCURRENCY", "3")))

_session = (
    AiohttpSession(api=TelegramAPIServer.from_base(TELEGRAM_API_BASE))
    if TELEGRAM_API_BASE else None
)
bot = Bot(token=TOKEN, session=_session,
          default=DefaultBotProperties(parse_mode=ParseMode.HTML))
dp = Dispatcher()
sss = SssInstagram()
BOT_ID = int(TOKEN.split(":", 1)[0])


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _host(url: str) -> str:
    m = re.match(r"https?://([^/]+)", url, re.I)
    if not m:
        return ""
    return m.group(1).split("@")[-1].split(":")[0].lower()


def _platform(url: str) -> str | None:
    h = _host(url)
    if TIKTOK_RE.search(h) or "tiktok" in h:
        return "tiktok"
    if INSTAGRAM_RE.search(h):
        return "instagram"
    if YOUTUBE_RE.search(h):
        return "youtube"
    return None


def _esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")[:500]


def _http_get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


_RETRY_CODES = {408, 429, 500, 502, 503, 504}


def _download_to(url: str, dest: Path, timeout: int = 120, retries: int = 4) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/"})
    last: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
                shutil.copyfileobj(r, f)
            return
        except urllib.error.HTTPError as e:
            last = e
            if e.code not in _RETRY_CODES:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            last = e
        time.sleep(1.5 * (attempt + 1))
    raise last  # type: ignore[misc]


# --------------------------------------------------------------------------- #
# TikTok via tikwm.com
# --------------------------------------------------------------------------- #
def _tiktok_tikwm(url: str, outdir: str) -> dict:
    api = "https://tikwm.com/api/?hd=1&url=" + urllib.parse.quote(url, safe="")
    data = json.loads(_http_get(api))
    if data.get("code") != 0:
        raise RuntimeError(f"tikwm: {data.get('msg') or data}")
    d = data["data"]
    out = Path(outdir)
    images = d.get("images") or []
    if images:
        for i, img in enumerate(images, 1):
            _download_to(img, out / f"{i:03d}.jpg")
    else:
        video_url = d.get("hdplay") or d.get("play") or d.get("wmplay")
        if not video_url:
            raise RuntimeError("tikwm: no video url in response")
        _download_to(video_url, out / "001.mp4")
        # slideshows have no video; single videos rarely need the audio track
    return {
        "title": d.get("title") or "",
        "uploader": (d.get("author") or {}).get("unique_id") or "",
    }


# --------------------------------------------------------------------------- #
# generic / Instagram via yt-dlp
# --------------------------------------------------------------------------- #
def _ydl_opts(outdir: str) -> dict:
    opts = {
        "outtmpl": str(Path(outdir) / "%(autonumber)03d-%(id)s.%(ext)s"),
        "format": "bv*+ba/b/best",
        "merge_output_format": "mp4",
        "format_sort": ["ext:mp4:m4a", "res", "br"],
        "noplaylist": False,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "restrictfilenames": True,
        "concurrent_fragment_downloads": 4,
        "retries": 5,
        "fragment_retries": 5,
        "extractor_retries": 3,
        "socket_timeout": 30,
    }
    if COOKIES.exists():
        opts["cookiefile"] = str(COOKIES)
    return opts


def _ydl_download(url: str, outdir: str) -> dict:
    with yt_dlp.YoutubeDL(_ydl_opts(outdir)) as ydl:
        info = ydl.extract_info(url, download=True)
    return {
        "title": info.get("title") or info.get("description") or "",
        "uploader": info.get("uploader") or info.get("uploader_id") or "",
    }


# --------------------------------------------------------------------------- #
# YouTube via loader.to
# --------------------------------------------------------------------------- #
# YouTube blocks this server's datacenter IP outright ("Sign in to confirm
# you're not a bot") for every yt-dlp player client. loader.to fetches it on
# their own infra and hands back a temporary direct link. Async job API:
# start -> poll progress_url -> download_url.
LOADERTO_API = "https://loader.to/ajax/download.php"


def _loaderto_download(url: str, outdir: str, fmt: str = "720") -> dict:
    q = LOADERTO_API + "?" + urllib.parse.urlencode({"format": fmt, "url": url})
    start = json.loads(_http_get(q, timeout=30))
    if not start.get("success") or not start.get("progress_url"):
        raise RuntimeError(f"loader.to rejected the link ({start.get('text') or start})")
    title = start.get("title") or ""
    dl = None
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline:
        time.sleep(2.5)
        p = json.loads(_http_get(start["progress_url"], timeout=30))
        if p.get("download_url"):
            dl = p["download_url"]
            break
        if (p.get("text") or "").strip().lower() == "failed":
            raise RuntimeError("loader.to could not process this video")
    if not dl:
        raise RuntimeError("loader.to timed out preparing the download")
    _download_to(dl, Path(outdir) / "001.mp4", timeout=600)
    return {"title": title, "uploader": ""}


def _blocking_fetch(url: str, outdir: str) -> dict:
    """Download media for `url` into `outdir`. Returns {title, uploader}."""
    plat = _platform(url)
    if plat == "tiktok":
        try:
            return _tiktok_tikwm(url, outdir)
        except Exception as e:  # noqa: BLE001
            log.warning("tikwm failed for %s (%s); trying yt-dlp", url, e)
            for p in Path(outdir).iterdir():
                p.unlink()
            return _ydl_download(url, outdir)
    if plat == "youtube":
        try:
            return _loaderto_download(url, outdir)
        except Exception as e:  # noqa: BLE001
            log.warning("loader.to failed for %s (%s); trying yt-dlp", url, e)
            for p in Path(outdir).iterdir():
                p.unlink()
            return _ydl_download(url, outdir)
    try:
        return _ydl_download(url, outdir)
    except yt_dlp.utils.DownloadError as e:
        raise RuntimeError(_friendly_ydl_error(str(e))) from e


def _friendly_ydl_error(raw: str) -> str:
    low = raw.lower()
    if any(s in low for s in ("login required", "rate-limit", "checkpoint",
                              "empty media response", "requires authentication")):
        return "Instagram wants this server to log in to see that post."
    if "no video in this post" in low or "no video formats found" in low:
        return ("Instagram photo post. Instagram now blocks anonymous photo "
                "downloads from this server and the sssinstagram fallback is "
                "behind a CAPTCHA. Reels/videos still work.")
    if "sign in to confirm" in low or "confirm you" in low and "not a bot" in low:
        return "YouTube is rate-limiting this server. Try again in a bit."
    if "unavailable" in low or "not available" in low or "removed" in low:
        return "The post is private, removed, or region-locked."
    return re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", raw).strip()[:400]


async def _fetch_via_sss(url: str, outdir: str) -> dict:
    result = await sss.fetch(url)
    out = Path(outdir)
    total = len(result["items"])
    ok = 0
    for i, it in enumerate(result["items"], 1):
        try:
            await asyncio.to_thread(_download_to, it["url"], out / f"{i:03d}.{it['ext']}")
            ok += 1
        except Exception as e:  # noqa: BLE001 — one dead CDN link shouldn't sink the post
            log.warning("sss item %d/%d failed to download: %s", i, total, e)
    if not ok:
        raise RuntimeError("sssinstagram media links all failed to download")
    return {"title": result["title"], "uploader": result["username"]}


async def _fetch_any(url: str, outdir: str) -> tuple[dict, list[Path]]:
    """Download `url` into `outdir` via the best available source; returns
    (meta, files). Shared by direct-message and inline-mode handlers."""
    try:
        meta = await asyncio.to_thread(_blocking_fetch, url, outdir)
    except Exception as primary_err:  # noqa: BLE001
        # yt-dlp can't grab Instagram photo posts / carousels anonymously;
        # sssinstagram's API can. Only worth trying for Instagram — TikTok
        # already has its tikwm/yt-dlp fallback baked into _blocking_fetch.
        if _platform(url) != "instagram":
            raise
        log.info("yt-dlp failed for %s (%s); trying sssinstagram", url, primary_err)
        for p in Path(outdir).iterdir():
            p.unlink()
        try:
            meta = await _fetch_via_sss(url, outdir)
        except Exception as sss_err:  # noqa: BLE001
            log.warning("sssinstagram fallback failed for %s: %s", url, sss_err)
            raise primary_err from sss_err
    files = sorted(p for p in Path(outdir).iterdir()
                   if p.is_file() and p.suffix.lower() in MEDIA_EXT)
    if not files:
        raise RuntimeError("downloaded nothing for this link")
    return meta, files


# --------------------------------------------------------------------------- #
# sending
# --------------------------------------------------------------------------- #
def _shrink_video(path: Path) -> Path | None:
    out = path.with_name(path.stem + "-small.mp4")
    cmd = [
        "ffmpeg", "-y", "-i", str(path),
        "-vf", "scale='min(1280,iw)':-2",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "30",
        "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
        str(out),
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=600)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        log.warning("ffmpeg shrink failed: %s", e)
        return None
    return out if out.exists() and out.stat().st_size <= MAX_UPLOAD else None


def _slideshow(images: list[Path], outdir: str, secs: float = 3.0) -> Path | None:
    """Guest/inline replies can carry only one media item. Turn a photo
    carousel into a single mp4 slideshow (each image `secs` seconds, padded
    onto a square canvas) so all of them come through in one message."""
    if len(images) < 2:
        return None
    listfile = Path(outdir) / "_slides.txt"
    lines = []
    for p in images:
        lines.append(f"file '{p.as_posix()}'")
        lines.append(f"duration {secs}")
    lines.append(f"file '{images[-1].as_posix()}'")  # concat demuxer quirk
    listfile.write_text("\n".join(lines))
    out = Path(outdir) / "_slideshow.mp4"
    vf = ("scale=1080:1080:force_original_aspect_ratio=decrease,"
          "pad=1080:1080:(ow-iw)/2:(oh-ih)/2:color=white,"
          "setsar=1,fps=30,format=yuv420p")
    cmd = [
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listfile),
        "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
        "-movflags", "+faststart", str(out),
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=300)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        log.warning("ffmpeg slideshow failed: %s", e)
        return None
    return out if out.exists() and out.stat().st_size <= MAX_UPLOAD else None


def _probe(path: Path) -> dict:
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height:format=duration",
             "-of", "default=nw=1:nk=1", str(path)],
            capture_output=True, text=True, timeout=30, check=True,
        )
        w, h, dur = r.stdout.split()[:3]
        return {"width": int(w), "height": int(h), "duration": int(float(dur))}
    except Exception:  # noqa: BLE001
        return {}


def _caption(meta: dict, url: str) -> str:
    title = re.sub(r"\s+", " ", (meta.get("title") or "").strip())
    if len(title) > 800:
        title = title[:800] + "…"
    uploader = meta.get("uploader") or ""
    tail = f'<a href="{url}">source</a>'
    if uploader:
        tail = f"@{uploader.lstrip('@')} · " + tail
    return "\n\n".join(p for p in (title, tail) if p)[:1024]


async def _send_media(msg: Message, files: list[Path], caption: str) -> None:
    prepared: list[Path] = []
    skipped = 0
    for f in files:
        if f.stat().st_size <= MAX_UPLOAD:
            prepared.append(f)
        elif f.suffix.lower() in VIDEO_EXT and (s := await asyncio.to_thread(_shrink_video, f)):
            prepared.append(s)
        else:
            skipped += 1

    note = f"\n\n⚠️ {skipped} file(s) too large for Telegram, skipped." if skipped else ""
    cap = (caption + note)[:1024]

    vids = [f for f in prepared if f.suffix.lower() in VIDEO_EXT]
    imgs = [f for f in prepared if f.suffix.lower() in IMAGE_EXT]
    auds = [f for f in prepared if f.suffix.lower() in AUDIO_EXT]

    if len(vids) == 1 and not imgs and not auds:
        await bot.send_video(msg.chat.id, FSInputFile(vids[0]), caption=cap,
                             supports_streaming=True,
                             reply_to_message_id=msg.message_id, **_probe(vids[0]))
        return
    if len(imgs) == 1 and not vids and not auds:
        await bot.send_photo(msg.chat.id, FSInputFile(imgs[0]), caption=cap,
                             reply_to_message_id=msg.message_id)
        return

    group_files = vids + imgs
    first = True
    for i in range(0, len(group_files), 10):
        group = []
        for f in group_files[i:i + 10]:
            c = cap if first else None
            first = False
            if f.suffix.lower() in VIDEO_EXT:
                group.append(InputMediaVideo(media=FSInputFile(f), caption=c,
                                             supports_streaming=True))
            else:
                group.append(InputMediaPhoto(media=FSInputFile(f), caption=c))
        if group:
            await bot.send_media_group(msg.chat.id, group,
                                       reply_to_message_id=msg.message_id)

    for f in auds:
        await bot.send_audio(msg.chat.id, FSInputFile(f),
                             reply_to_message_id=msg.message_id)

    if not prepared:
        raise RuntimeError("all files were too large for Telegram")


# --------------------------------------------------------------------------- #
# handlers
# --------------------------------------------------------------------------- #
async def handle_url(msg: Message, url: str) -> None:
    async with _sem:
        await bot.send_chat_action(msg.chat.id, ChatAction.UPLOAD_VIDEO)
        tmp = tempfile.mkdtemp(prefix="tgdl-", dir=str(STATE_DIR))
        try:
            meta, files = await _fetch_any(url, tmp)
            await _send_media(msg, files, _caption(meta, url))
        except Exception as e:  # noqa: BLE001
            log.exception("failed on %s", url)
            await msg.reply(f"❌ Couldn't download that link.\n<code>{_esc(str(e))}</code>")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


HELP = (
    "Send me a <b>TikTok</b>, <b>Instagram</b> or <b>YouTube</b> link and I'll "
    "send back the video or photos — no watermark, no ads.\n\n"
    "Works with short links (vt.tiktok.com/…), reels, YouTube Shorts, posts and "
    "photo slideshows. Several links in one message are fine.\n\n"
    "You can also use me without adding me to a chat: reply to someone's "
    "link with a mention of @yetdlpbot, or just mention me together with a "
    "link, and I'll post the media right there."
)


# --------------------------------------------------------------------------- #
# guest / inline media delivery helpers
# --------------------------------------------------------------------------- #
def _extract_supported_url(text: str) -> str | None:
    for u in URL_RE.findall(text or ""):
        u = u.rstrip(").,]'\"")
        if _platform(u):
            return u
    return None


def _stash_targets(user_id: int) -> list[int]:
    """Where to upload the file to mint a file_id, best first: the requester's
    own DM, then an explicit STASH_CHAT_ID, then anyone on the allowlist (the
    owner has certainly /start-ed the bot). Guests who never opened a DM with
    the bot can't be sent to directly (Telegram 403)."""
    out: list[int] = []
    for t in [user_id, int(STASH_CHAT_ID) if STASH_CHAT_ID else None, *sorted(ALLOWED)]:
        if t is not None and t not in out:
            out.append(t)
    return out


async def _stash_and_get_file_id(user_id: int, files: list[Path]) -> tuple[str, str, str]:
    """Inline message edits can't take a raw file upload — only a file_id or
    URL. Upload the first item to a chat we can post to, mint a file_id, then
    delete that stash message."""
    f = files[0]
    is_video = f.suffix.lower() in VIDEO_EXT
    last_err: Exception | None = None
    for chat_id in _stash_targets(user_id):
        try:
            if is_video:
                msg = await bot.send_video(chat_id, FSInputFile(f),
                                           supports_streaming=True, **_probe(f))
                file_id, kind = msg.video.file_id, "video"
            else:
                msg = await bot.send_photo(chat_id, FSInputFile(f))
                file_id, kind = msg.photo[-1].file_id, "photo"
        except (TelegramForbiddenError, TelegramBadRequest) as e:
            last_err = e
            continue
        try:
            await bot.delete_message(chat_id, msg.message_id)
        except Exception:  # noqa: BLE001
            pass
        extra = len(files) - 1
        note = (f"\n\n(+{extra} more in this post — message me the link directly for all of them)"
                if extra else "")
        return file_id, kind, note
    raise RuntimeError(
        "couldn't stage this file for in-chat delivery — open a DM with "
        "@yetdlpbot (send it /start) once, then try again"
    ) from last_err


async def _deliver_media_via_inline_edit(imid: str, user_id: int, url: str) -> None:
    """Download `url` and turn the placeholder inline/guest message at
    `imid` into the real video/photo (or an error) via edit_message_media."""
    async with _sem:
        tmp = tempfile.mkdtemp(prefix="tgdl-", dir=str(STATE_DIR))
        try:
            meta, files = await _fetch_any(url, tmp)
            # A guest/inline reply is a single item. If the post is a photo
            # carousel, stitch every image into one slideshow video so none
            # are lost; fall back to first-photo-plus-note if that fails.
            if len(files) > 1 and all(f.suffix.lower() in IMAGE_EXT for f in files):
                slides = await asyncio.to_thread(_slideshow, files, tmp)
                if slides:
                    files = [slides]
            file_id, kind, note = await _stash_and_get_file_id(user_id, files)
            cap = (_caption(meta, url) + note)[:1024]
            media = (InputMediaVideo(media=file_id, caption=cap, supports_streaming=True)
                     if kind == "video" else InputMediaPhoto(media=file_id, caption=cap))
            await bot.edit_message_media(inline_message_id=imid, media=media)
        except Exception as e:  # noqa: BLE001
            log.exception("inline delivery failed for %s", url)
            try:
                await bot.edit_message_text(f"❌ Couldn't download that link.\n{_esc(str(e))}",
                                            inline_message_id=imid)
            except Exception:  # noqa: BLE001
                pass
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------- #
# guest mode — @mention the bot, or reply to a message with a link and
# mention it, in any chat it isn't even a member of. Needs "Guest Mode"
# turned on for this bot in BotFather's Mini App (Bot Settings).
# --------------------------------------------------------------------------- #
@dp.guest_message()
async def on_guest_message(msg: Message) -> None:
    if ALLOWED and msg.from_user and msg.from_user.id not in ALLOWED:
        return

    # A guest_message also fires when someone just replies to one of the
    # bot's own messages ("HAHAHA" under a video it posted). Don't treat the
    # bot's own caption (which carries the source link) as a fetch request.
    replied = msg.reply_to_message
    replied_is_ours = bool(replied and replied.from_user and replied.from_user.id == BOT_ID)

    url = None
    if replied and not replied_is_ours:
        url = _extract_supported_url(replied.text or replied.caption or "")
    if not url:
        url = _extract_supported_url(msg.text or msg.caption or "")
    if not url:
        return  # nothing to do — stay silent rather than spam a hint

    sent = await bot.answer_guest_query(
        msg.guest_query_id,
        result=InlineQueryResultArticle(
            id="0", title="yetdlp",
            input_message_content=InputTextMessageContent(message_text=f"⏳ Fetching {url} …"),
        ),
    )
    await _deliver_media_via_inline_edit(sent.inline_message_id, msg.from_user.id, url)


@dp.message(CommandStart())
async def on_start(msg: Message) -> None:
    await msg.answer(HELP)


@dp.message(Command("help"))
async def on_help(msg: Message) -> None:
    await msg.answer(HELP)


@dp.message(Command("selfcheck"))
async def on_selfcheck(msg: Message) -> None:
    """Admin: run the media self-check now. `/selfcheck fail` injects a
    synthetic failure so the alert path can be exercised."""
    if ALLOWED and (not msg.from_user or msg.from_user.id not in ALLOWED):
        return
    arg = (msg.text or "").partition(" ")[2].strip().lower()
    await msg.answer("running self-check…")
    extra = [("Synthetic failure (test)", "FAIL")] if arg == "fail" else None
    results = await run_selfcheck(extra)
    report = _format_selfcheck(results)
    await msg.answer(report)
    if any(not r.ok for r in results):
        await _notify_selfcheck(report, also_skip=msg.chat.id)


@dp.message(F.text)
async def on_text(msg: Message) -> None:
    if ALLOWED and msg.from_user and msg.from_user.id not in ALLOWED:
        return
    urls = [u.rstrip(").,]'\"") for u in URL_RE.findall(msg.text or "")]
    urls = [u for u in urls if _platform(u)]
    if not urls:
        if msg.chat.type == "private":
            await msg.reply("Send me a TikTok, Instagram or YouTube link. /help for details.")
        return
    for url in urls:
        await handle_url(msg, url)


# --------------------------------------------------------------------------- #
# daily self-check
# --------------------------------------------------------------------------- #
# One canonical link per media shape. When a link rots it shows up as a failure
# in the daily report (which is the point) — swap it here when that happens.
SELFCHECK_CASES: list[tuple[str, str]] = [
    ("TikTok · video", "https://vt.tiktok.com/ZSVvsAodq/"),
    ("TikTok · photo post",
     "https://www.tiktok.com/@m6010283/photo/7678391802965052680"),
    ("Instagram · reel", "https://www.instagram.com/reel/DctvpfyzQYM/"),
    ("Instagram · single photo", "https://www.instagram.com/p/DcyibZtoO_9/"),
    ("Instagram · photo carousel", "https://www.instagram.com/p/Dcyij21CEbH/"),
    ("YouTube · Shorts", "https://www.youtube.com/shorts/W-VQ9xKFdUs"),
]


class _CheckResult:
    __slots__ = ("label", "ok", "detail", "secs")

    def __init__(self, label: str, ok: bool, detail: str, secs: float) -> None:
        self.label, self.ok, self.detail, self.secs = label, ok, detail, secs


async def _run_one_check(label: str, url: str) -> _CheckResult:
    t0 = time.monotonic()
    if url == "FAIL":  # synthetic case for `/selfcheck fail`
        return _CheckResult(label, False, "synthetic failure (notification test)", 0.0)
    tmp = tempfile.mkdtemp(prefix="tgdl-chk-", dir=str(STATE_DIR))
    try:
        _, files = await _fetch_any(url, tmp)
        kinds: dict[str, int] = {}
        for f in files:
            k = ("video" if f.suffix.lower() in VIDEO_EXT
                 else "image" if f.suffix.lower() in IMAGE_EXT else "file")
            kinds[k] = kinds.get(k, 0) + 1
        detail = ", ".join(f"{n} {k}" for k, n in kinds.items()) or "0 files"
        return _CheckResult(label, True, detail, time.monotonic() - t0)
    except Exception as e:  # noqa: BLE001
        first = (str(e).splitlines() or [""])[0]
        return _CheckResult(label, False, first[:180] or e.__class__.__name__,
                            time.monotonic() - t0)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


async def run_selfcheck(extra: list[tuple[str, str]] | None = None) -> list[_CheckResult]:
    out: list[_CheckResult] = []
    for label, url in list(SELFCHECK_CASES) + list(extra or []):
        async with _sem:
            out.append(await _run_one_check(label, url))
    return out


def _format_selfcheck(results: list[_CheckResult]) -> str:
    bad = [r for r in results if not r.ok]
    n = len(results)
    head = (f"⚠️ <b>yetdlp self-check — {len(bad)}/{n} FAILING</b>" if bad
            else f"✅ <b>yetdlp self-check — all {n} OK</b>")
    w = max(len(r.label) for r in results)
    rows = "\n".join(
        f"{'ok  ' if r.ok else 'FAIL'}  {r.label.ljust(w)}   {r.detail}  ·  {r.secs:.1f}s"
        for r in results
    )
    parts = [head, f"<pre>{_esc(rows)}</pre>"]
    if bad:
        hint: list[str] = []
        labels = [r.label.lower() for r in bad]
        if any("tiktok" in x for x in labels):
            hint.append("tikwm / TikTok")
        if any("reel" in x for x in labels):
            hint.append("yt-dlp / Instagram anon")
        if any("instagram" in x and "photo" in x for x in labels):
            hint.append("IG photos blocked from this IP (sssinstagram CAPTCHA) — needs cookies/proxy")
        if any("youtube" in x for x in labels):
            hint.append("loader.to / YouTube")
        if hint:
            parts.append("Likely: " + "; ".join(dict.fromkeys(hint)))
        parts.append(f"{n - len(bad)}/{n} media types still working.")
    parts.append(f"<i>host {os.uname().nodename} · "
                 f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}</i>")
    return "\n\n".join(parts)[:4000]


def _notify_chat_id() -> int | str | None:
    target = SELFCHECK_NOTIFY or (str(min(ALLOWED)) if ALLOWED else "")
    if not target:
        return None
    return int(target) if re.fullmatch(r"-?\d+", target) else target


async def _notify_selfcheck(report: str, also_skip: int | None = None) -> None:
    chat = _notify_chat_id()
    if chat is None or chat == also_skip:
        return
    try:
        await bot.send_message(chat, report)
    except Exception:  # noqa: BLE001
        log.exception("self-check: could not notify %s", chat)


def _secs_until(hhmm: str) -> float:
    try:
        hh, mm = (int(x) for x in hhmm.split(":", 1))
    except Exception:  # noqa: BLE001
        hh, mm = 9, 0
    now = datetime.now(timezone.utc)
    nxt = now.replace(hour=hh % 24, minute=mm % 60, second=0, microsecond=0)
    if nxt <= now:
        nxt += timedelta(days=1)
    return (nxt - now).total_seconds()


async def _selfcheck_loop() -> None:
    if not SELFCHECK_ENABLE:
        log.info("self-check: disabled")
        return
    log.info("self-check: daily at %s UTC, notify=%s", SELFCHECK_AT, _notify_chat_id())
    while True:
        await asyncio.sleep(_secs_until(SELFCHECK_AT))
        try:
            results = await run_selfcheck()
            bad = [r for r in results if not r.ok]
            log.info("self-check: %d/%d failing%s", len(bad), len(results),
                     "" if not bad else " — " + ", ".join(r.label for r in bad))
            if bad:
                await _notify_selfcheck(_format_selfcheck(results))
        except Exception:  # noqa: BLE001
            log.exception("self-check: run failed")
        await asyncio.sleep(90)  # don't re-fire within the same minute


def _ensure_migrated_to_local_api() -> None:
    """Telegram requires a bot to logOut of the cloud API once before it can be
    used with a self-hosted server. Idempotent via a marker file."""
    if not TELEGRAM_API_BASE:
        return
    marker = STATE_DIR / ".cloud-logged-out"
    if marker.exists():
        return
    try:
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{TOKEN}/logOut", method="POST")
        urllib.request.urlopen(req, timeout=30).read()
        marker.write_text("")
        log.info("logged out of cloud Bot API; now bound to %s", TELEGRAM_API_BASE)
    except urllib.error.HTTPError as e:
        # 401 == already migrated / no active cloud session — fine, mark done.
        if e.code in (401, 429):
            marker.write_text("")
        log.warning("cloud logOut -> HTTP %s (continuing)", e.code)
    except Exception as e:  # noqa: BLE001
        log.warning("cloud logOut failed: %s (will retry next start)", e)


async def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    _ensure_migrated_to_local_api()
    me = await bot.get_me()
    log.info("starting as @%s (id=%s); allowlist=%s; cookies=%s; api=%s",
             me.username, me.id, ALLOWED or "everyone", COOKIES.exists(),
             TELEGRAM_API_BASE or "cloud")
    checker = asyncio.create_task(_selfcheck_loop())
    try:
        await dp.start_polling(bot)
    finally:
        checker.cancel()
        await sss.close()


if __name__ == "__main__":
    asyncio.run(main())
