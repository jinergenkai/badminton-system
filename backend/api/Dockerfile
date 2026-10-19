# backend/api — API nhỏ trên SQLite. Không cần thư viện ngoài (chỉ stdlib).
FROM python:3.12-slim

ENV TZ=Asia/Ho_Chi_Minh \
    PYTHONUNBUFFERED=1 \
    DB_PATH=/app/data/badminton.db

RUN apt-get update && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app
RUN mkdir -p /app/data

EXPOSE 8000
CMD ["python", "app.py", "--host", "0.0.0.0", "--port", "8000"]
