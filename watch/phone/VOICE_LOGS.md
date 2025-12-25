# 🎤 Voice Service - Cách Hoạt Động

## Luồng Hoạt Động của Wake Word Detection

### 1. **Khởi Tạo (Initialization)**
```
App Start
   ↓
ScoreController.onInit()
   ↓
VoiceService.initialize()
   ↓
Request Microphone Permission
   ↓
Create Porcupine Manager with 2 wake words:
  - red-point.ppn  (Index 0)
  - blue-point.ppn (Index 1)
   ↓
Auto-start listening
```

### 2. **Lắng Nghe (Listening)**
```
Porcupine Manager listening...
   ↓
Microphone capturing audio
   ↓
Processing audio in real-time
   ↓
Comparing with wake word models
```

### 3. **Phát Hiện Wake Word (Detection)**
```
User says "Red Point" or "Blue Point"
   ↓
Porcupine detects match!
   ↓
Callback with keywordIndex:
  - Index 0 = red-point.ppn  → Team A
  - Index 1 = blue-point.ppn → Team B
   ↓
Send command to controller
   ↓
Update score ✅
```

## 📊 Debug Logs

Khi chạy app, bạn sẽ thấy logs như sau trong console:

### ✅ Khởi Tạo Thành Công
```
🎤 [Voice] 🚀 Initializing voice service...
🎤 [Voice] Wake words: red-point.ppn (Team A), blue-point.ppn (Team B)
🎤 [Voice] Requesting microphone permission...
🎤 [Voice] Permission GRANTED ✅
🎤 [Voice] Creating Porcupine Manager...
🎤 [Voice] AccessKey: AbCdEf1234...
🎤 [Voice] ✅ Porcupine Manager created successfully!
🎤 [Voice] ▶️  Starting voice listening...
🎤 [Voice] ✅ Listening for wake words!
🎤 [Voice] 👂 Say "Red Point" or "Blue Point"
```

### 🔴 Phát Hiện "Red Point"
```
🎤 [Voice] ✨ WAKE WORD DETECTED! Index: 0
🎤 [Voice] 🔴 Red Point detected → Team A scores!
```

### 🔵 Phát Hiện "Blue Point"
```
🎤 [Voice] ✨ WAKE WORD DETECTED! Index: 1
🎤 [Voice] 🔵 Blue Point detected → Team B scores!
```

### ❌ Lỗi Thiếu AccessKey
```
🎤 [Voice] ❌ PorcupineException: Invalid AccessKey
🎤 [Voice] 🔧 Running in DEMO mode
🎤 [Voice] ℹ️  You need to add your Picovoice AccessKey
🎤 [Voice] ℹ️  Get FREE key at: https://console.picovoice.ai/
```

### ⚠️ Lỗi Thiếu Model Files
```
🎤 [Voice] ❌ PorcupineException: Cannot find asset
🎤 [Voice] ℹ️  Model files not found in assets/models/
```

## 🔍 Cách Xem Logs

### **1. Trong VS Code / Android Studio:**
- Mở tab "Debug Console" hoặc "Run"
- Chạy `flutter run`
- Xem logs real-time

### **2. Trong Terminal:**
```bash
flutter run -v
```

### **3. Trong App:**
- Nhìn vào **Voice Indicator** ở dưới màn hình
- Nó hiển thị status message cuối cùng
- Ví dụ: "👂 Listening...", "🔴 Red Point", etc.

## 🎯 Checklist Để Voice Hoạt Động

- [ ] **AccessKey đã thêm** trong `voice_service.dart` dòng 20
- [ ] **Model files** `red-point.ppn` và `blue-point.ppn` trong `assets/models/`
- [ ] **Permissions** được cấp (Android/iOS manifest)
- [ ] **Microphone** hoạt động bình thường
- [ ] **Môi trường yên tĩnh** để test

## 🧪 Cách Test

### **Demo Mode (không cần AccessKey):**
- Dùng nút A/B để test scoring
- Logs sẽ hiện: "Demo Mode - Use A/B"

### **Voice Mode (có AccessKey + models):**
1. Chạy app
2. Xem logs khởi tạo
3. Đảm bảo thấy "✅ Listening for wake words!"
4. Nói to và rõ: **"Red Point"** hoặc **"Blue Point"**
5. Xem logs detection
6. Điểm tự động tăng!

## 🐛 Troubleshooting

| Vấn đề | Log | Giải pháp |
|--------|-----|-----------|
| Không có logs | - | Check Debug Console có mở không |
| "Invalid AccessKey" | ❌ PorcupineException | Thêm AccessKey hợp lệ |
| "Cannot find asset" | ❌ Cannot find asset | Kiểm tra files `.ppn` trong `assets/models/` |
| "Permission DENIED" | ❌ Permission DENIED | Cấp quyền microphone trong settings |
| Không detect | Không có log "✨ WAKE WORD" | Nói to hơn, rõ hơn, môi trường yên |

## 💡 Tips

1. **Test với model files thật:** Đảm bảo `.ppn` files tương ứng với từ bạn nói
2. **Phát âm chuẩn:** Wake words phải khớp với cách training
3. **Môi trường:** Test ở nơi yên, ít ồn
4. **Check logs liên tục:** Logs sẽ cho biết chính xác điều gì đang xảy ra

---

**Giờ chạy app và xem logs để hiểu rõ hơn!** 🚀
