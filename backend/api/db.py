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


def roster(active_only: bool = False) -> list[dict]:
    con = connect()
    try:
        sql = ("SELECT id,name,short,avatar,active,phone_id,elo,wins,losses,played,source"
               " FROM players")
        if active_only:
            sql += " WHERE active=1"
        sql += " ORDER BY name COLLATE NOCASE"
        return [dict(r) for r in con.execute(sql).fetchall()]
    finally:
        con.close()


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
    rating: dict[str, float] = {}
    stat: dict[str, list[int]] = {}  # pid -> [wins, losses, played]

    def r(pid: str) -> float:
        return rating.setdefault(pid, BASE_ELO)

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
        for p in a:
            rating[p] = r(p) + K_FACTOR * (sa - ea)
            st = s(p); st[2] += 1; st[0 if winner == "A" else 1] += 1
        for p in b:
            rating[p] = r(p) + K_FACTOR * (sb - eb)
            st = s(p); st[2] += 1; st[0 if winner == "B" else 1] += 1

    # reset rồi ghi lại cho mọi player (người chưa đánh -> BASE_ELO, 0 trận)
    con.execute("UPDATE players SET elo=?, wins=0, losses=0, played=0", (BASE_ELO,))
    for pid in set(list(rating) + list(stat)):
        w, l, pl = s(pid)
        con.execute(
            "UPDATE players SET elo=?, wins=?, losses=?, played=? WHERE id=?",
            (round(r(pid), 1), w, l, pl, pid),
        )


def ranking() -> list[dict]:
    con = connect()
    try:
        return [dict(x) for x in con.execute(
            "SELECT id,name,short,avatar,elo,wins,losses,played FROM players"
            " WHERE active=1 AND played>0 ORDER BY elo DESC, wins DESC"
        ).fetchall()]
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
