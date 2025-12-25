# 🔐 Environment Setup - .env Configuration

## ✅ Đã Setup

AccessKey giờ được load từ file `.env` thay vì hardcode trong code!

## 📁 Files

### **1. `.env`** (Chứa key thật - KHÔNG commit)
```env
PICOVOICE_ACCESS_KEY=3ZsjB+Lqz9YvUxjiPBL8lktSfYU27+Dy3HXQlzObXf+9PhpXizlbkw==
```

### **2. `.env.example`** (Template - CÓ THỂ commit)
```env
PICOVOICE_ACCESS_KEY=YOUR_ACCESS_KEY_HERE
```

### **3. `.gitignore`** (Đã thêm .env)
```
# Environment variables
.env
```

## 🔧 Setup cho người khác

Khi clone project:

```bash
# 1. Copy template
cp .env.example .env

# 2. Thêm key thật vào
nano .env  # hoặc mở bằng editor
PICOVOICE_ACCESS_KEY=your_real_key_here

# 3. Run app
flutter run
```

## 💻 Code Changes

### **main.dart**
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file
  await dotenv.load(fileName: ".env");
  
  runApp(const MyApp());
}
```

### **voice_service.dart**
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class VoiceService {
  // Load AccessKey from .env file
  static String get accessKey => 
    dotenv.env['PICOVOICE_ACCESS_KEY'] ?? 'YOUR_ACCESS_KEY_HERE';
```

### **pubspec.yaml**
```yaml
dependencies:
  flutter_dotenv: ^6.0.0

flutter:
  assets:
    - .env  # Important!
```

## 🎯 Lợi ích

✅ **Bảo mật**: Key không bị lộ trong source code
✅ **Dễ share**: Chia sẻ code không lo lộ key
✅ **Flexible**: Mỗi dev có thể dùng key riêng
✅ **Git-safe**: .env không bị commit lên Git

## 🚨 Important

### **KHÔNG commit file .env!**
```bash
# .env đã được thêm vào .gitignore
# Nhưng hãy kiểm tra:
git status

# Nếu thấy .env trong list, ĐỪNG add!
```

### **CÓ THỂ commit .env.example**
```bash
# File này làm template cho người khác
git add .env.example
git commit -m "Add env template"
```

## 🧪 Testing

```bash
# 1. Check .env loaded
flutter run

# Logs sẽ hiện:
# 🎤 [Voice] AccessKey: 3ZsjB+Lqz9...

# 2. Nếu không có key
# Logs sẽ hiện:
# 🎤 [Voice] AccessKey: YOUR_ACCESS...
```

## ⚙️ Multiple Environments

Có thể tạo nhiều env files:

```
.env.dev
.env.staging  
.env.production
```

Load theo môi trường:
```dart
await dotenv.load(fileName: ".env.dev");
```

---

**AccessKey giờ an toàn hơn!** 🔐✨
