# backend/api — người chơi · trận đấu · ranking (SQLite)

API nhỏ bằng Python stdlib trên một file SQLite (`/app/data/badminton.db`).
Không dính ALOBO, không thư viện ngoài. Chạy cùng compose với `crawler`.

## Vì sao có service này

- **Một nguồn người chơi chung.** `id` người chơi = **id gốc của sổ tiền** (Blob) —
  không phải remap dữ liệu tiền cầu. Flutter tạo thêm người test thì đẩy lên đây.
- **Lịch sử trận + ranking.** Flutter sync trận → tính Elo.
- **Host xoay người.** Mỗi buổi biết ai chưa đánh / đánh ít / đánh nhiều để chia cho chuẩn.

Danh bạ được **mirror lên Blob** (`roster.json` qua `web/api/roster.js`) nên web và
Flutter **đọc được kể cả khi home server tắt**. Backend là nơi **ghi** duy nhất.

## Endpoint

| Method | Path | Việc |
|---|---|---|
| GET | `/api/health` | sống chưa + số người |
| GET | `/api/roster` | danh bạ người chơi |
| GET | `/api/ranking` | bảng xếp hạng Elo (người đã đánh ≥1 trận) |
| GET | `/api/pickup?session=<id>` | gợi ý xoay người cho một buổi |
| POST | `/api/players` | tạo/sửa người `{players:[{id,name,short?,avatar?,phone_id?}]}` |
| POST | `/api/sync/matches` | đẩy trận (xem payload dưới) |
| POST | `/api/roster/reseed` | kéo lại danh bạ từ sổ tiền + đẩy mirror |

POST từ internet phải kèm `Authorization: Bearer <API_TOKEN>`. Máy trong
`TRUSTED_NETS` (PC qua WireGuard) khỏi token. GET mở.

Payload sync (Flutter → backend), `team_a`/`team_b` là **id gốc người chơi**:

```json
{
  "sessions": [{"id":"s1","played_on":"2026-10-19","court_cost":120000}],
  "matches": [{
    "id":"<Match.id của Flutter>", "session_id":"s1",
    "played_at":"2026-10-19T10:00:00", "ended_at":"...",
    "team_a":["p0","p1"], "team_b":["p2","p3"],
    "team_a_score":21, "team_b_score":15, "winner":"A",
    "rally_sequence":"...", "duration_seconds":600, "video_url":""
  }]
}
```

Sync **idempotent** theo `match.id` (gửi lại đè bản cũ). Elo tính **lại từ đầu**
theo thứ tự thời gian mỗi lần sync nên luôn nhất quán.

## Deploy (Dokploy) + migrate dữ liệu

Service đã nằm trong `backend/docker-compose.yml`. Push `main` → Dokploy autodeploy
tạo thêm service `api`. Đặt ở tab **Environment** của Dokploy:

```
API_TOKEN=<chuỗi ngẫu nhiên dài, Flutter sẽ gửi kèm khi sync>
BILLBOOK_URL=https://<project>.vercel.app/api/data
ROSTER_PUSH_URL=https://<project>.vercel.app/api/roster
ROSTER_PUSH_TOKEN=<giống ROSTER_TOKEN đặt trên Vercel>
```

**Migrate tự động:** lần đầu DB rỗng mà có `BILLBOOK_URL`, api tự kéo danh sách
thành viên từ sổ tiền (tên + ảnh, giữ nguyên id) rồi đẩy mirror lên Blob. Muốn
nạp lại sau này: `POST /api/roster/reseed` (từ PC qua WireGuard, khỏi token).

Trên **Vercel** thêm env `ROSTER_TOKEN` (hoặc để trống thì dùng chung `CRAWLER_TOKEN`)
rồi Redeploy. Web gọi ranking/pickup qua domain của api (đặt ở tab **Domains** của
Dokploy, service `api`, port `8000`, HTTPS Let's Encrypt).

Quản trị từ PC: bật WireGuard → `http://10.8.0.4:8002`.

## Chạy thử ở máy

```bash
python app.py --port 8777      # DB mặc định ./data/badminton.db
curl http://127.0.0.1:8777/api/health
```

127.0.0.1 nằm trong `TRUSTED_NETS` mặc định nên POST thử khỏi cần token.
