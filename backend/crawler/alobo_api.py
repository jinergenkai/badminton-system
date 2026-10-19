"""
Standalone Alobo API caller.

Reverse-engineered from the Flutter Web app at datlich.alobo.vn:
  - x-user-app = SHA-256("MM/dd/yyyy, HH:mm@<PROD_KEY>") using current UTC time
  - Response decryption: AES-256-CBC with known key, IV from response
"""

import json
import base64
import sys

import requests
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

from gen_x_user_app import generate_x_user_app

AES_KEY = b"Al0b0@Doczy2026_8768_Secret_0810"

BASE_URL = "https://user-global.alobo.vn/v2"


def decrypt_envelope(envelope: dict) -> dict:
    iv = base64.b64decode(envelope["iv"])
    data = base64.b64decode(envelope["data"])
    cipher = AES.new(AES_KEY, AES.MODE_CBC, iv)
    plaintext = unpad(cipher.decrypt(data), 16).decode()
    return json.loads(plaintext)


def make_headers(bearer_token: str) -> dict:
    return {
        "accept": "*/*",
        "authorization": f"Bearer {bearer_token}",
        "origin": "https://datlich.alobo.vn",
        "referer": "https://datlich.alobo.vn/",
        "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36",
        "x-custom-lang": "vi",
        "x-name-app": "alobo-user",
        "x-platform": "web",
        "x-user-app": generate_x_user_app(),
        "x-version-app": "2.10.4",
    }


def call_api(path: str, bearer_token: str, method: str = "GET", **kwargs) -> dict:
    url = f"{BASE_URL}{path}"
    headers = make_headers(bearer_token)
    resp = requests.request(method, url, headers=headers, **kwargs)
    resp.raise_for_status()
    body = resp.json()
    if body.get("enc"):
        return decrypt_envelope(body)
    return body


if __name__ == "__main__":
    token = sys.argv[1] if len(sys.argv) > 1 else input("Bearer token: ").strip()
    path = sys.argv[2] if len(sys.argv) > 2 else "/user/account/profile"

    print(f"x-user-app: {generate_x_user_app()}")
    print(f"Calling {BASE_URL}{path} ...")

    result = call_api(path, token)
    print(json.dumps(result, indent=2, ensure_ascii=False))
