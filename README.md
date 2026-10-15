# caulong

Mọi thứ về cầu lông của nhóm, một repo: sổ tiền, sân trống, đếm điểm trên đồng hồ,
phân tích video.

| Thư mục | Là gì | Chạy ở đâu |
|---|---|---|
| [`web/`](web/) | Sổ Cầu Lông (chia tiền, QR, lịch sử) + trang Sân trống công khai | Vercel (Root Directory = `web`) |
| [`backend/crawler/`](backend/crawler/) | Cào ALOBO → heatmap sân trống, tìm slot | home server (Dokploy) |
| `backend/api/` | *(sắp làm)* trận đấu, tỉ số, ranking, hàng đợi job | home server (Dokploy) |
| [`watch/band/`](watch/) | App đếm điểm trên Mi Band 10 (QuickApp) | đồng hồ |
| [`watch/phone/`](watch/) | App Flutter: bảng điểm, loa, quay video trận | điện thoại Android |
| [`analysis/`](analysis/) | Video → sân, cầu, cú đánh, đường bay 3D (TrackNetV3 + pose) | PC có GPU |
| [`archive/`](archive/) | Repo mẫu / bản cũ để tham khảo cách custom band — **không build** | — |

## Hạ tầng

```
User ──▶ Vercel (web/, luôn sống)
            │ gọi API
            ▼
   *.app.huynhhanh.com ──▶ Linode (relay) ──WireGuard──▶ home server (Dokploy)
                                                         crawler · api · postgres · minio
Phone (watch/phone) ──sync trận/tỉ số──▶ api      PC GPU (analysis/) ──WireGuard──▶ nhận job
```

- Dokploy: `deploy.huynhhanh.com`, app: `*.app.huynhhanh.com`.
- Home server mất điện → web vẫn mở (Vercel), dữ liệu đọc từ snapshot; phone giữ hàng đợi rồi sync sau.

## Chạy thử ở máy

```bash
python backend/crawler/server.py          # heatmap sân trống  → http://127.0.0.1:8000
node web/dev-server.mjs                   # sổ tiền (dev)      → http://localhost:3210
```

Chi tiết từng phần: README trong mỗi thư mục.

## File không nằm trong git (giữ local)

| File | Dùng cho |
|---|---|
| `backend/crawler/.env` | `ALOBO_KEY`, `PUSH_URL`, `PUSH_TOKEN` — xem `.env.example` |
| `backend/crawler/data/` | dữ liệu đã cào |
| `watch/phone/.env`, `watch/phone/android/local.properties` | cấu hình app phone |
| `analysis/models/`, `analysis/data/`, `analysis/third_party/`, `analysis/.venv/` | model AI, video, TrackNetV3 — xem `analysis/README.md` |

## Lịch sử

Gộp từ 4 repo, giữ nguyên lịch sử từng repo (`git log -- <thư mục>`):

| Repo cũ | Vào |
|---|---|
| `caulong-web` | `web/` + `backend/crawler/` (từ `alobo_crawler/`) |
| `miband-custom-app` (`D:\project\watch`) | `watch/` (`bandcounter-watch/` → `watch/band/`) + `archive/watch/` |
| `voice_counter` (`bandcounter-flutter`) | `watch/phone/` |
| `read-video` | `analysis/` |
