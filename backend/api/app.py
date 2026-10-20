#!/usr/bin/env python3
"""backend/api — HTTP API nhỏ (stdlib) trên SQLite.

Chức năng:
  GET  /api/health                 -> {ok:true}
  GET  /api/roster                 -> danh bạ người chơi (nguồn chung)
  POST /api/players                 -> tạo/sửa người chơi (Flutter/host); đẩy mirror lên Blob
  POST /api/sync/matches            -> Flutter đẩy trận; tính lại Elo
  GET  /api/ranking                 -> bảng xếp hạng (Elo)
  GET  /api/pickup?session=<id>     -> gợi ý xoay người cho một buổi
  POST /api/roster/reseed           -> kéo lại danh bạ từ sổ tiền (Blob) + đẩy mirror

Bảo vệ ghi (POST): từ internet phải kèm `Authorization: Bearer <API_TOKEN>`;
máy trong TRUSTED_NETS (WireGuard) thì khỏi token. Đọc (GET) mở.
id người chơi = id GỐC sổ tiền.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import db

TRUSTED_NETS = os.environ.get("TRUSTED_NETS", "127.0.0.1/32,10.8.0.3/32")
API_TOKEN = os.environ.get("API_TOKEN", "").strip()
BILLBOOK_URL = os.environ.get("BILLBOOK_URL", "").strip()          # vd https://<proj>.vercel.app/api/data
ROSTER_PUSH_URL = os.environ.get("ROSTER_PUSH_URL", "").strip()    # vd https://<proj>.vercel.app/api/roster
ROSTER_PUSH_TOKEN = os.environ.get("ROSTER_PUSH_TOKEN", "").strip()
# Cổng sân trống: proxy nội bộ sang service crawler (cùng docker network).
CRAWLER_URL = os.environ.get("CRAWLER_URL", "http://crawler:8000").rstrip("/")
CRAWLER_TOKEN = os.environ.get("CRAWLER_TOKEN", "").strip()   # để kích cào
ADMIN_PASS = os.environ.get("ADMIN_PASS", "").strip()         # gate đổi cấu hình / kích cào


def _pass_ok(given) -> bool:
    """Mật khẩu quản trị. Có ADMIN_PASS riêng thì so trực tiếp; không thì uỷ quyền
    về Vercel (BILLBOOK_URL = /api/data) — cùng nguồn mật khẩu sổ, khỏi lệch."""
    given = str(given or "")
    if not given:
        return False
    if ADMIN_PASS:
        import hmac
        return hmac.compare_digest(given, ADMIN_PASS)
    if BILLBOOK_URL:
        try:
            data = json.dumps({"pass": given, "check": 1}).encode("utf-8")
            req = urllib.request.Request(BILLBOOK_URL, data=data,
                                         headers={"content-type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status == 200
        except Exception:  # noqa: BLE001  (HTTPError 401 / mạng lỗi → coi như sai)
            return False
    return False


def _crawler_get(path: str):
    req = urllib.request.Request(CRAWLER_URL + path, headers={"accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def _crawler_post(path: str, body: dict, token: str = ""):
    data = json.dumps(body or {}).encode("utf-8")
    headers = {"content-type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(CRAWLER_URL + path, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, json.loads(r.read().decode("utf-8"))


def _nets() -> list:
    out = []
    for part in TRUSTED_NETS.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            out.append(ipaddress.ip_network(part, strict=False))
        except ValueError:
            pass
    return out


_TRUSTED = _nets()


def _trusted(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return any(addr in n for n in _TRUSTED)


def _token_ok(header: str) -> bool:
    if not API_TOKEN:
        return False
    given = str(header or "")
    if given.lower().startswith("bearer "):
        given = given[7:]
    return given.strip() == API_TOKEN


def fetch_billbook_members() -> list[dict]:
    """Kéo danh sách thành viên từ sổ tiền (Blob qua Vercel GET /api/data)."""
    if not BILLBOOK_URL:
        raise RuntimeError("Chưa đặt BILLBOOK_URL")
    req = urllib.request.Request(BILLBOOK_URL, headers={"accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        payload = json.load(r)
    data = payload.get("data") or {}
    members = data.get("members") or []
    out = []
    for m in members:
        if not isinstance(m, dict):
            continue
        out.append({
            "id": str(m.get("id") or "").strip(),
            "name": str(m.get("name") or "").strip() or "?",
            "avatar": m.get("av") if isinstance(m.get("av"), str) else "",
            "source": "billbook",
        })
    return [m for m in out if m["id"]]


def reseed_from_billbook() -> int:
    members = fetch_billbook_members()
    con = db.connect()
    try:
        for m in members:
            db.upsert_player(con, m)
        con.commit()
    finally:
        con.close()
    push_roster_mirror()
    return len(members)


def push_roster_mirror() -> bool:
    """Đẩy danh bạ (không gồm trường nặng ngoài avatar) lên Blob để web/Flutter đọc
    luôn-online. Thiếu cấu hình hoặc lỗi mạng -> chỉ cảnh báo, không làm sập request."""
    if not (ROSTER_PUSH_URL and ROSTER_PUSH_TOKEN):
        return False
    body = {"players": db.roster(active_only=True)}
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        ROSTER_PUSH_URL, data=data, method="POST",
        headers={"content-type": "application/json",
                 "authorization": "Bearer " + ROSTER_PUSH_TOKEN},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            r.read()
        return True
    except urllib.error.URLError as e:
        print(f"[roster-mirror] cảnh báo: {e}", flush=True)
        return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):  # bớt ồn
        pass

    def _send(self, code: int, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.send_header("cache-control", "no-store")
        # CORS: các GET (roster/ranking/pickup) là công khai nên cho mọi origin.
        # Frontend Vite trên Vercel gọi thẳng backend (khác origin) → cần header này.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    # ---- CORS preflight ----
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "content-type, authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.send_header("content-length", "0")
        self.end_headers()

    def _client_ip(self) -> str:
        return self.client_address[0] if self.client_address else ""

    def _may_write(self) -> bool:
        if _trusted(self._client_ip()):
            return True
        return _token_ok(self.headers.get("Authorization", ""))

    def _read_json(self):
        n = int(self.headers.get("content-length") or 0)
        if n <= 0:
            return {}
        raw = self.rfile.read(n)
        try:
            return json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    # ---- GET ----
    def do_GET(self):
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        q = parse_qs(u.query)
        try:
            if path == "/api/health":
                return self._send(200, {"ok": True, "players": db.players_count()})
            if path == "/api/roster":
                return self._send(200, {"players": db.roster(active_only=False)})
            if path == "/api/ranking":
                return self._send(200, {"ranking": db.ranking()})
            if path == "/api/pickup":
                sid = (q.get("session") or [""])[0]
                if not sid:
                    return self._send(400, {"error": "cần ?session=<id>"})
                return self._send(200, {"session": sid, "pickup": db.pickup(sid)})
            # --- Sân trống: proxy sang crawler (đọc công khai) ---
            if path == "/api/courts":
                data = _crawler_get("/api/data")
                stamp = None
                try:
                    stamp = (_crawler_get("/api/crawl").get("coverage") or {}).get("last_data_at")
                except Exception:  # noqa: BLE001
                    pass
                return self._send(200, {"updatedAt": stamp, "data": data})
            if path == "/api/courts/directory":
                return self._send(200, _crawler_get("/api/directory"))
            if path == "/api/courts/config":
                return self._send(200, _crawler_get("/api/config"))
            if path == "/api/courts/status":
                return self._send(200, _crawler_get("/api/crawl"))
            return self._send(404, {"error": "not found"})
        except Exception as e:  # noqa: BLE001
            return self._send(500, {"error": str(e)})

    # ---- POST ----
    def do_POST(self):
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        # Sân trống admin: gate bằng mật khẩu quản trị (ADMIN_PASS), không phải API_TOKEN.
        if path in ("/api/courts/crawl", "/api/courts/config"):
            body = self._read_json() or {}
            if not _pass_ok(body.get("pass")):
                return self._send(401, {"error": "sai mật khẩu quản trị"})
            try:
                if path == "/api/courts/crawl":
                    code, j = _crawler_post("/api/crawl/run", {}, CRAWLER_TOKEN)
                    return self._send(code, j)
                cfg = {k: v for k, v in body.items() if k != "pass"}
                code, j = _crawler_post("/api/config", cfg)
                return self._send(code, j)
            except urllib.error.HTTPError as e:
                return self._send(e.code, {"error": e.read().decode("utf-8", "ignore")})
            except Exception as e:  # noqa: BLE001
                return self._send(502, {"error": "không gọi được crawler: " + str(e)})
        if not self._may_write():
            return self._send(401, {"error": "cần Authorization: Bearer <API_TOKEN>"})
        body = self._read_json()
        if body is None:
            return self._send(400, {"error": "body không phải JSON"})
        try:
            if path == "/api/players":
                items = body.get("players") if isinstance(body.get("players"), list) else [body]
                con = db.connect()
                try:
                    ids = [db.upsert_player(con, p) for p in items]
                    con.commit()
                finally:
                    con.close()
                push_roster_mirror()
                return self._send(200, {"ok": True, "ids": ids})

            if path == "/api/sync/matches":
                matches = body.get("matches")
                if not isinstance(matches, list):
                    return self._send(400, {"error": "cần {matches:[...]}"})
                con = db.connect()
                try:
                    for s in (body.get("sessions") or []):
                        if isinstance(s, dict) and s.get("id"):
                            con.execute(
                                "INSERT OR REPLACE INTO sessions(id,played_on,court_cost,note)"
                                " VALUES(?,?,?,?)",
                                (str(s["id"]), str(s.get("played_on") or ""),
                                 float(s.get("court_cost") or 0), str(s.get("note") or "")),
                            )
                    saved = [db.save_match(con, m) for m in matches]
                    db.recompute_ratings(con)
                    con.commit()
                finally:
                    con.close()
                return self._send(200, {"ok": True, "saved": len(saved)})

            if path == "/api/roster/reseed":
                n = reseed_from_billbook()
                return self._send(200, {"ok": True, "seeded": n})

            return self._send(404, {"error": "not found"})
        except Exception as e:  # noqa: BLE001
            return self._send(500, {"error": str(e)})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()

    db.init_db()
    # Lần đầu DB rỗng mà có BILLBOOK_URL -> tự seed từ sổ tiền (migrate).
    if db.players_count() == 0 and BILLBOOK_URL:
        try:
            n = reseed_from_billbook()
            print(f"[seed] nạp {n} người từ sổ tiền", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"[seed] bỏ qua ({e})", flush=True)

    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"api chạy http://{args.host}:{args.port}  (players={db.players_count()})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
