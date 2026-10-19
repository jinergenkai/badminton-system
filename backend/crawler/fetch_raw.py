#!/usr/bin/env python3
"""Lấy envelope API bằng chữ ký x-user-app sinh theo thời gian."""
from __future__ import annotations

import os
from pathlib import Path
import time
from typing import Any
from urllib.parse import quote, urlencode

import httpx

from gen_x_user_app import generate_x_user_app


_BASE_URL = "https://user-global.alobo.vn/v2/user/branch"
_WEB_BASE_URL = "https://datlich.alobo.vn"
_ENDPOINTS = {
    "get_onetime_bookings": "get_onetime_bookings",
    "get_schedule_bookings": "get_schedule_bookings",
    "get_lock_yards": "get_lock_yards/{branchId}",
    "get_cores": "get_cores/{branchId}",
    "get_core_types": "get_core_types/{branchId}",
    # 2.10.4: get_branch bị khoá -> 403 "Forbidden". App chuyển sang branch_info
    # (cùng là thông tin sân công khai). Giữ tên key "get_branch" để không đụng
    # scheduler/adapt; chỉ đổi PATH đích.
    "get_branch": "branch_info/{branchId}",
    "branch_info": "branch_info/{branchId}",
    "products": "products/{branchId}",
}

# Giữ browser sống trong suốt lifetime của scheduler để không phải khởi động
# Chromium ở mỗi request. Không ghi signature ra disk hay log.
_PLAYWRIGHT: Any = None
_BROWSER: Any = None
_CONTEXT: Any = None
_PAGE: Any = None
_SIGNATURE: str | None = None
# Bộ header x-* mà app THẬT gửi, bắt từ bootstrap (gồm x-version-app hiện hành).
# Không hardcode version -> ALOBO bump version cũng không gãy.
_APP_HEADERS: dict[str, str] = {}
_SIGNED_HEADER_KEYS = (
    "x-user-app", "x-version-app", "x-custom-lang", "x-name-app", "x-platform",
)
# Chỉ dùng khi KHÔNG bắt được từ app (fallback cũ). Cập nhật nếu cần.
_FALLBACK_VERSION = os.environ.get("ALOBO_X_VERSION_APP", "2.10.4")


def _dbg(*a: Any) -> None:
    if os.environ.get("ALOBO_DEBUG"):
        print("   [debug]", *a, flush=True)


def _mask(v: str | None) -> str:
    if not v:
        return repr(v)
    return f"{v[:8]}…{v[-4:]} (len {len(v)})" if len(v) > 16 else v


