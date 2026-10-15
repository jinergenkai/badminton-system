# Crawler "Sân trống" — chỉ Python, KHÔNG cài Chromium: trình duyệt là Playwright server
# dùng chung trên Dokploy (biến PLAYWRIGHT_WS). Image nhẹ ~200 MB thay vì ~1.5 GB.
FROM python:3.12-slim

ENV PYTHONUTF8=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=Asia/Ho_Chi_Minh \
    CONFIG_PATH=/app/data/config.json

# tzdata: "hôm nay" của cửa sổ ngày phải theo giờ Việt Nam, không phải UTC
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000
# data/ là volume. Lần đầu chưa có config trong volume thì chép bản trong git sang;
# từ đó sửa danh sách sân trên UI sẽ ghi vào volume (CONFIG_PATH) và giữ qua redeploy.
CMD ["sh", "-c", "mkdir -p data && { [ -f \"$CONFIG_PATH\" ] || cp config.json \"$CONFIG_PATH\"; } && exec python server.py --host 0.0.0.0 --port 8000"]
