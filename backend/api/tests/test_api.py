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


def elo_ref(matches, bases=None):
    """Cài đặt Elo độc lập để đối chiếu (không dùng code của db.py):
    khởi điểm theo trình (mặc định 1000), K=48 cho 10 trận đầu của mỗi người, sau đó 32."""
    bases = bases or {}
    r, n = {}, {}
    for m in sorted(matches, key=lambda m: (m["played_at"], m["id"])):
        a, b = m["team_a"], m["team_b"]
        get = lambda p: r.get(p, bases.get(p, 1000.0))  # noqa: E731
        ra = sum(get(p) for p in a) / len(a)
        rb = sum(get(p) for p in b) / len(b)
        ea = 1 / (1 + 10 ** ((rb - ra) / 400))
        sa = 1.0 if m["winner"] == "A" else 0.0
        k = lambda p: 48 if n.get(p, 0) < 10 else 32  # noqa: E731
        for p in a:
            r[p] = get(p) + k(p) * (sa - ea)
        for p in b:
            r[p] = get(p) + k(p) * ((1 - sa) - (1 - ea))
        for p in a + b:
            n[p] = n.get(p, 0) + 1
    return r


def reset_db():
    con = db.connect()
    for t in ("players", "matches", "match_players", "sessions", "boards"):
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
        # cả 4 bắt đầu 1000, đều là người mới (K=48) -> kỳ vọng 0.5 -> thắng +24, thua -24
        self.assertEqual([r[p]["elo"] for p in ("m0", "m1", "m2", "m3")], [1024.0, 1024.0, 976.0, 976.0])
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
        # ai cũng < 10 trận -> cùng K -> tổng Elo vẫn bảo toàn
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
        self.assertEqual(r["m2"]["elo"], 1024.0)

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


class TestLevels(Base):
    def set_level(self, pid, level, pw=PASS):
        return http("POST", "/api/players/level", {"pass": pw, "id": pid, "level": level})

    def test_level_sets_start_elo_and_recomputes(self):
        self.assertEqual(self.set_level("m0", "gioi")[0], 200)
        self.assertEqual(self.set_level("m1", "newbie")[0], 200)
        roster = {p["id"]: p for p in http("GET", "/api/roster")[1]["players"]}
        self.assertEqual((roster["m0"]["level"], roster["m0"]["elo"]), ("gioi", 1200.0))  # chưa đánh vẫn hiện Elo khởi điểm
        self.assertEqual(roster["m1"]["elo"], 800.0)
        self.assertEqual(roster["m2"]["elo"], 1000.0)
        ms = [match("a", ["m0", "m2"], ["m1", "m3"], 21, 12), match("b", ["m1", "m0"], ["m2", "m3"], 21, 19, hh="10:30")]
        http("POST", "/api/sync/matches", {"matches": ms})
        ref = elo_ref(ms, {"m0": 1200.0, "m1": 800.0})
        r = self.ranking()
        for pid in ("m0", "m1", "m2", "m3"):
            self.assertAlmostEqual(r[pid]["elo"], round(ref[pid], 1), places=1, msg=pid)
        # đổi trình SAU khi đã có trận -> Elo tính lại từ đầu với mốc mới
        self.set_level("m1", "tb")
        ref2 = elo_ref(ms, {"m0": 1200.0})
        self.assertAlmostEqual(self.ranking()["m1"]["elo"], round(ref2["m1"], 1), places=1)
        # bỏ đặt -> về 1000
        self.set_level("m0", "")
        self.assertAlmostEqual(self.ranking()["m0"]["elo"], round(elo_ref(ms)["m0"], 1), places=1)

    def test_k_drops_after_ten_games(self):
        ms = [match(f"k{i:02d}", ["m0", "m1"], ["m2", "m3"], 21, 10, hh=f"{8 + i // 4:02d}:{(i % 4) * 15:02d}") for i in range(12)]
        http("POST", "/api/sync/matches", {"matches": ms})
        ref = elo_ref(ms)
        r = self.ranking()
        self.assertAlmostEqual(r["m0"]["elo"], round(ref["m0"], 1), places=1)
        # tự tính tay trận 11: K phải là 32 chứ không còn 48
        r10 = elo_ref(ms[:10])
        ea = 1 / (1 + 10 ** (((r10["m2"] + r10["m3"]) / 2 - (r10["m0"] + r10["m1"]) / 2) / 400))
        self.assertAlmostEqual(elo_ref(ms[:11])["m0"] - r10["m0"], 32 * (1 - ea), places=6)

    def test_level_validation_and_auth(self):
        self.assertEqual(self.set_level("m0", "gioi", pw="sai")[0], 401)
        self.assertEqual(self.set_level("m0", "sieu-nhan")[0], 400)
        self.assertEqual(self.set_level("khong-co", "tb")[0], 404)

    def test_migrate_old_db_without_level_column(self):
        import sqlite3
        path = os.path.join(TMP, "old.db")
        con = sqlite3.connect(path)
        con.execute("CREATE TABLE players (id TEXT PRIMARY KEY, name TEXT NOT NULL, short TEXT NOT NULL DEFAULT '',"
                    " avatar TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1, phone_id TEXT NOT NULL DEFAULT '',"
                    " elo REAL NOT NULL DEFAULT 1000, wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0,"
                    " played INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'billbook',"
                    " created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))")
        con.execute("INSERT INTO players(id,name) VALUES('x','Cũ')")
        con.commit(); con.close()
        old = db.DB_PATH
        try:
            db.DB_PATH = path
            db.init_db(); db.init_db()          # chạy 2 lần không lỗi
            row = {p["id"]: p for p in db.roster()}["x"]
            self.assertEqual((row["name"], row["level"], row["host"]), ("Cũ", "", False))
        finally:
            db.DB_PATH = old


