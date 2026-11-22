#!/usr/bin/env python3
"""Lớp dữ liệu SQLite cho backend/api.

Giữ mọi truy cập DB ở một chỗ. Elo/thắng/thua tính LẠI từ đầu trên toàn bộ
matches mỗi lần sync — dữ liệu nhỏ, cách này đơn giản và luôn đúng, không phải
cộng dồn dễ lệch.
"""
from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
DB_PATH = os.environ.get("DB_PATH") or str(HERE / "data" / "badminton.db")
SCHEMA = HERE / "schema.sql"

K_FACTOR = 32          # bước điều chỉnh Elo mỗi trận
BASE_ELO = 1000.0
# Người mới: K lớn hơn trong N trận đầu để Elo nhanh về đúng trình.
K_NEW = 48
NEW_GAMES = 10

# Trình độ host chọn -> Elo khởi điểm. '' = chưa đặt (= Trung bình, 1000).
# Giữ cùng thứ tự/khóa với web/src/lib/levels.js.
LEVELS = {
    "newbie": ("Newbie", 800.0),
    "yeu": ("Yếu", 900.0),
    "tb-yeu": ("TB yếu", 950.0),
    "tb": ("Trung bình", 1000.0),
    "kha": ("Khá", 1100.0),
    "gioi": ("Giỏi", 1200.0),
}


def base_elo(level: str) -> float:
    return LEVELS.get(level or "", ("", BASE_ELO))[1]

# Khách vãng lai: tạo trên web (không có trong sổ tiền). id 'g-<hex>' — id sổ
# tiền là base36 chữ+số, không có '-', nên không bao giờ trùng.
GUEST_SOURCE = "guest"
GUEST_MARK = "*"       # đuôi tên ngắn trên band/bảng: "Tuấn*"
SHORT_MAX = 8          # = PlayerService.shortMax phía Flutter


def guest_short(name: str, short: str = "") -> str:
    """Tên ngắn cho khách, luôn kết thúc bằng GUEST_MARK và vừa SHORT_MAX ký tự."""
    import re
    base = (short or "").strip().rstrip(GUEST_MARK).strip()
    if not base:
        # "Tuấn (bạn An)" -> "Tuấn"; "Nguyễn Văn Tuấn" -> "Tuấn" (tên gọi ở cuối)
        clean = re.sub(r"\(.*?\)|\[.*?\]", " ", name or "")
        parts = [re.sub(r"[^\w]", "", w) for w in clean.split()]
        parts = [w for w in parts if w]
        base = parts[-1] if parts else "Khach"
    return base[: SHORT_MAX - len(GUEST_MARK)] + GUEST_MARK


def today_vn() -> str:
    """Ngày hôm nay ở VN (YYYY-MM-DD), không phụ thuộc TZ của container."""
    from datetime import datetime, timedelta, timezone
    return datetime.now(timezone(timedelta(hours=7))).strftime("%Y-%m-%d")


def connect() -> sqlite3.Connection:
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def init_db() -> None:
    con = connect()
    try:
        con.executescript(SCHEMA.read_text(encoding="utf-8"))
        # migrate: cột level cho DB tạo trước khi có trình độ (SQLite không có ADD COLUMN IF NOT EXISTS)
        cols = {r[1] for r in con.execute("PRAGMA table_info(players)")}
        if "level" not in cols:
            con.execute("ALTER TABLE players ADD COLUMN level TEXT NOT NULL DEFAULT ''")
        con.commit()
    finally:
        con.close()


def players_count() -> int:
    con = connect()
    try:
        return con.execute("SELECT COUNT(*) FROM players").fetchone()[0]
    finally:
        con.close()


