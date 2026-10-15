# ✅ Đã Thêm Quyền Microphone

## Permissions đã thêm vào Android

File: `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

## Cách Test Lại

### 1. **Uninstall app cũ** (quan trọng!)
```bash
# Uninstall để reset permissions
adb uninstall com.example.voice_counter
```

Hoặc xóa app thủ công trên điện thoại.

### 2. **Rebuild và install**
```bash
flutter clean
flutter run
```

### 3. **Cấp quyền khi app hỏi**
- Lần đầu chạy, app sẽ hỏi quyền microphone
- Nhấn **"Allow"** / **"Cho phép"**
- Logs sẽ hiện: `🎤 [Voice] Permission GRANTED ✅`

### 4. **Nếu vẫn bị denied:**
Vào Settings điện thoại:
- Settings → Apps → Voice Counter
- Permissions → Microphone
- Bật ON

## Logs Mong Đợi

### ✅ Sau khi cấp quyền:
```
🎤 [Voice] 🚀 Initializing voice service...
🎤 [Voice] Requesting microphone permission...
🎤 [Voice] Permission GRANTED ✅
🎤 [Voice] Creating Porcupine Manager...
🎤 [Voice] ✅ Porcupine Manager created successfully!
🎤 [Voice] ▶️  Starting voice listening...
🎤 [Voice] ✅ Listening for wake words!
🎤 [Voice] 👂 Say "Red Point" or "Blue Point"
```

## iOS (Nếu cần)

File: `ios/Runner/Info.plist`

Đã sẵn sàng để thêm:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone for voice scoring</string>
```

---

**Bây giờ uninstall app cũ và chạy lại!** 🎤