def fetch_raw(endpoint: str, params: dict) -> Any:
    """Trả envelope thô cho một endpoint, mặc định dùng chữ ký sinh cục bộ.

    Có thể đặt ``ALOBO_FETCH_MODE=playwright`` để dùng lại đường browser cũ.
    """
    global _PLAYWRIGHT, _BROWSER, _CONTEXT, _PAGE, _SIGNATURE

    if endpoint not in _ENDPOINTS:
        allowed = ", ".join(sorted(_ENDPOINTS))
        raise ValueError(f"Endpoint không hỗ trợ: {endpoint!r}. Chọn một trong: {allowed}.")
    if not isinstance(params, dict):
        raise TypeError("params phải là dict.")

    path = _ENDPOINTS[endpoint]
    query = dict(params)
    if "{branchId}" in path:
        try:
            path = path.format(branchId=quote(str(query.pop("branchId")), safe=""))
        except KeyError as exc:
            raise ValueError(f"{endpoint} cần params['branchId'].") from exc
    target_url = f"{_BASE_URL}/{path}"
    if query:
        target_url = f"{target_url}?{urlencode(query, doseq=True)}"

    # Mặc định gọi HTTP trực tiếp với chữ ký mới. Playwright vẫn có thể bật
    # explicit bằng ALOBO_FETCH_MODE=playwright để đối chiếu/fallback.
    mode_value = os.environ.get("ALOBO_FETCH_MODE")
    if mode_value is None:
        try:
            for line in Path(__file__).with_name(".env").read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                name, value = line.split("=", 1)
                if name.strip() == "ALOBO_FETCH_MODE":
                    mode_value = value.strip().strip("\"'")
                    break
        except FileNotFoundError:
            pass
    mode = (mode_value or "generated").lower()
    if mode in ("generated", "header"):
        signature = generate_x_user_app()
        headers = {
            "accept": "*/*",
            "accept-language": "vi-VN,vi;q=0.9,en-US;q=0.6,en;q=0.5",
            "origin": _WEB_BASE_URL,
            "referer": f"{_WEB_BASE_URL}/",
            "user-agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/153.0.0.0 Safari/537.36"
            ),
            "x-custom-lang": "vi",
            "x-name-app": "alobo-user",
            "x-platform": "web",
            "x-user-app": signature,
            "x-version-app": "2.10.4",
        }
        try:
            response = httpx.get(target_url, headers=headers, timeout=25.0)
            response.raise_for_status()
            body = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise RuntimeError(f"ALOBO GET {endpoint} thất bại qua header: {exc}") from exc
        if not isinstance(body, dict):
            raise RuntimeError("ALOBO response phải là JSON object/envelope.")
        return body
    if mode != "playwright":
        raise ValueError("ALOBO_FETCH_MODE chỉ nhận 'generated' (mặc định) hoặc 'playwright'.")

    if _PAGE is None or _PAGE.is_closed():
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as exc:
            raise RuntimeError(
                "Thiếu Playwright. Chạy: pip install -r requirements.txt && "
                "python -m playwright install chromium"
            ) from exc

        _PLAYWRIGHT = sync_playwright().start()
        launch_args = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage"]}
        chrome_path = os.environ.get("ALOBO_CHROME_PATH")
        if not chrome_path:
            try:
                for line in Path(__file__).with_name(".env").read_text(encoding="utf-8").splitlines():
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    name, value = line.split("=", 1)
                    if name.strip() == "ALOBO_CHROME_PATH":
                        chrome_path = value.strip().strip("\"'")
                        break
            except FileNotFoundError:
                pass
        if not chrome_path:
            for candidate in (
                r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                "/usr/bin/google-chrome",
                "/usr/bin/chromium",
            ):
                if Path(candidate).is_file():
                    chrome_path = candidate
                    break
        if chrome_path:
            launch_args["executable_path"] = chrome_path
        # PLAYWRIGHT_WS (vd ws://<container chromium>:3000/) → nối vào Playwright server dùng
        # chung trên Dokploy thay vì tự mở Chromium. Client phải cùng major.minor với server.
        ws_endpoint = os.environ.get("PLAYWRIGHT_WS", "").strip()
        try:
            if ws_endpoint:
                _BROWSER = _PLAYWRIGHT.chromium.connect(ws_endpoint, timeout=30_000)
            else:
                _BROWSER = _PLAYWRIGHT.chromium.launch(**launch_args)
            _CONTEXT = _BROWSER.new_context(
                locale="vi-VN", viewport={"width": 1366, "height": 900}
            )
            _PAGE = _CONTEXT.new_page()
            _PAGE.set_default_timeout(30_000)

            def capture_signature(request: Any) -> None:
                global _SIGNATURE, _APP_HEADERS
                if request.url.startswith("https://user-global.alobo.vn/"):
                    hdrs = request.headers
                    value = hdrs.get("x-user-app")
                    if value:
                        _SIGNATURE = value
                        # chụp nguyên bộ x-* app thật gửi (gồm x-version-app hiện hành)
                        _APP_HEADERS = {
                            k: hdrs[k] for k in _SIGNED_HEADER_KEYS if hdrs.get(k)
                        }

            _PAGE.on("request", capture_signature)
        except Exception as exc:
            _PAGE = _CONTEXT = _BROWSER = _PLAYWRIGHT = None
            where = f"Playwright server {ws_endpoint}" if ws_endpoint else "Chrome"
            raise RuntimeError(f"Không thể khởi động {where} cho ALOBO: {exc}") from exc

    def refresh_signature() -> None:
        """Buộc app phát request bootstrap và chờ header ký mới trong RAM."""
        global _SIGNATURE
        _SIGNATURE = None
        branch_id = str(params.get("branchId", ""))
        bootstrap_url = f"{_WEB_BASE_URL}/san/{quote(branch_id, safe='')}" if branch_id else _WEB_BASE_URL
        _dbg("bootstrap:", bootstrap_url)
        _PAGE.goto(bootstrap_url, wait_until="domcontentloaded", timeout=60_000)
        deadline = time.monotonic() + 12
        while _SIGNATURE is None and time.monotonic() < deadline:
            _PAGE.wait_for_timeout(200)
        if not _SIGNATURE:
            raise RuntimeError("App ALOBO không phát x-user-app trong 12 giây.")

    try:
        if not _SIGNATURE:
            refresh_signature()

        _dbg("signature:", _mask(_SIGNATURE))
        _dbg("app x-* bắt được:", {k: (_mask(v) if k == "x-user-app" else v)
                                   for k, v in _APP_HEADERS.items()} or "(RỖNG!)")
        _dbg("GET", target_url)

        result: dict[str, Any] | None = None
        for attempt in range(2):
            # Dùng ĐÚNG bộ x-* app thật vừa gửi (gồm x-version-app hiện hành);
            # chỉ bù mặc định nếu thiếu, không hardcode version cũ nữa.
            headers = {"accept": "*/*"}
            headers.update(_APP_HEADERS)
            headers.setdefault("x-user-app", _SIGNATURE or "")
            headers.setdefault("x-custom-lang", "vi")
            headers.setdefault("x-name-app", "alobo-user")
            headers.setdefault("x-platform", "web")
            headers.setdefault("x-version-app", _FALLBACK_VERSION)
            result = _PAGE.evaluate(
                """async ({url, headers}) => {
                    const response = await fetch(url, {headers});
                    let text = null, body = null;
                    try { text = await response.text(); } catch (_) {}
                    try { body = JSON.parse(text); } catch (_) {}
                    const rh = {};
                    ['x-ratelimit-remaining','cf-ray','www-authenticate','retry-after']
                      .forEach(k => { const v = response.headers.get(k); if (v) rh[k]=v; });
                    return {status: response.status, body, text, respHeaders: rh};
                }""",
                {"url": target_url, "headers": headers},
            )
            _dbg(f"attempt {attempt}: HTTP {result.get('status')}",
                 "| resp-headers:", result.get("respHeaders"))
            _dbg("  body/text:", (result.get("text") or "")[:400])
            if result.get("status") not in (401, 403) or attempt:
                break
            _dbg("  -> 401/403, refresh chữ ký rồi thử lại 1 lần")
            refresh_signature()
    except Exception as exc:
        raise RuntimeError(f"ALOBO GET {endpoint} thất bại qua Playwright: {exc}") from exc

    if not result or result.get("status") < 200 or result.get("status") >= 300:
        status = result.get("status") if result else "không rõ"
        raise RuntimeError(f"ALOBO GET {endpoint} thất bại: HTTP {status}.")
    body = result.get("body")
    if not isinstance(body, dict):
        raise RuntimeError("ALOBO response phải là JSON object/envelope.")
    return body