def upsert_player(con: sqlite3.Connection, p: dict) -> str:
    """Thêm/cập nhật người chơi. KHÔNG đụng elo/wins/losses/played (do tính lại).
    Giữ nguyên avatar cũ nếu lần này không gửi (tránh xoá ảnh khi Flutter đẩy lên)."""
    pid = str(p.get("id") or "").strip()
    if not pid:
        raise ValueError("player cần 'id'")
    row = con.execute("SELECT id FROM players WHERE id=?", (pid,)).fetchone()
    name = str(p.get("name") or "").strip() or "?"
    short = str(p.get("short") or "").strip()
    avatar = p.get("avatar")
    phone_id = str(p.get("phone_id") or "").strip()
    source = str(p.get("source") or "billbook").strip()
    if row is None:
        con.execute(
            "INSERT INTO players(id,name,short,avatar,phone_id,source) VALUES(?,?,?,?,?,?)",
            (pid, name, short, avatar or "", phone_id, source),
        )
    else:
        # avatar None -> giữ cũ; '' hoặc chuỗi -> ghi đè
        if avatar is None:
            con.execute(
                "UPDATE players SET name=?, short=COALESCE(NULLIF(?,''),short),"
                " phone_id=COALESCE(NULLIF(?,''),phone_id), updated_at=datetime('now') WHERE id=?",
                (name, short, phone_id, pid),
            )
        else:
            con.execute(
                "UPDATE players SET name=?, short=COALESCE(NULLIF(?,''),short), avatar=?,"
                " phone_id=COALESCE(NULLIF(?,''),phone_id), updated_at=datetime('now') WHERE id=?",
                (name, short, avatar, phone_id, pid),
            )
    return pid


def _with_guest(row) -> dict:
    d = dict(row)
    d["guest"] = d.get("source") == GUEST_SOURCE
    return d


def roster(active_only: bool = False) -> list[dict]:
    con = connect()
    try:
        sql = ("SELECT id,name,short,avatar,active,phone_id,elo,wins,losses,played,source,level"
               " FROM players")
        if active_only:
            sql += " WHERE active=1"
        sql += " ORDER BY name COLLATE NOCASE"
        return [_with_guest(r) for r in con.execute(sql).fetchall()]
    finally:
        con.close()


def add_guest(con: sqlite3.Connection, name: str, short: str = "") -> dict:
    """Tạo khách vãng lai. Trùng tên với một khách đang active -> trả lại người cũ
    (bấm 2 lần không ra 2 người)."""
    import secrets
    name = (name or "").strip()
    if not name:
        raise ValueError("khách cần tên")
    if len(name) > 60:
        raise ValueError("tên quá dài")
    row = con.execute(
        "SELECT id FROM players WHERE source=? AND active=1 AND name=? COLLATE NOCASE",
        (GUEST_SOURCE, name),
    ).fetchone()
    if row is not None:
        pid = row["id"]
    else:
        pid = "g-" + secrets.token_hex(4)
        con.execute(
            "INSERT INTO players(id,name,short,avatar,source) VALUES(?,?,?,?,?)",
            (pid, name, guest_short(name, short), "", GUEST_SOURCE),
        )
    return _with_guest(con.execute(
        "SELECT id,name,short,avatar,active,phone_id,elo,wins,losses,played,source"
        " FROM players WHERE id=?", (pid,)).fetchone())


def hide_guest(con: sqlite3.Connection, pid: str) -> bool:
    """Ẩn khách (active=0). Chỉ khách — người của sổ tiền không ẩn ở đây được.
    Trận cũ giữ nguyên, Elo vẫn tính."""
    cur = con.execute("UPDATE players SET active=0, updated_at=datetime('now')"
                      " WHERE id=? AND source=?", (str(pid or ""), GUEST_SOURCE))
    return cur.rowcount > 0


def set_level(con: sqlite3.Connection, pid: str, level: str) -> bool:
    """Đặt trình độ (Elo khởi điểm) rồi tính lại toàn bộ Elo. level '' = bỏ đặt."""
    level = (level or "").strip()
    if level and level not in LEVELS:
        raise ValueError("trình độ không hợp lệ: " + level)
    cur = con.execute("UPDATE players SET level=?, updated_at=datetime('now') WHERE id=?", (level, str(pid or "")))
    if cur.rowcount == 0:
        return False
    recompute_ratings(con)
    return True


