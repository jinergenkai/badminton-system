import hashlib
import os
from pathlib import Path
from datetime import datetime, timezone

# Production key recovered from main.dart.js XOR tables (B.bDr ^ B.bz7).
# The dev key "Alobo-User-Key-2026" is NOT used in production.
def _load_prod_key() -> str:
    value = os.environ.get("PROD_KEY")
    if value:
        return value.strip()
    try:
        for line in Path(__file__).with_name(".env").read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                name, value = line.split("=", 1)
                if name.strip() == "PROD_KEY":
                    return value.strip().strip("\"'")
    except FileNotFoundError:
        pass
    raise RuntimeError("Thiếu PROD_KEY trong .env hoặc environment.")


def generate_x_user_app():
    now = datetime.now(timezone.utc)
    formatted = now.strftime("%m/%d/%Y, %H:%M")
    input_str = f"{formatted}@{_load_prod_key()}"
    return hashlib.sha256(input_str.encode()).hexdigest()


if __name__ == "__main__":
    token = generate_x_user_app()
    now = datetime.now(timezone.utc)
    print(f"UTC: {now.strftime('%m/%d/%Y, %H:%M')}")
    print(f"x-user-app: {token}")
