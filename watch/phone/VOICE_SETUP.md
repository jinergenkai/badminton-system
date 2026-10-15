# 🏸 Voice-Controlled Badminton Counter

A Flutter app for counting badminton scores using voice commands with Picovoice Porcupine wake word detection.

## Quick Start

### Current Setup (With Your Models)

You have two Porcupine wake word models:
- `red-point.ppn` - Triggers Team A (Blue) to score
- `blue-point.ppn` - Triggers Team B (Orange) to score

### Getting Your Picovoice AccessKey

1. Go to [Picovoice Console](https://console.picovoice.ai/)
2. Sign up for FREE
3. Copy your AccessKey
4. Open `lib/services/voice_service.dart`
5. Replace `YOUR_ACCESS_KEY_HERE` with your actual key:
   ```dart
   static const String accessKey = 'YOUR_ACTUAL_KEY_HERE';
   ```

### Adding Model Files

Your wake word files should be in the `assets/models/` directory:
```
assets/
└── models/
    ├── red-point.ppn
    └── blue-point.ppn
```

Already configured in `pubspec.yaml` ✅

### Platform Permissions

#### Android
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

#### iOS
Add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access for voice scoring</string>
```

## How It Works

### Voice Commands

- Say **"Red Point"** → Team A scores +1
- Say **"Blue Point"** → Team B scores +1

The app is always listening when the microphone is active (green icon).

### Manual Controls

- **+/- Buttons** on each team card - Manual score adjustment
- **A/B Buttons** (bottom right) - Simulate voice commands for testing
- **Microphone Icon** - Start/stop voice listening
- **Settings Icon** (top right) - Reset game or pause/resume

## Features

- ✅ Voice-controlled scoring with Porcupine
- ✅ Beautiful animated UI
- ✅ GetX state management
- ✅ Automatic winner detection (21 points, 2-point lead)
- ✅ Game pause/resume
- ✅ Score history tracking
- ✅ Responsive design (portrait/landscape)

## Running the App

```bash
# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Build APK (Android)
flutter build apk --release
```

## Troubleshooting

### "AccessKey" Error
- You need to add your Picovoice AccessKey in `voice_service.dart`
- Get it FREE from https://console.picovoice.ai/

### Model Not Found
- Ensure `.ppn` files are in `assets/models/`
- Check `pubspec.yaml` assets section
- Run `flutter clean` then `flutter pub get`

### Permissions Denied
- Grant microphone permission when prompted
- Check platform-specific permission settings

### Voice Not Detecting
- Test in a quiet environment
- Speak clearly: "Red Point" or "Blue Point"
- Check microphone icon is green (listening)
- Use test buttons A/B to verify scoring works

## Project Structure

```
lib/
├── main.dart                   # App entry
├── models/
│   └── game_state.dart        # Score state model
├── services/
│   └── voice_service.dart     # Porcupine voice recognition
├── controllers/
│   └── score_controller.dart  # GetX state management
├── views/
│   └── score_screen.dart      # Main UI
└── widgets/
    ├── team_card.dart         # Team score display
    └── voice_indicator.dart   # Voice status widget
```

## Tech Stack

- **Flutter** - UI framework
- **GetX** - State management
- **Porcupine** (Picovoice) - Wake word detection
- **Google Fonts** - Typography (Poppins)
- **Flutter Animate** - Animations

## Game Rules

- First to 21 points wins
- Must win by 2 points minimum
- Deuce continues until 2-point lead achieved

---

**Ready to play!** 🏸 Just add your Picovoice AccessKey and start scoring with your voice!