def unknown_ids(con: sqlite3.Connection, ids) -> list[str]:
    """Các id người chơi không có trong bảng players (vd 'p12' từ phone chưa nối)."""
    out = []
    for pid in sorted({str(x) for x in ids if str(x).strip()}):
        if con.execute("SELECT 1 FROM players WHERE id=?", (pid,)).fetchone() is None:
            out.append(pid)
    return out


def save_match(con: sqlite3.Connection, m: dict) -> str:
    """Lưu một trận + thành phần đội. Idempotent theo match id (replace)."""
    mid = str(m.get("id") or "").strip()
    if not mid:
        raise ValueError("match cần 'id'")
    team_a = [str(x) for x in (m.get("team_a") or []) if str(x).strip()]
    team_b = [str(x) for x in (m.get("team_b") or []) if str(x).strip()]
    con.execute(
        "INSERT OR REPLACE INTO matches(id,session_id,played_at,ended_at,team_a_score,"
        "team_b_score,winner,rally_sequence,duration_seconds,video_url,source)"
        " VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        (
            mid, str(m.get("session_id") or ""), str(m.get("played_at") or ""),
            str(m.get("ended_at") or ""), int(m.get("team_a_score") or 0),
            int(m.get("team_b_score") or 0), str(m.get("winner") or ""),
            str(m.get("rally_sequence") or ""), int(m.get("duration_seconds") or 0),
            str(m.get("video_url") or ""), str(m.get("source") or "phone"),
        ),
    )
    con.execute("DELETE FROM match_players WHERE match_id=?", (mid,))
    for pid in team_a:
        con.execute("INSERT OR IGNORE INTO match_players(match_id,player_id,team) VALUES(?,?,?)",
                    (mid, pid, "A"))
    for pid in team_b:
        con.execute("INSERT OR IGNORE INTO match_players(match_id,player_id,team) VALUES(?,?,?)",
                    (mid, pid, "B"))
    return mid


def recompute_ratings(con: sqlite3.Connection) -> None:
    """Tính lại elo/wins/losses/played cho mọi người từ đầu, theo thứ tự thời gian.
    Đôi: dùng elo trung bình đội, cập nhật đều cho từng người trong đội."""
    base = {r["id"]: base_elo(r["level"]) for r in con.execute("SELECT id, level FROM players")}
    rating: dict[str, float] = {}
    stat: dict[str, list[int]] = {}  # pid -> [wins, losses, played]

    def r(pid: str) -> float:
        return rating.setdefault(pid, base.get(pid, BASE_ELO))

    def s(pid: str) -> list[int]:
        return stat.setdefault(pid, [0, 0, 0])

    rows = con.execute(
        "SELECT id,winner FROM matches WHERE winner IN ('A','B')"
        " ORDER BY CASE WHEN played_at='' THEN created_at ELSE played_at END, id"
    ).fetchall()
    for mr in rows:
        mid, winner = mr["id"], mr["winner"]
        mps = con.execute("SELECT player_id,team FROM match_players WHERE match_id=?",
                          (mid,)).fetchall()
        a = [x["player_id"] for x in mps if x["team"] == "A"]
        b = [x["player_id"] for x in mps if x["team"] == "B"]
        if not a or not b:
            continue
        ra = sum(r(p) for p in a) / len(a)
        rb = sum(r(p) for p in b) / len(b)
        ea = 1.0 / (1.0 + 10 ** ((rb - ra) / 400))
        eb = 1.0 - ea
        sa = 1.0 if winner == "A" else 0.0
        sb = 1.0 - sa
        # K theo từng người: N trận đầu dùng K_NEW (tính trước khi cộng trận này)
        k = lambda p: K_NEW if s(p)[2] < NEW_GAMES else K_FACTOR  # noqa: E731
        for p in a:
            rating[p] = r(p) + k(p) * (sa - ea)
            st = s(p); st[2] += 1; st[0 if winner == "A" else 1] += 1
        for p in b:
            rating[p] = r(p) + k(p) * (sb - eb)
            st = s(p); st[2] += 1; st[0 if winner == "B" else 1] += 1

    # reset rồi ghi lại cho mọi player (người chưa đánh -> Elo khởi điểm theo trình, 0 trận)
    con.execute("UPDATE players SET elo=?, wins=0, losses=0, played=0", (BASE_ELO,))
    for pid, b in base.items():
        if b != BASE_ELO:
            con.execute("UPDATE players SET elo=? WHERE id=?", (b, pid))
    for pid in set(list(rating) + list(stat)):
        w, l, pl = s(pid)
        con.execute(
            "UPDATE players SET elo=?, wins=?, losses=?, played=? WHERE id=?",
            (round(r(pid), 1), w, l, pl, pid),
        )


