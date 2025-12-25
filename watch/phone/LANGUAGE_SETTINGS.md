# 🌍 Language Settings - Cài Đặt Ngôn Ngữ

## ✅ Tính Năng Mới

App giờ hỗ trợ **nhiều ngôn ngữ** cho TTS announcements!

## 🎯 Cách Sử Dụng

### **1. Mở Language Settings**
```
Nhấn Settings icon (⚙️) ở góc phải trên
  ↓
Chọn "Voice Language" (🌍 màu xanh lá)
  ↓
Chọn ngôn ngữ muốn dùng
```

### **2. Các Ngôn Ngữ Hỗ Trợ**

| Ngôn Ngữ | Code | Ví dụ nói |
|----------|------|-----------|
| 🇺🇸 English | en-US | "5, 3" |
| 🇻🇳 Tiếng Việt | vi-VN | "Năm, ba" |
| 🇨🇳 中文 | zh-CN | "五, 三" |
| 🇯🇵 日本語 | ja-JP | "五, 三" |
| 🇰🇷 한국어 | ko-KR | "오, 삼" |

### **3. Test Ngôn Ngữ**

Sau khi chọn ngôn ngữ:
- Nhấn nút **"Test"** bên phải để nghe
- English: "Hello"
- Tiếng Việt: "Xin chào"
- 中文: "你好"
- 日本語: "こんにちは"
- 한국어: "안녕하세요"

## 🔊 TTS Announcement Format

### **Khi Ghi Điểm (Đơn Giản)**
Chỉ đọc **2 số**, chậm rãi:

```
Điểm: 5-3
TTS nói: "5, 3"
  ↓
Chậm rãi (speechRate = 0.4)
```

**Không nói:**
- ❌ "Red scores 5 to 3"
- ❌ "Team A ghi điểm 5 - 3"

**Chỉ nói:**
- ✅ "5, 3" (tất cả ngôn ngữ)

### **Khi Kết Thúc**

Theo ngôn ngữ đã chọn:

```
English:      "Team A wins"
Tiếng Việt:   "Đội A thắng"
其他语言:      (tự động theo language code)
```

## ⚙️ Settings Được Lưu

Settings được lưu vào **SharedPreferences**:
```dart
// Saved automatically
'tts_language': 'vi-VN'
```

Khi bạn:
- ✅ Đóng app
- ✅ Mở lại app
- ✅ Settings vẫn giữ nguyên!

## 🎨 UI Language Settings

**Dialog màu xanh lá + teal**
- Icon 🌍 ở góc trái
- Title: "Voice Language"
- Subtitle: "Choose language for score announcements"
- Checkbox ✓ cho ngôn ngữ hiện tại
- Nút "Test" để thử giọng

## 🧪 Test Flow

### **Bước 1: Chọn ngôn ngữ**
```
Settings → Voice Language → Tiếng Việt
  ↓
Nhấn "Test" → Nghe: "Xin chào"
```

### **Bước 2: Ghi điểm bằng voice**
```
Nói "Blue Point"
  ↓
Điểm: 5-3
  ↓
TTS nói: "Năm, ba" (chậm rãi)
```

### **Bước 3: Thắng trận**
```
Điểm đạt 21
  ↓
TTS nói: "Đội A thắng"
```

## 📱 Code Structure

```
TtsService
  ├── supportedLanguages (Map)
  ├── currentLanguage (String)
  ├── initialize() - Load saved language
  ├── setLanguage() - Change & save
  ├── announceScore() - Chỉ đọc 2 số
  ├── announceWinner() - Theo ngôn ngữ
  └── testSpeech() - Test greeting

ScoreController
  ├── ttsService (exposed)
  ├── changeLanguage()
  └── testTts()

ScoreScreen
  ├── _showLanguageSettings()
  └── _buildLanguageOption()
```

## 🔧 Tùy Chỉnh

### Thêm ngôn ngữ mới:

```dart
// In tts_service.dart
static const Map<String, String> supportedLanguages = {
  'en-US': 'English',
  'vi-VN': 'Tiếng Việt',
  'th-TH': 'ภาษาไทย',  // Thêm Thai
  // ...
};
```

### Tùy chỉnh tốc độ:

```dart
await _flutterTts.setSpeechRate(0.3);  // Chậm hơn nữa
await _flutterTts.setSpeechRate(0.6);  // Nhanh hơn
```

---

**Rebuild app để test!** 🌍🔊

```bash
flutter run
```
