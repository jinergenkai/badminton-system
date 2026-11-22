"""Test end-to-end cho backend/api — chỉ dùng stdlib, DB tạm, KHÔNG đụng data thật.

    cd backend/api
    python -m unittest discover -s tests -v

Dựng 2 server thật trên 127.0.0.1:
  - fake Vercel: GET/POST /api/data (sổ tiền + kiểm mật khẩu), POST /api/roster
    (đếm số lần backend đẩy mirror)
  - api (app.py) trỏ BILLBOOK_URL/ROSTER_PUSH_URL vào fake Vercel
"""
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
API_DIR = os.path.dirname(HERE)

PASS = "mat-khau-test"
TODAY = "2026-11-23"
YESTERDAY = "2026-11-22"


# ---------------- fake Vercel ----------------
class FakeVercel:
    members = []
    pushes = []


class FakeVercelHandler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/api/data"):
            return self._send(200, {"rev": 1, "data": {"members": FakeVercel.members, "sessions": []}})
        self._send(404, {})

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        if self.path.startswith("/api/data"):
            return self._send(200 if body.get("pass") == PASS else 401, {"ok": body.get("pass") == PASS})
        if self.path.startswith("/api/roster"):
            FakeVercel.pushes.append(body.get("players"))
            return self._send(200, {"ok": True})
        self._send(404, {})


def _serve(handler):
    srv = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


TMP = tempfile.mkdtemp(prefix="bm-api-test-")
VERCEL = _serve(FakeVercelHandler)
VBASE = f"http://127.0.0.1:{VERCEL.server_address[1]}"

# env TRƯỚC khi import app/db (chúng đọc env lúc import)
os.environ.update({
    "DB_PATH": os.path.join(TMP, "test.db"),
    "BILLBOOK_URL": VBASE + "/api/data",
    "ROSTER_PUSH_URL": VBASE + "/api/roster",
    "ROSTER_PUSH_TOKEN": "t",
    "ADMIN_PASS": "",            # trống -> api uỷ quyền kiểm mật khẩu về Vercel
    "API_TOKEN": "",
    "RESEED_MINUTES": "0",
    "TRUSTED_NETS": "127.0.0.1/32",
})
sys.path.insert(0, API_DIR)
import db   # noqa: E402
import app  # noqa: E402

db.init_db()
API = _serve(app.Handler)
BASE = f"http://127.0.0.1:{API.server_address[1]}"