class TestHost(Base):
    def test_host_flag(self):
        set_ = lambda pid, h, pw=PASS: http("POST", "/api/players/host", {"pass": pw, "id": pid, "host": h})
        self.assertEqual(set_("m0", True, "sai")[0], 401)
        self.assertEqual(set_("khong-co", True)[0], 404)
        self.assertEqual(set_("m0", True)[0], 200)
        roster = {p["id"]: p for p in http("GET", "/api/roster")[1]["players"]}
        self.assertIs(roster["m0"]["host"], True)
        self.assertIs(roster["m1"]["host"], False)
        pick = {p["id"]: p for p in http("GET", "/api/pickup?date=" + TODAY)[1]["pickup"]}
        self.assertIs(pick["m0"]["host"], True)
        http("POST", "/api/sync/matches", {"matches": [match("a", ["m0", "m1"], ["m2", "m3"], 21, 10)]})
        self.assertIs(self.ranking()["m0"]["host"], True)
        self.assertEqual(self.ranking()["m0"]["elo"], 1024.0)   # host không đổi Elo
        set_("m0", False)
        self.assertIs({p["id"]: p for p in http("GET", "/api/roster")[1]["players"]}["m0"]["host"], False)
        # kéo lại sổ tiền không xoá cờ host
        set_("m1", True); app.reseed_from_billbook()
        self.assertIs({p["id"]: p for p in http("GET", "/api/roster")[1]["players"]}["m1"]["host"], True)


class TestProfile(Base):
    def test_profile_matches_and_elo(self):
        m1 = match("p1", ["m0", "m1"], ["m2", "m3"], 21, 15, hh="10:00")
        m1["rally_sequence"] = "BBBBBB" + "A" * 21 + "B" * 9   # m0 bị dẫn 0-6 rồi thắng
        m2 = match("p2", ["m0", "m2"], ["m1", "m3"], 18, 21, hh="23:10")
        http("POST", "/api/sync/matches", {"matches": [m1, m2]})
        st, j = http("GET", "/api/profile?id=m0")
        self.assertEqual(st, 200)
        self.assertEqual(j["player"]["id"], "m0")
        ms = j["matches"]
        self.assertEqual([m["id"] for m in ms], ["p1", "p2"])          # cũ -> mới
        a, b = ms
        self.assertTrue(a["won"]); self.assertFalse(b["won"])
        self.assertEqual(a["partners"], ["m1"]); self.assertEqual(sorted(a["opponents"]), ["m2", "m3"])
        self.assertEqual((a["score"], a["opp_score"]), (21, 15))
        self.assertEqual((b["score"], b["opp_score"]), (18, 21))
        self.assertTrue(a["rallies"].startswith("LLLLLLW"))
        self.assertEqual(a["elo_before"], 1000.0); self.assertEqual(a["delta"], 24.0)
        # Elo cuối = trước trận 2 + delta trận 2 = Elo trên ranking (cùng một phép tính)
        self.assertAlmostEqual(b["elo_before"], a["elo_before"] + a["delta"], places=1)
        self.assertAlmostEqual(self.ranking()["m0"]["elo"], b["elo_before"] + b["delta"], places=0)
        self.assertEqual(set(j["people"]), {"m0", "m1", "m2", "m3"})

    def test_profile_unknown_and_missing(self):
        self.assertEqual(http("GET", "/api/profile?id=khong-co")[0], 404)
        self.assertEqual(http("GET", "/api/profile")[0], 400)
        st, j = http("GET", "/api/profile?id=m5")
        self.assertEqual(st, 200); self.assertEqual(j["matches"], [])


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
        self.assertEqual(r["m0"]["elo"], 1024.0)
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


