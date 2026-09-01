# yetdlp

Telegram bot **@yetdlpbot** — sends back TikTok / Instagram videos and photos
with no watermark and no ads. Runs on `a.zxc.sx` as the `yetdlp` systemd
service (see `../yetdlp.nix`).

## How it works

- **TikTok** (`vt.tiktok.com/…`, `tiktok.com/@user/video/…`, photo slideshows):
  fetched via the `tikwm.com` API — clean no-watermark MP4, or all slideshow
  images. Falls back to `yt-dlp` if the API is down.
- **Instagram** (reels, video posts): `yt-dlp` first. When that fails (photo
  posts / carousels yt-dlp can't fetch anonymously, or a rate-limit) it falls
  back to **sssinstagram.com**, driven through a headless Chromium
  (`sssig.py`) — their `/api/convert` request is signed by obfuscated JS, so
  rather than keep a static key in sync with their deploys we drive the real
  page and read the JSON response it gets back. One Chromium is kept warm and
  reaped after 15 min idle. You can still drop a `cookies.txt` into
  `/var/lib/yetdlp/` for yt-dlp as a first-line option, but it's optional now.
- Files over Telegram's 49 MB bot limit are re-encoded with ffmpeg to fit;
  if still too big they're skipped with a note.

## Config

Environment, supplied by the agenix secret `../secret/yetdlp.age`
(shell `KEY=VALUE` lines):

| var | meaning |
|-----|---------|
| `BOT_TOKEN` | Telegram bot token (required) |
| `ALLOWED_USER_IDS` | space/comma separated user ids; empty = everyone |
| `MAX_UPLOAD_MB` | max upload size, default 49 |
| `MAX_CONCURRENCY` | simultaneous downloads, default 3 |

`STATE_DIR` is set to `/var/lib/yetdlp` by the unit.

### Editing the secret

```sh
cd hosts/a/secret
agenix -e yetdlp.age      # needs one of the recipient keys in secrets.nix
```

## Run locally

```sh
python -m venv .venv && .venv/bin/pip install aiogram yt-dlp
BOT_TOKEN=… STATE_DIR=./state .venv/bin/python bot.py
```

## Deploy

```sh
make switch-a      # or: nix run nixpkgs#deploy-rs -- .#a
journalctl -u yetdlp -f
```
