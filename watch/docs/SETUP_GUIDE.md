# BandCounter Demo — Setup Guide
## Mi Band 10 (Vela JS) ↔ Android (Kotlin/Compose)

---

## Tổng quan

```
Watch App (Vela JS)          Android App (Kotlin)
  manifest.json                applicationId
  package: "com.hung.bandcounter"  = "com.hung.bandcounter"  ← PHẢI KHỚP
  signature: từ Android .jks       signed bằng cùng .jks    ← PHẢI KHỚP
       │                                   │
       └──── connect.send() ──BLE──────────►  OnMessageReceivedListener
```

---

## BƯỚC 1: Tạo keystore cho Android app

```bash
# Chạy 1 lần duy nhất, lưu file .jks này cẩn thận
keytool -genkey -v \
  -keystore bandcounter.jks \
  -alias bandcounter \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=BandCounter, O=Hung, C=VN" \
  -storepass yourpassword \
  -keypass yourpassword
```

---

## BƯỚC 2: Extract certificate từ .jks → .pem (cho watch app)

```bash
# Bước 2a: .jks → .p12
keytool -importkeystore \
  -srckeystore bandcounter.jks \
  -destkeystore bandcounter.p12 \
  -srcstoretype jks \
  -deststoretype pkcs12 \
  -srcstorepass yourpassword \
  -deststorepass yourpassword

# Bước 2b: .p12 → .pem
openssl pkcs12 -nodes \
  -in bandcounter.p12 \
  -out bandcounter.pem \
  -passin pass:yourpassword

# Bước 2c: Tách riêng private key và certificate
# Từ bandcounter.pem, copy:
#   -----BEGIN PRIVATE KEY----- ... -----END PRIVATE KEY-----
#   → lưu vào: watch-app/sign/debug/private.pem
#              watch-app/sign/release/private.pem
#
#   -----BEGIN CERTIFICATE----- ... -----END CERTIFICATE-----
#   → lưu vào: watch-app/sign/debug/certificate.pem
#              watch-app/sign/release/certificate.pem
```

Hoặc dùng **online tool** của Xiaomi (không upload key lên server):
👉 https://iot.mi.com/vela/quickapp/zh/tools/

---

## BƯỚC 3: Lấy Xiaomi Wearable SDK (.aar)

Có 2 cách:

### Cách A — Từ WatchSDK repo (dễ nhất)
```
github.com/A5245/WatchSDK
└── WatchDemo/app/libs/
    └── xms-wearable-*.aar   ← file này
```
Copy vào `android-app/app/libs/`

### Cách B — Extract từ Mi Fitness APK
1. Download Mi Fitness APK (com.xiaomi.wearable)
2. Dùng APKTool giải nén
3. Tìm `classes.dex` → convert → tìm package `com.xiaomi.xms.wearable`
4. Repack thành .aar

---

## BƯỚC 4: Setup Watch App (AIoT-IDE trên Windows)

1. Download AIoT-IDE: https://iot.mi.com/vela/quickapp/zh/guide/start/use-ide.html
2. Mở project `watch-app/`
3. Copy cert/key vào `sign/debug/` và `sign/release/`
4. Đảm bảo `manifest.json` có:
   ```json
   "package": "com.hung.bandcounter"
   ```
5. Build → Install lên Mi Band 10 qua AIoT-IDE (hoặc Mi Fitness mod)

---

## BƯỚC 5: Build Android App

```bash
cd android-app

# Sign config trong gradle.properties (không commit lên git):
# KEYSTORE_PATH=../bandcounter.jks
# KEYSTORE_PASS=yourpassword
# KEY_ALIAS=bandcounter
# KEY_PASS=yourpassword

./gradlew assembleDebug
# Cài lên phone: adb install app/build/outputs/apk/debug/app-debug.apk
```

---

## BƯỚC 6: Cấp quyền trong Mi Fitness

Sau khi cả 2 app đã được cài:
1. Mở Mi Fitness → Device → Apps → [tên app mày]
2. Cấp quyền "Third-party app communication"
3. Hoặc dùng [Wearable-Debug](https://github.com/A5245/Wearable-Debug) plugin

---

## BƯỚC 7: Test

1. Mở Android app trên phone → chờ status "Watch connected"
2. Trên Mi Band 10 → mở BandCounter app
3. Bấm **+A** → Android app hiển thị event log "+A | 1–0 | HH:mm:ss"
4. Bấm **+B** → "+B | 1–1"
5. Bấm **↩ Undo** → "undo"

---

## Troubleshooting

| Vấn đề | Nguyên nhân | Fix |
|--------|-------------|-----|
| Watch app không gửi được | Signature không khớp | Re-sign watch app với đúng .jks |
| Android không nhận event | Package name khác nhau | Kiểm tra `applicationId` vs `manifest.json package` |
| "Permission denied" trong Mi Fitness | Chưa cấp quyền third-party | Dùng Wearable-Debug hoặc cấp thủ công |
| Status "not connected" dù watch đang kết nối | MessageClient chưa init | Đảm bảo `addListener` chạy trước khi watch gửi |

---

## Files structure

```
watch-app/
├── src/
│   ├── manifest.json          ← package: "com.hung.bandcounter"
│   └── pages/index/
│       └── index.ux           ← UI + interconnect logic
└── sign/
    ├── debug/
    │   ├── private.pem        ← extract từ bandcounter.jks
    │   └── certificate.pem
    └── release/
        ├── private.pem
        └── certificate.pem

android-app/
├── MainActivity.kt            ← Compose UI + MessageClient listener
├── build.gradle.kts           ← applicationId: "com.hung.bandcounter"
└── app/libs/
    └── xms-wearable-*.aar     ← Xiaomi SDK
```

---

## References

- Vela interconnect API: https://iot.mi.com/vela/quickapp/zh/features/network/interconnect.html
- Xiaomi Vela quickstart: https://iot.mi.com/vela/quickapp/zh/guide/start/use-ide.html
- WatchSDK demo (Android side): https://github.com/A5245/WatchSDK
- Ebook Android client (open source reference): https://github.com/youshen2/com.bandbbs.ebook-android
- BandBBS Mi Band 10 forum: https://www.bandbbs.cn/forums/mb10/
