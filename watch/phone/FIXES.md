# GetX Observable Fix + Porcupine Voice Setup

## ✅ What Was Fixed

### 1. Voice Service Updated for Porcupine
- Changed from Picovoice (wake word + NLU) to **Porcupine** (wake word only)
- Configured for your two wake word models:
  - `red-point.ppn` → Team A scores
  - `blue-point.ppn` → Team B scores
- Added `porcupine_flutter` package
- Simplified voice detection logic

### 2. GetX Observable Issue - **IMPORTANT**

The red screen error about "GetX probably did not insert any observable variables" happens because of how we access nested values in `_gameState`.

**The Problem:**
```dart
// In ScoreController
int get teamAScore => gameState.teamAScore;  // Returns primitive int

// In UI (inside Obx)
TeamCard(
  score: controller.teamAScore,  // ❌ GetX can't track this!
)
```

**Why It Happens:**
- `teamAScore` is a getter that returns a primitive `int`
- GetX can't track changes to primitives from nested objects
- The `Obx` widget doesn't know to rebuild when `_gameState` changes

**The Solution - Two Options:**

#### Option A: Access through gameState (Recommended)
Update `score_screen.dart` to access values through `_gameState`:

```dart
// Change from:
score: controller.teamAScore,
isActive: controller.isGameActive,

// To:
score: controller.gameState.teamAScore,
isActive: controller.gameState.isGameActive,
```

This works because `controller.gameState` returns the value of `_gameState.value`, and GetX can track the `Rx<GameState>` observable.

#### Option B: Make scores directly observable
Change `ScoreController` to have separate observables:

```dart
final RxInt teamAScore = 0.obs;
final RxInt teamBScore = 0.obs;
final RxBool isGameActive = true.obs;
```

**I recommend Option A** because it keeps the state model clean and centralized.

## 🎤 Setting Up Voice Recognition

### Step 1: Get Picovoice AccessKey

1. Go to https://console.picovoice.ai/
2. Sign up (FREE)
3. Copy your AccessKey
4. Open `lib/services/voice_service.dart`
5. Replace line 20:
   ```dart
   static const String accessKey = 'YOUR_ACTUAL_PICOVOICE_ACCESS_KEY';
   ```

### Step 2: Add Your Model Files

Your wake word files should already be in:
```
assets/models/
├── red-point.ppn
└── blue-point.ppn
```

Already configured in `pubspec.yaml` ✅

### Step 3: Add Permissions

**Android** - Edit `android/app/src/main/AndroidManifest.xml`:
```xml
<manifest ...>
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application ...>
```

**iOS** - Edit `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone for voice scoring</string>
```

### Step 4: Test!

```bash
flutter run
```

- Say "Red Point" → Team A scores
- Say "Blue Point" → Team B scores  
- Or use the A/B buttons to test manually

## 🐛 Fixing the GetX Error

To fix the red screen error, I'll update the score access pattern now...