class TestBoard(Base):
    def setUp(self):
        super().setUp()
        con = db.connect()
        con.execute("DELETE FROM boards")
        con.commit()
        con.close()

    def board(self, **kw):
        b = {"present": ["m0", "m1", "m2", "m3", "m4"],
             "courts": [{"name": "Sân 1", "slots": ["m0", "m1", "m2", "m3"]},
                        {"name": "Sân 2", "slots": [None, None, None, None]}]}
        b.update(kw)
        return b

    def test_empty_default(self):
        st, j = http("GET", "/api/board?date=" + TODAY)
        self.assertEqual((st, j["rev"]), (200, 0))
        self.assertEqual(len(j["board"]["courts"]), 1)
        self.assertEqual(j["board"]["courts"][0]["slots"], [None] * 4)

    def test_save_rev_and_conflict(self):
        st, j = http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0, "board": self.board()})
        self.assertEqual((st, j["rev"]), (200, 1))
        self.assertEqual(http("GET", "/api/board?date=" + TODAY)[1]["board"]["courts"][0]["slots"],
                         ["m0", "m1", "m2", "m3"])
        # máy khác vẫn cầm rev 0 -> 409 kèm bản server, KHÔNG ghi đè
        st, j = http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0,
                                            "board": self.board(present=[])})
        self.assertEqual(st, 409)
        self.assertEqual(j["server"]["rev"], 1)
        self.assertIn("m4", http("GET", "/api/board?date=" + TODAY)[1]["board"]["present"])
        # ngày khác độc lập
        self.assertEqual(http("GET", "/api/board?date=" + YESTERDAY)[1]["rev"], 0)

    def test_validation(self):
        dup = self.board(courts=[{"name": "A", "slots": ["m0", "m0", None, None]}])
        self.assertEqual(http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0, "board": dup})[0], 400)
        two = self.board(courts=[{"name": "A", "slots": ["m0", None, None, None]},
                                 {"name": "B", "slots": ["m0", None, None, None]}])
        self.assertEqual(http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0, "board": two})[0], 400)
        bad = self.board(courts=[{"name": "A", "slots": [None, None, None]}])
        self.assertEqual(http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0, "board": bad})[0], 400)
        self.assertEqual(http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0,
                                                     "board": self.board(courts=[])})[0], 400)
        self.assertEqual(http("POST", "/api/board", {"pass": "sai", "date": TODAY, "rev": 0,
                                                     "board": self.board()})[0], 401)
        # người trên sân mà quên tick có mặt -> tự thêm vào present
        st, j = http("POST", "/api/board", {"pass": PASS, "date": TODAY, "rev": 0,
                                            "board": self.board(present=[])})
        self.assertEqual(st, 200)
        self.assertEqual(sorted(j["board"]["present"]), ["m0", "m1", "m2", "m3"])

    def test_last_ended_for_wait_time(self):
        http("POST", "/api/sync/matches", {"matches": [match("t1", ["m0", "m1"], ["m2", "m3"], 21, 10, TODAY, "18:00")]})
        by = {p["id"]: p for p in http("GET", "/api/pickup?date=" + TODAY)[1]["pickup"]}
        # helper match(): ended_at = played_at + 30 giây -> phải lấy giờ RỜI sân, không phải giờ vào
        self.assertEqual(by["m0"]["last_ended"], TODAY + "T18:00:30.000")
        self.assertGreater(by["m0"]["last_ended"], by["m0"]["last_played"])
        self.assertEqual(by["m4"]["last_ended"], "")


def tearDownModule():
    API.shutdown()
    VERCEL.shutdown()
    shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
