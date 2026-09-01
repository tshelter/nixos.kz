"""Instagram fallback via sssinstagram.com.

yt-dlp can't fetch Instagram photo posts / carousels anonymously. sssinstagram
can, but its /api/convert request is signed (HMAC-SHA256 over target_url+ts
with a static build-time key, verified server-side) by obfuscated front-end
JS. Rather than keep the key in sync with their deploys, we drive the real
page in a headless browser and intercept the JSON response it gets back.

One Chromium is kept alive between requests and reaped after IDLE_TIMEOUT of
inactivity, so a long-idle bot doesn't hold the memory. Requests are
serialized (the page's Vue state is single-slot) — fine for a fallback path.
"""

from __future__ import annotations

import asyncio
import logging
import time

from playwright.async_api import async_playwright

log = logging.getLogger("tgbot-dl.sssig")

IDLE_TIMEOUT = 900  # seconds; drop the browser after this long unused
HOME = "https://sssinstagram.com/en1"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")

_CHROMIUM_ARGS = [
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
    "--single-process",
    "--no-zygote",
    "--disable-extensions",
    "--mute-audio",
    "--js-flags=--max-old-space-size=128",
]


def _parse(data: dict) -> dict:
    items = []
    for it in data.get("url") or []:
        u = it.get("url")
        if not u:
            continue
        ext = (it.get("ext") or it.get("type") or "").lower()
        kind = "video" if ext in ("mp4", "mov", "webm", "m4v") else "image"
        items.append({"url": u, "ext": ext or ("mp4" if kind == "video" else "jpg"),
                      "kind": kind})
    meta = data.get("meta") or {}
    return {"items": items, "title": meta.get("title") or "",
            "username": meta.get("username") or ""}


class SssInstagram:
    def __init__(self) -> None:
        self._pw = None
        self._browser = None
        self._page = None
        self._lock = asyncio.Lock()
        self._last_used = 0.0
        self._reaper: asyncio.Task | None = None

    async def _ensure(self) -> None:
        if self._page is not None and not self._page.is_closed():
            return
        await self._shutdown()  # clean any half-open state first
        if self._pw is None:
            self._pw = await async_playwright().start()
        self._browser = await self._pw.chromium.launch(headless=True, args=_CHROMIUM_ARGS)
        ctx = await self._browser.new_context(user_agent=UA, locale="en-US")
        self._page = await ctx.new_page()
        await self._page.goto(HOME, wait_until="networkidle", timeout=60000)
        if self._reaper is None or self._reaper.done():
            self._reaper = asyncio.create_task(self._reap())
        log.info("chromium up")

    async def _reap(self) -> None:
        try:
            while True:
                await asyncio.sleep(120)
                async with self._lock:
                    if self._page is not None and \
                            time.monotonic() - self._last_used > IDLE_TIMEOUT:
                        log.info("chromium idle >%ds, shutting down", IDLE_TIMEOUT)
                        await self._shutdown()
                        return
        except asyncio.CancelledError:
            pass

    async def _shutdown(self) -> None:
        for obj, meth in ((self._browser, "close"), (self._pw, "stop")):
            try:
                if obj is not None:
                    await getattr(obj, meth)()
            except Exception:  # noqa: BLE001
                pass
        self._browser = self._page = self._pw = None

    async def close(self) -> None:
        if self._reaper is not None:
            self._reaper.cancel()
        async with self._lock:
            await self._shutdown()

    async def fetch(self, url: str) -> dict:
        """{'items':[{url,ext,kind}], 'title', 'username'} for an Instagram URL."""
        async with self._lock:
            try:
                await self._ensure()
                page = self._page
                assert page is not None

                await page.fill("#input", url)
                await page.wait_for_timeout(400)
                async with page.expect_response(
                    lambda r: "/api/convert" in r.url and r.request.method == "POST",
                    timeout=45000,
                ) as got:
                    await page.click("button.form__submit")
                resp = await got.value
                if not resp.ok:
                    raise RuntimeError(f"sssinstagram returned HTTP {resp.status}")
                data = await resp.json()
                try:
                    await page.click("button.btn-clear", timeout=3000)
                except Exception:  # noqa: BLE001
                    pass  # cosmetic reset only
            except Exception:
                # a wedged page/context is not worth keeping around
                await self._shutdown()
                raise
            finally:
                self._last_used = time.monotonic()

        result = _parse(data)
        if not result["items"]:
            raise RuntimeError(data.get("error") or "sssinstagram found no media for this link")
        return result
