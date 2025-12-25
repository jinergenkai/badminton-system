# 🔊 Text-to-Speech - Đọc Điểm Tự Động

## ✅ Đã Thêm Tính Năng

App giờ sẽ **tự động đọc điểm** sau mỗi lần ghi điểm bằng voice!

## 🎯 Cách Hoạt Động

### **1. Ghi Điểm Bằng Voice**
```
User nói: "Blue Point"
   ↓
Wake word detected
   ↓
Team B +1 điểm
   ↓
TTS đọc: "Blue scores! 5 to 3" 🔊
```

### **2. Ghi Điểm Bằng Nút**
```
User nhấn nút +
   ↓
Team tăng điểm
   ↓
KHÔNG đọc (chỉ đọc khi dùng voice)
```

### **3. Kết Thúc Trò Chơi**
```
Điểm đạt 21 (dẫn trước 2 điểm)
   ↓
TTS đọc: "Team A wins the game!" 🏆
   ↓
Hiện popup thông báo
```

## 📢 Các Câu TTS Sẽ Nói

### Khi Ghi Điểm:
- **Team A (Red):** "Red scores! X to Y"
- **Team B (Blue):** "Blue scores! X to Y"

### Khi Kết Thúc:
- **Team A thắng:** "Team A wins the game!"
- **Team B thắng:** "Team B wins the game!"

## ⚙️ Cấu Hình TTS

File: `lib/services/tts_service.dart`

```dart
await _flutterTts.setLanguage("en-US");    // Ngôn ngữ
await _flutterTts.setSpeechRate(0.5);      // Tốc độ (0.5 = chậm)
await _flutterTts.setVolume(1.0);          // Âm lượng (1.0 = max)
await _flutterTts.setPitch(1.0);           // Cao độ giọng
```

### Tùy Chỉnh:

**Nói nhanh hơn:**
```dart
await _flutterTts.setSpeechRate(0.8);  // 0.8 = nhanh hơn
```

**Giọng nam/nữ:**
```dart
await _flutterTts.setPitch(0.8);  // Thấp = giọng nam
await _flutterTts.setPitch(1.2);  // Cao = giọng nữ
```

**Đổi sang tiếng Việt:**
```dart
await _flutterTts.setLanguage("vi-VN");
// Đổi text trong announceScore():
"Đỏ ghi điểm! $teamAScore - $teamBScore"
```

## 🧪 Test TTS

### Cách 1: Voice Command
```
1. Chạy app
2. Nói "Blue Point"
3. Nghe: "Blue scores! 1 to 0" 🔊
```

### Cách 2: Nút Test
```
1. Nhấn nút A hoặc B (dưới góc phải)
2. KHÔNG nghe gì (vì không phải voice command)
3. Nhấn nút + trên card → KHÔNG nghe
```

### Cách 3: Kiểm Tra Winner
```
1. Ghi điểm đến 21 cho 1 team
2. Nghe: "Team A wins the game!" 🏆
```

## 📊 Logs

Khi TTS hoạt động, bạn sẽ thấy:

```
🔊 [TTS] Initializing Text-to-Speech...
🔊 [TTS] ✅ Text-to-Speech ready!
🔊 [TTS] 📢 Announcing: "Blue scores! 5 to 3"
🔊 [TTS] 🏆 Announcing: "Team A wins the game!"
```

## ⚡ Performance

- TTS chạy async, không block UI
- Chỉ đọc khi ghi điểm bằng VOICE
- Tự động dispose khi đóng app

## 🐛 Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| Không nghe thấy | Check âm lượng điện thoại |
| Giọng lạ | Đổi language hoặc pitch |
| Nói quá nhanh | Giảm speechRate xuống 0.4-0.5 |
| Nói quá chậm | Tăng speechRate lên 0.7-0.8 |

---

**Test ngay!** Nói "Blue Point" và nghe app đọc điểm! 🔊🏸
