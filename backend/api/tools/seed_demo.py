#!/usr/bin/env python3
"""Tạo một DB DEMO (người chơi + khách + vài buổi trận ảo) để xem ranking/pickup
trên web mà không đụng dữ liệu thật.

    cd backend/api
    python tools/seed_demo.py                       # -> data/demo.db
    set DB_PATH=data\\demo.db  &&  python app.py --port 8777      (Windows cmd)
    $env:DB_PATH="data\\demo.db"; python app.py --port 8777      (PowerShell)
    # web: đặt VITE_API_BASE=http://127.0.0.1:8777 trong web/.env.local rồi npm run dev

An toàn: từ chối ghi vào data/badminton.db (DB thật) và từ chối ghi đè file có
sẵn trừ khi thêm --force. Không gọi mạng, không đẩy mirror lên Blob.
"""
import argparse
import os
import random
import sys
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent

NAMES = ["Nguyễn Mạnh Hùng", "Trần Văn An", "Lê Thị Bình", "Phạm Quốc Cường",
         "Võ Minh Dũng", "Đỗ Thu Em", "Hoàng Gia Phúc", "Bùi Thanh Giang",
         "Ngô Hải Hà", "Đặng Khánh Linh"]
GUESTS = ["Tuấn (bạn An)", "Khách Quang"]
# "trình" ẩn của từng người — chỉ để tỉ số trông thật, ranking phải tự tìm ra
SKILL = [1.30, 1.00, 0.85, 1.15, 1.05, 0.80, 1.20, 0.95, 0.90, 1.10, 1.00, 0.75]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(HERE / "data" / "demo.db"))
    ap.add_argument("--force", action="store_true", help="ghi đè file demo đã có")
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    target = Path(args.db).resolve()
    real = (HERE / "data" / "badminton.db").resolve()
    if target == real or target.name == "badminton.db":
        sys.exit("Từ chối: đây là tên DB thật. Dùng --db data/demo.db")
    if target.exists():
        if not args.force:
            sys.exit(f"{target} đã có. Thêm --force để tạo lại.")
        target.unlink()

    os.environ["DB_PATH"] = str(target)
    sys.path.insert(0, str(HERE))
    import db  # noqa: E402  (đọc DB_PATH lúc import)

    db.init_db()
    rnd = random.Random(args.seed)
    con = db.connect()
    ids = []
    for i, n in enumerate(NAMES):
        pid = f"demo{i:02d}"
        db.upsert_player(con, {"id": pid, "name": n, "source": "billbook"})
        ids.append(pid)
    for g in GUESTS:
        ids.append(db.add_guest(con, g)["id"])
    skill = dict(zip(ids, SKILL))

    today = date.fromisoformat(db.today_vn())
    n_match = 0
    for d in range(args.days - 1, -1, -1):
        day = today - timedelta(days=d)
        present = rnd.sample(ids, k=min(len(ids), rnd.randint(8, 10)))
        played = {p: 0 for p in present}
        minute = 18 * 60
        for _ in range(rnd.randint(5, 8)):
            # xoay người như host: ai đánh ít nhất vào sân trước
            four = sorted(present, key=lambda p: (played[p], rnd.random()))[:4]
            rnd.shuffle(four)
            a, b = four[:2], four[2:]
            pa = sum(skill[p] for p in a) / (sum(skill[p] for p in a) + sum(skill[p] for p in b))
            win_a = rnd.random() < pa
            lose = rnd.randint(8, 19)
            sa, sb = (21, lose) if win_a else (lose, 21)
            hh, mm = divmod(minute, 60)
            mid = f"demo-{day.isoformat()}-{n_match:03d}"
            db.save_match(con, {
                "id": mid, "played_at": f"{day.isoformat()}T{hh:02d}:{mm:02d}:00.000",
                "ended_at": f"{day.isoformat()}T{hh:02d}:{mm + 15 if mm + 15 < 60 else 59:02d}:00.000",
                "team_a": a, "team_b": b, "team_a_score": sa, "team_b_score": sb,
                "winner": "A" if sa > sb else "B", "duration_seconds": 900, "source": "demo",
            })
            for p in four:
                played[p] += 1
            minute += rnd.randint(14, 22)
            n_match += 1
    db.recompute_ratings(con)
    con.commit()
    con.close()

    print(f"Đã tạo {target} — {len(ids)} người ({len(GUESTS)} khách), {n_match} trận / {args.days} ngày\n")
    print("Ranking:")
    for i, p in enumerate(db.ranking(), 1):
        tag = " (khách)" if p["guest"] else ""
        print(f"  {i:2}. {p['name']:<22}{tag:<9} Elo {p['elo']:7.1f}  {p['wins']}T-{p['losses']}B")
    pk = db.pickup_by_date(today.isoformat())
    print(f"\nHôm nay {pk['date']}: {pk['matches']} trận")
    for p in pk["pickup"]:
        print(f"  {p['short'] or p['name']:<10} {p['played']} trận  cuối: {p['last_played'][11:16] or '-'}")


if __name__ == "__main__":
    main()