def http(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def match(mid, a, b, sa, sb, day=TODAY, hh="10:00"):
    return {"id": mid, "played_at": f"{day}T{hh}:00.000", "ended_at": f"{day}T{hh}:30.000",
            "team_a": a, "team_b": b, "team_a_score": sa, "team_b_score": sb,
            "winner": "A" if sa > sb else "B", "rally_sequence": "", "duration_seconds": 600}


def elo_ref(matches, k=32, base=1000.0):
    """Cài đặt Elo độc lập để đối chiếu (không dùng code của db.py)."""
    r = {}
    for m in sorted(matches, key=lambda m: (m["played_at"], m["id"])):
        a, b = m["team_a"], m["team_b"]
        ra = sum(r.get(p, base) for p in a) / len(a)
        rb = sum(r.get(p, base) for p in b) / len(b)
        ea = 1 / (1 + 10 ** ((rb - ra) / 400))
        sa = 1.0 if m["winner"] == "A" else 0.0
        for p in a:
            r[p] = r.get(p, base) + k * (sa - ea)
        for p in b:
            r[p] = r.get(p, base) + k * ((1 - sa) - (1 - ea))
    return r


def reset_db():
    con = db.connect()
    for t in ("players", "matches", "match_players", "sessions"):
        con.execute(f"DELETE FROM {t}")
    con.commit()
    con.close()
    FakeVercel.members = [{"id": f"m{i}", "name": n, "av": ""} for i, n in
                          enumerate(["Nguyễn Mạnh Hùng", "Trần Văn An", "Lê Bình", "Phạm Cường",
                                     "Võ Dũng", "Đỗ Em"])]
    FakeVercel.pushes = []
    app.reseed_from_billbook()


class Base(unittest.TestCase):
    def setUp(self):
        reset_db()

    def ranking(self):
        st, j = http("GET", "/api/ranking")
        self.assertEqual(st, 200)
        return {p["id"]: p for p in j["ranking"]}


class TestElo(Base):
    def test_one_match_exact_numbers(self):
        st, j = http("POST", "/api/sync/matches", {"matches": [match("x1", ["m0", "m1"], ["m2", "m3"], 21, 15)]})
        self.assertEqual((st, j["saved"], j["unknown"]), (200, 1, []))
        r = self.ranking()
        # cả 4 bắt đầu 1000 -> kỳ vọng 0.5 -> thắng +16, thua -16
        self.assertEqual([r[p]["elo"] for p in ("m0", "m1", "m2", "m3")], [1016.0, 1016.0, 984.0, 984.0])
        self.assertEqual((r["m0"]["wins"], r["m0"]["losses"], r["m0"]["played"]), (1, 0, 1))
        self.assertEqual((r["m2"]["wins"], r["m2"]["losses"], r["m2"]["played"]), (0, 1, 1))
        self.assertNotIn("m4", r)  # chưa đánh -> không lên ranking

    def test_many_matches_match_reference_and_order(self):
        ms = [
            match("a", ["m0", "m1"], ["m2", "m3"], 21, 18, YESTERDAY, "19:00"),
            match("b", ["m0", "m2"], ["m1", "m4"], 15, 21, YESTERDAY, "19:20"),
            match("c", ["m3", "m5"], ["m0", "m4"], 22, 20, TODAY, "18:00"),
            match("d", ["m1", "m5"], ["m2", "m3"], 21, 9, TODAY, "18:25"),
            match("e", ["m0", "m1"], ["m4", "m5"], 19, 21, TODAY, "18:50"),
        ]
        # gửi NGƯỢC thứ tự: backend phải tự xếp theo played_at
        st, j = http("POST", "/api/sync/matches", {"matches": list(reversed(ms))})
        self.assertEqual((st, j["saved"]), (200, 5))
        ref = elo_ref(ms)
        r = self.ranking()
        for pid, want in ref.items():
            self.assertAlmostEqual(r[pid]["elo"], round(want, 1), places=1, msg=pid)
        # tổng Elo được bảo toàn (đánh đôi, cập nhật đều mỗi người)
        self.assertAlmostEqual(sum(p["elo"] for p in r.values()), 1000.0 * len(r), places=0)
        # thứ tự ranking = Elo giảm dần
        elos = [p["elo"] for p in http("GET", "/api/ranking")[1]["ranking"]]
        self.assertEqual(elos, sorted(elos, reverse=True))

    def test_resend_is_idempotent(self):
        ms = [match("a", ["m0", "m1"], ["m2", "m3"], 21, 18), match("b", ["m0", "m2"], ["m1", "m3"], 21, 11)]
        http("POST", "/api/sync/matches", {"matches": ms})
        first = self.ranking()
        for _ in range(3):
            http("POST", "/api/sync/matches", {"matches": ms})
        self.assertEqual(self.ranking(), first)
        self.assertEqual(first["m0"]["played"], 2)

    def test_resend_with_corrected_score_replaces(self):
        http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", "m1"], ["m2", "m3"], 21, 18)]})
        # cùng id, đổi người thắng (sửa nhầm) -> đè, không cộng dồn
        http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", "m1"], ["m2", "m3"], 18, 21)]})
        r = self.ranking()
        self.assertEqual((r["m0"]["wins"], r["m0"]["losses"], r["m0"]["played"]), (0, 1, 1))
        self.assertEqual(r["m2"]["elo"], 1016.0)

    def test_unknown_phone_id_is_reported_not_ranked(self):
        st, j = http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", "p12"], ["m2", "m3"], 21, 10)]})
        self.assertEqual(st, 200)
        self.assertEqual(j["unknown"], ["p12"])
        r = self.ranking()
        self.assertNotIn("p12", r)
        self.assertEqual(r["m0"]["played"], 1)  # người thật vẫn được tính

    def test_bad_payload(self):
        self.assertEqual(http("POST", "/api/sync/matches", {"x": 1})[0], 400)
        self.assertEqual(http("POST", "/api/sync/matches", {"matches": [{"team_a": ["m0"]}]})[0], 500)


class TestGuests(Base):
    def test_create_needs_admin_pass(self):
        self.assertEqual(http("POST", "/api/guests", {"pass": "sai", "name": "Khách A"})[0], 401)
        self.assertEqual(http("POST", "/api/guests", {"name": "Khách A"})[0], 401)

    def test_create_mark_dedupe_and_rank(self):
        pushes0 = len(FakeVercel.pushes)
        st, j = http("POST", "/api/guests", {"pass": PASS, "name": "Nguyễn Văn Tuấn"})
        self.assertEqual(st, 200)
        g = j["player"]
        self.assertTrue(g["id"].startswith("g-"))
        self.assertTrue(g["guest"])
        self.assertEqual(g["short"], "Tuấn*")
        self.assertEqual(len(FakeVercel.pushes), pushes0 + 1)  # mirror đẩy ngay cho phone
        # bấm lần 2 cùng tên -> cùng người
        self.assertEqual(http("POST", "/api/guests", {"pass": PASS, "name": "Nguyễn Văn Tuấn"})[1]["player"]["id"], g["id"])
        # tên ngắn dài bị cắt vừa 8 ký tự band, vẫn có dấu *
        s = http("POST", "/api/guests", {"pass": PASS, "name": "X", "short": "Abcdefghijk"})[1]["player"]["short"]
        self.assertEqual(s, "Abcdefg*")
        self.assertLessEqual(len(s), db.SHORT_MAX)
        self.assertEqual(http("POST", "/api/guests", {"pass": PASS, "name": "  "})[0], 400)
        # tên có ngoặc / ký tự lạ -> tên ngắn vẫn đọc được
        self.assertEqual(db.guest_short("Tuấn (bạn An)"), "Tuấn*")
        self.assertEqual(db.guest_short("Khách Quang!"), "Quang*")
        self.assertEqual(db.guest_short("(?)"), "Khach*")
        self.assertEqual(db.guest_short("Ai đó", "Bo*"), "Bo*")
        # khách đánh trận -> lên ranking, có cờ guest
        http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", g["id"]], ["m2", "m3"], 21, 10)]})
        r = self.ranking()
        self.assertTrue(r[g["id"]]["guest"])
        self.assertFalse(r["m0"]["guest"])

    def test_hide_only_guests(self):
        g = http("POST", "/api/guests", {"pass": PASS, "name": "Khách B"})[1]["player"]
        self.assertEqual(http("POST", "/api/guests/hide", {"pass": PASS, "id": "m0"})[0], 404)
        self.assertEqual(http("POST", "/api/guests/hide", {"pass": PASS, "id": g["id"]})[0], 200)
        ids = [p["id"] for p in http("GET", "/api/pickup?date=" + TODAY)[1]["pickup"]]
        self.assertNotIn(g["id"], ids)
        self.assertIn("m0", ids)

    def test_reseed_never_touches_guests(self):
        g = http("POST", "/api/guests", {"pass": PASS, "name": "Khách C"})[1]["player"]
        app.reseed_from_billbook()
        roster = {p["id"]: p for p in http("GET", "/api/roster")[1]["players"]}
        self.assertEqual(roster[g["id"]]["source"], "guest")
        self.assertEqual(roster[g["id"]]["active"], 1)


class TestReseed(Base):
    def test_new_member_appears_and_no_push_when_unchanged(self):
        n0 = len(FakeVercel.pushes)
        app.reseed_from_billbook(force_push=False)           # không đổi gì
        self.assertEqual(len(FakeVercel.pushes), n0)
        FakeVercel.members.append({"id": "newbie1", "name": "Người Mới", "av": ""})
        app.reseed_from_billbook(force_push=False)           # có người mới
        self.assertEqual(len(FakeVercel.pushes), n0 + 1)
        ids = [p["id"] for p in FakeVercel.pushes[-1]]
        self.assertIn("newbie1", ids)

    def test_reseed_keeps_ratings(self):
        http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", "m1"], ["m2", "m3"], 21, 10)]})
        FakeVercel.members[0]["name"] = "Hùng (đổi tên)"
        app.reseed_from_billbook()
        r = self.ranking()
        self.assertEqual(r["m0"]["elo"], 1016.0)
        self.assertEqual(r["m0"]["name"], "Hùng (đổi tên)")


class TestPickup(Base):
    def test_counts_per_day_and_order(self):
        http("POST", "/api/sync/matches", {"matches": [
            match("y1", ["m0", "m1"], ["m2", "m3"], 21, 10, YESTERDAY, "20:00"),
            match("t1", ["m0", "m1"], ["m2", "m3"], 21, 10, TODAY, "18:00"),
            match("t2", ["m0", "m4"], ["m1", "m5"], 21, 10, TODAY, "18:30"),
        ]})
        st, j = http("GET", "/api/pickup?date=" + TODAY)
        self.assertEqual(st, 200)
        self.assertEqual((j["date"], j["matches"]), (TODAY, 2))
        by = {p["id"]: p for p in j["pickup"]}
        self.assertEqual({k: by[k]["played"] for k in by},
                         {"m0": 2, "m1": 2, "m2": 1, "m3": 1, "m4": 1, "m5": 1})
        self.assertEqual(by["m0"]["last_played"][:16], TODAY + "T18:30")
        # ít trận trước; cùng 1 trận thì ai nghỉ lâu hơn (m2,m3 đánh 18:00) trước m4,m5 (18:30)
        order = [p["id"] for p in j["pickup"]]
        self.assertEqual(order[:2], ["m2", "m3"])
        self.assertEqual(set(order[2:4]), {"m4", "m5"})
        self.assertEqual(set(order[4:]), {"m0", "m1"})
        # hôm qua chỉ có 1 trận
        self.assertEqual(http("GET", "/api/pickup?date=" + YESTERDAY)[1]["matches"], 1)

    def test_default_today_and_bad_date(self):
        st, j = http("GET", "/api/pickup")
        self.assertEqual(st, 200)
        self.assertEqual(j["date"], db.today_vn())
        self.assertEqual(http("GET", "/api/pickup?date=23-11-2026")[0], 400)

    def test_session_mode_still_works(self):
        m = match("s1", ["m0", "m1"], ["m2", "m3"], 21, 10)
        m["session_id"] = "buoi1"
        http("POST", "/api/sync/matches", {"matches": [m]})
        st, j = http("GET", "/api/pickup?session=buoi1")
        self.assertEqual(st, 200)
        self.assertEqual({p["id"]: p["played"] for p in j["pickup"]}["m0"], 1)


def tearDownModule():
    API.shutdown()
    VERCEL.shutdown()
    shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