def ranking() -> list[dict]:
    con = connect()
    try:
        return [_with_guest(x) for x in con.execute(
            "SELECT id,name,short,avatar,elo,wins,losses,played,source,level FROM players"
            " WHERE active=1 AND played>0 ORDER BY elo DESC, wins DESC, name COLLATE NOCASE"
        ).fetchall()]
    finally:
        con.close()


MAX_COURTS = 8


def empty_board() -> dict:
    return {"present": [], "courts": [{"name": "Sân 1", "slots": [None, None, None, None]}]}


def clean_board(b) -> dict:
    """Kiểm + chuẩn hoá bảng xếp sân. Sai cấu trúc -> ValueError (400).
    Một người chỉ được ở 1 ô trên toàn bảng; người trên sân tự tính là có mặt."""
    if not isinstance(b, dict):
        raise ValueError("board phải là object")
    present = b.get("present") or []
    courts = b.get("courts") or []
    if not isinstance(present, list) or not isinstance(courts, list):
        raise ValueError("present/courts phải là mảng")
    if not 1 <= len(courts) <= MAX_COURTS:
        raise ValueError(f"cần 1..{MAX_COURTS} sân")
    seen: set[str] = set()
    out_courts = []
    for i, c in enumerate(courts):
        if not isinstance(c, dict):
            raise ValueError("sân phải là object")
        slots = c.get("slots")
        if not isinstance(slots, list) or len(slots) != 4:
            raise ValueError("mỗi sân đúng 4 ô")
        clean = []
        for x in slots:
            if x is None or x == "":
                clean.append(None)
                continue
            pid = str(x)
            if pid in seen:
                raise ValueError(f"{pid} đang ở 2 ô cùng lúc")
            seen.add(pid)
            clean.append(pid)
        name = str(c.get("name") or f"Sân {i + 1}").strip()[:20] or f"Sân {i + 1}"
        out_courts.append({"name": name, "slots": clean})
    pres = []
    for x in present + sorted(seen):
        pid = str(x)
        if pid and pid not in pres:
            pres.append(pid)
    return {"present": pres[:200], "courts": out_courts}


def get_board(day: str) -> dict:
    import json
    con = connect()
    try:
        row = con.execute("SELECT data,rev,updated_at FROM boards WHERE day=?", (day,)).fetchone()
    finally:
        con.close()
    if row is None:
        return {"date": day, "rev": 0, "updated_at": None, "board": empty_board()}
    return {"date": day, "rev": row["rev"], "updated_at": row["updated_at"],
            "board": json.loads(row["data"])}


def save_board(day: str, rev: int, board) -> tuple[bool, dict]:
    """Ghi nếu rev khớp bản trên server. Trả (ok, bản hiện tại sau khi xử lý).
    Lệch rev -> (False, bản server) để client tự gộp, không đè mất của nhau."""
    import json
    clean = clean_board(board)
    con = connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        row = con.execute("SELECT rev FROM boards WHERE day=?", (day,)).fetchone()
        cur = row["rev"] if row else 0
        if int(rev) != cur:
            con.rollback()
            return False, get_board(day)
        con.execute(
            "INSERT INTO boards(day,data,rev,updated_at) VALUES(?,?,?,datetime('now'))"
            " ON CONFLICT(day) DO UPDATE SET data=excluded.data, rev=excluded.rev,"
            " updated_at=excluded.updated_at",
            (day, json.dumps(clean, ensure_ascii=False), cur + 1),
        )
        con.commit()
    finally:
        con.close()
    return True, get_board(day)


