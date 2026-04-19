import 'dart:async';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class VoiceService {
  PorcupineManager? _porcupineManager;
  bool _isListening = false;

  final StreamController<String> _commandController =
      StreamController<String>.broadcast();
  final StreamController<bool> _listeningController =
      StreamController<bool>.broadcast();

  Stream<String> get commandStream => _commandController.stream;
  Stream<bool> get listeningStream => _listeningController.stream;
  bool get isListening => _isListening;

  // Load AccessKey from .env file
  static String get accessKey =>
      dotenv.env['PICOVOICE_ACCESS_KEY'] ?? 'YOUR_ACCESS_KEY_HERE';

  // Wake word model files - must be mutable list for Porcupine
  static final List<String> keywordPaths = [
    'assets/models/red-point_en_android_v4_0_0.ppn',   // index 0 → Team A
    'assets/models/blue-point_en_android_v4_0_0.ppn',  // index 1 → Team B
    'assets/models/picovoice_android.ppn',              // index 2 → Undo
  ];

  Future<bool> requestPermissions() async {
    print('🎤 [Voice] Requesting microphone permission...');
    final status = await Permission.microphone.request();
    final granted = status.isGranted;
    print('🎤 [Voice] Permission ${granted ? "GRANTED ✅" : "DENIED ❌"}');
    return granted;
  }

  Future<void> initialize({required Function(String) onWakeWord}) async {
    print('🎤 [Voice] 🚀 Initializing voice service...');
    print(
      '🎤 [Voice] Wake words: red-point.ppn (Team A), blue-point.ppn (Team B)',
    );

    try {
      // Request microphone permission
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        throw Exception('Microphone permission not granted');
      }

      print('🎤 [Voice] Creating Porcupine Manager...');
      print('🎤 [Voice] AccessKey: ${accessKey.substring(0, 10)}...');

      // Initialize Porcupine Manager with both wake words
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        keywordPaths,
        sensitivities: [0.5, 0.5, 0.5],
        (keywordIndex) {
          print('🎤 [Voice] ✨ WAKE WORD DETECTED! Index: $keywordIndex');

          if (keywordIndex == 0) {
            print('🎤 [Voice] 🔴 Red Point detected → Team A scores!');
            onWakeWord('🔴 Red Point');
            _commandController.add('A');
          } else if (keywordIndex == 1) {
            print('🎤 [Voice] 🔵 Blue Point detected → Team B scores!');
            onWakeWord('🔵 Blue Point');
            _commandController.add('B');
          } else if (keywordIndex == 2) {
            print('🎤 [Voice] ↩️ Picovoice detected → Undo!');
            onWakeWord('↩️ Undo');
            _commandController.add('UNDO');
          } else {
            print('🎤 [Voice] ⚠️ Unknown keyword index: $keywordIndex');
          }
        },
        errorCallback: (error) {
          print('🎤 [Voice] ❌ ERROR: ${error.message}');
          _commandController.add('Error: ${error.message}');
        },
      );

      print('🎤 [Voice] ✅ Porcupine Manager created successfully!');
      _commandController.add('✅ Voice initialized');

      // Auto-start listening after initialization
      await start();
    } on PorcupineException catch (e) {
      // Failed to initialize - user needs to add AccessKey
      print('🎤 [Voice] ❌ PorcupineException: ${e.message}');
      _handleInitError(e.message);
    } catch (e) {
      print('🎤 [Voice] ❌ Unexpected error: $e');
      _handleInitError(e.toString());
    }
  }

  void _handleInitError(String? message) {
    print('🎤 [Voice] 🔧 Running in DEMO mode');

    // Show helpful error messages
    if (message?.contains('AccessKey') ?? false) {
      print('🎤 [Voice] ℹ️  You need to add your Picovoice AccessKey');
      print('🎤 [Voice] ℹ️  Get FREE key at: https://console.picovoice.ai/');
      _commandController.add('⚠️ Add AccessKey');
    } else if (message?.contains('asset') ?? false) {
      print('🎤 [Voice] ℹ️  Model files not found in assets/models/');
      _commandController.add('⚠️ Add model files');
    } else {
      print('🎤 [Voice] ℹ️  Demo Mode - Use A/B buttons');
      _commandController.add('Demo Mode');
    }
  }

  Future<void> start() async {
    print('🎤 [Voice] ▶️  Starting voice listening...');

    if (_porcupineManager != null) {
      try {
        await _porcupineManager!.start();
        _isListening = true;
        _listeningController.add(true);
        print('🎤 [Voice] ✅ Listening for wake words!');
        print('🎤 [Voice] 👂 Say "Red Point" or "Blue Point"');
        _commandController.add('👂 Listening...');
      } catch (e) {
        print('🎤 [Voice] ❌ Error starting: $e');
        _commandController.add('Error starting');
      }
    } else {
      // Demo mode - simulate listening
      print('🎤 [Voice] ⚠️  No Porcupine manager (demo mode)');
      _isListening = true;
      _listeningController.add(true);
      _commandController.add('Demo - use A/B');
    }
  }

  Future<void> stop() async {
    print('🎤 [Voice] ⏸️  Stopping voice listening...');

    if (_porcupineManager != null) {
      try {
        await _porcupineManager!.stop();
        print('🎤 [Voice] ⏹️  Stopped');
      } catch (e) {
        print('🎤 [Voice] ❌ Error stopping: $e');
      }
    }
    _isListening = false;
    _listeningController.add(false);
    _commandController.add('Stopped');
  }

  void manualCommand(String command) {
    print('🎤 [Voice] 🖱️  Manual command: $command');
    _commandController.add(command);
  }

  void dispose() {
    print('🎤 [Voice] 🗑️  Disposing voice service...');
    _porcupineManager?.delete();
    _commandController.close();
    _listeningController.close();
  }
}
