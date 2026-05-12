# 🏸 Badminton Voice Counter

```
flutter build apk --release
  adb install build/app/outputs/flutter-apk/app-release.apk
```

A voice-controlled badminton score counter app built with Flutter, GetX, and Picovoice.

## Features

✅ **Voice-Controlled Scoring** - Score points using voice commands
✅ **GetX State Management** - Reactive and efficient state handling
✅ **Beautiful Animated UI** - Modern design with smooth animations
✅ **Responsive Layout** - Works in portrait and landscape modes
✅ **Real-time Updates** - Instant score updates with animations
✅ **Game Controls** - Reset, pause, and resume functionality
✅ **Winner Detection** - Automatic game-end detection (21 points, 2-point lead)

## Installation

1. Clone the repository or copy the project files
2. Run `flutter pub get` to install dependencies
3. Connect your device or start an emulator
4. Run `flutter run`

## How to Use

### Testing Without Voice (Demo Mode)

The app includes test buttons (A and B) in the bottom right corner for testing:

- Press **A** button to add a point to Team A
- Press **B** button to add a point to Team B
- Tap the microphone icon to toggle voice listening state
- Use the settings icon (top right) to access Reset/Pause options

### Setting Up Picovoice Voice Recognition

To enable actual voice commands, you need to:

1. **Get Picovoice Access Key**
   - Sign up at [Picovoice Console](https://console.picovoice.ai/)
   - Get your FREE AccessKey

2. **Create Your Model Files**
   - Create a wake word model (`.ppn`) using Porcupine
   - Create a context model (`.rhn`) using Rhino for commands like:
     - Intent: "addPoint" with slot "team" (values: "A", "B")
   - Download the model files

3. **Add Model Files to App**
   - Copy your `.ppn` and `.rhn` files to `assets/models/` directory
   - Update `lib/services/voice_service.dart`:
     ```dart
     static const String accessKey = 'YOUR_ACTUAL_ACCESS_KEY';
     static const String keywordPath = 'assets/models/your_keyword.ppn';
     static const String contextPath = 'assets/models/your_context.rhn';
     ```

4. **Configure Voice Commands**
   - Design your Rhino context with intents like:
     - "Team A" → adds point to Team A
     - "Team B" → adds point to Team B
     - "One" or "1" → Team A
     - "Two" or "2" → Team B

### Adding Permissions

#### Android (android/app/src/main/AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

#### iOS (ios/Runner/Info.plist)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice commands</string>
```

## Project Structure

```
lib/
├── main.dart                       # App entry point
├── models/
│   └── game_state.dart            # Game state model
├── services/
│   └── voice_service.dart         # Picovoice integration
├── controllers/
│   └── score_controller.dart      # GetX controller
├── views/
│   └── score_screen.dart          # Main score screen
└── widgets/
    ├── team_card.dart             # Team score card
    └── voice_indicator.dart       # Voice listening indicator
```

## Dependencies

- **get**: ^4.6.6 - State management
- **picovoice_flutter**: ^3.0.3 - Voice recognition
- **permission_handler**: ^11.3.1 - Microphone permissions
- **google_fonts**: ^6.2.1 - Typography
- **flutter_animate**: ^4.5.0 - Animations

## Screenshots

The app features:

- Gradient backgrounds with vibrant colors
- Animated score displays with elastic animations
- Voice indicator with wave effects
- Responsive layout for all screen sizes
- Game menu with pause/reset controls

## Voice Command Examples

Once configured with Picovoice, you can say:

- "Team A" → +1 point for Team A
- "Team B" → +1 point for Team B
- Or custom commands you define in your Rhino context

## Game Rules

- First team to reach 21 points wins
- Must win by at least 2 points
- Game automatically detects winner and displays victory message

## Development

Built with ❤️ using:

- Flutter SDK
- GetX for state management
- Picovoice for voice recognition
- Material Design 3

## Notes

- The app currently runs in demo mode without actual Picovoice models
- Use the test buttons (A/B) to simulate voice commands
- Add your Picovoice model files to enable real voice recognition
- Adjust voice commands in `voice_service.dart` to match your Rhino context

## Support

For Picovoice setup help:

- [Picovoice Documentation](https://picovoice.ai/docs/)
- [Picovoice Console](https://console.picovoice.ai/)
- [Flutter Package](https://pub.dev/packages/picovoice_flutter)

Enjoy your voice-controlled badminton matches! 🏸