def pickup_by_date(day: str) -> dict:
    """Cho một NGÀY (YYYY-MM-DD, giờ VN): mỗi người active + số trận đã đánh trong
    ngày + lần cuối vào sân + Elo. Phone gửi played_at dạng ISO giờ local không
    offset, nên 10 ký tự đầu chính là ngày VN.
    Xếp: ít trận nhất trước, cùng số trận thì ai nghỉ lâu hơn trước."""
    day = (day or "").strip()[:10]
    con = connect()
    try:
        players = con.execute(
            "SELECT id,name,short,avatar,elo,source,level FROM players WHERE active=1"
            " ORDER BY name COLLATE NOCASE"
        ).fetchall()
        rows = con.execute(
            "SELECT mp.player_id AS pid, m.played_at AS t, m.ended_at AS e FROM match_players mp"
            " JOIN matches m ON m.id=mp.match_id WHERE substr(m.played_at,1,10)=?",
            (day,),
        ).fetchall()
        n_matches = con.execute(
            "SELECT COUNT(*) FROM matches WHERE substr(played_at,1,10)=?", (day,)
        ).fetchone()[0]
        counts: dict[str, dict] = {}
        for row in rows:
            c = counts.setdefault(row["pid"], {"played": 0, "last": "", "end": ""})
            c["played"] += 1
            if (row["t"] or "") > c["last"]:
                c["last"] = row["t"] or ""
            # giờ RỜI sân gần nhất (không có ended_at thì lấy giờ vào sân)
            end = row["e"] or row["t"] or ""
            if end > c["end"]:
                c["end"] = end
        out = []
        for p in players:
            c = counts.get(p["id"], {"played": 0, "last": "", "end": ""})
            out.append({
                "id": p["id"], "name": p["name"], "short": p["short"], "avatar": p["avatar"],
                "elo": p["elo"], "guest": p["source"] == GUEST_SOURCE, "level": p["level"],
                "played": c["played"], "last_played": c["last"], "last_ended": c["end"],
            })
        out.sort(key=lambda x: (x["played"], x["last_played"] or "", x["name"].lower()))
        return {"date": day, "matches": n_matches, "pickup": out}
    finally:
        con.close()


def pickup(session_id: str) -> list[dict]:
    """Cho một buổi: mỗi người active kèm số trận đã đánh trong buổi + lần cuối vào sân.
    Xếp để host chọn người tiếp theo: ít trận nhất trước, rồi nghỉ lâu nhất trước."""
    con = connect()
    try:
        players = con.execute(
            "SELECT id,name,short,avatar FROM players WHERE active=1 ORDER BY name COLLATE NOCASE"
        ).fetchall()
        counts: dict[str, dict] = {}
        rows = con.execute(
            "SELECT mp.player_id AS pid, m.played_at AS t FROM match_players mp"
            " JOIN matches m ON m.id=mp.match_id WHERE m.session_id=?",
            (session_id,),
        ).fetchall()
        for row in rows:
            c = counts.setdefault(row["pid"], {"played": 0, "last": ""})
            c["played"] += 1
            if (row["t"] or "") > c["last"]:
                c["last"] = row["t"] or ""
        out = []
        for p in players:
            c = counts.get(p["id"], {"played": 0, "last": ""})
            out.append({
                "id": p["id"], "name": p["name"], "short": p["short"],
                "avatar": p["avatar"], "played": c["played"], "last_played": c["last"],
            })
        # ít trận nhất trước; cùng số trận thì ai vào sân lâu rồi (last nhỏ) trước
        out.sort(key=lambda x: (x["played"], x["last_played"] or ""))
        return out
    finally:
        con.close()
