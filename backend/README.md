# backend — chạy trên home server (Dokploy)

| Service | Là gì | Domain |
|---|---|---|
| `crawler` | Cào ALOBO **khi được bấm** (không chạy định kỳ), đẩy kết quả lên Vercel | `caulongapi.app.huynhhanh.com` |
| `api` | *(sắp làm)* sổ tiền, trận đấu, ranking — dùng Postgres | cùng domain |

## Luồng "Sân trống"

```
courts.html (Vercel) ── admin bấm ⟳ Cào ngay ──▶ /api/courts?action=crawl  (kiểm ADMIN_PASS)
        ▲                                              │ Bearer CRAWLER_TOKEN
        │                                              ▼
   /api/courts  ◀── POST + token (push_web.py) ── crawler: POST /api/crawl/run
   (Vercel Blob)                                       │ chạy scheduler.py --once
                                                       ▼
                           Playwright server dùng chung (container chromium) ──▶ ALOBO
```

- **Chỉ cào khi bấm** — `server.py` chạy KHÔNG có `--crawl`, không có lịch 30′.
- Từ internet chỉ gọi được `POST /api/crawl/run`, phải có token, cách nhau ≥ 2 phút.
- Crawler **không cài Chromium**: nối vào Playwright server sẵn có trên Dokploy qua
  `PLAYWRIGHT_WS` (cùng `dokploy-network`). Client ghim `playwright==1.64.*` cho khớp server.

## Deploy lần đầu (Dokploy UI)

1. **Create Service → Compose**, đặt tên `badminton-backend`
   - Provider: **GitHub** (hoặc Git) → repo `jinergenkai/badminton-system`, branch `main`
   - **Compose Path**: `backend/docker-compose.yml`
2. Tab **Environment**:

   ```
   ALOBO_KEY=<giống backend/crawler/.env ở máy>
   PUSH_URL=https://<project>.vercel.app/api/courts
   PUSH_TOKEN=<giống CRAWLER_TOKEN trên Vercel>
   ```
   (`PLAYWRIGHT_WS` đã có mặc định trong compose, chỉ đặt nếu đổi container chromium.)
3. Tab **Domains** → Add: Service `crawler`, Host `caulongapi.app.huynhhanh.com`,
   Path `/`, Container Port `8000`, **HTTPS** + Certificate **Let's Encrypt**.
4. **Deploy**. Kiểm tra: `curl https://caulongapi.app.huynhhanh.com/api/crawl` → JSON.
5. Vercel → Environment Variables: `CRAWLER_TRIGGER_URL=https://caulongapi.app.huynhhanh.com/api/crawl/run`
   → **Redeploy**.

Bật **Autodeploy** (webhook GitHub) để push lên `main` là Dokploy build lại.

## Đổi danh sách sân

Danh sách sân nằm trong volume (`/app/data/config.json`), lần deploy đầu chép từ
`crawler/config.json` trong git; **sau đó sửa trong git không còn tác dụng**.
Sửa từ UI quản trị của crawler — **bật WireGuard trên PC** rồi mở
**http://10.8.0.4:8001** → tab ⚙ Cài đặt sân / ⟳ Cào dữ liệu.

Chỉ PC `10.8.0.3` được sửa (biến `TRUSTED_NETS` trong compose). Qua domain công khai thì chỉ xem
và kích cào bằng token. Đổi máy quản trị → sửa `TRUSTED_NETS` ở tab Environment của Dokploy.

## Postgres (cho `api`, chưa dùng)

`dokploy-postgres` là DB **của chính Dokploy** — không dùng cho app. Tạo DB riêng:
Dokploy → **Create Service → Database → PostgreSQL**, tự đặt Database / User / Password.
Trong cùng `dokploy-network`, app nối bằng *Internal Host* Dokploy hiển thị, port 5432.
Từ máy bạn: đặt **External Port** (vd `5433`) trong trang DB của Dokploy → DBeaver/psql vào
`10.8.0.4:5433` qua WireGuard. Cổng này **không có lớp token nào** như crawler → dùng mật khẩu
mạnh, và chắc chắn router nhà không forward cổng đó ra internet.
