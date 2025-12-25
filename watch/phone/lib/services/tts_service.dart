import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  Future<void> initialize() async {
    try {
      print('🔊 [TTS] Initializing Text-to-Speech...');

      // Cấu hình TTS
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(
        0.5,
      ); // Tốc độ nói (0.5 = chậm, 1.0 = bình thường)
      await _flutterTts.setVolume(1.0); // Âm lượng (0.0 - 1.0)
      await _flutterTts.setPitch(1.0); // Cao độ

      _isInitialized = true;
      print('🔊 [TTS] ✅ Text-to-Speech ready!');
    } catch (e) {
      print('🔊 [TTS] ❌ Error initializing: $e');
    }
  }

  Future<void> announceScore(
    int teamAScore,
    int teamBScore,
    String scoringTeam,
  ) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Tạo câu thông báo
      String announcement;

      if (scoringTeam == 'A') {
        announcement = "Red scores! $teamAScore to $teamBScore";
      } else {
        announcement = "Blue scores! $teamAScore to $teamBScore";
      }

      print('🔊 [TTS] 📢 Announcing: "$announcement"');

      // Đọc điểm
      await _flutterTts.speak(announcement);
    } catch (e) {
      print('🔊 [TTS] ❌ Error speaking: $e');
    }
  }

  Future<void> announceWinner(String winner) async {
    if (!_isInitialized) return;

    try {
      String announcement = "$winner wins the game!";
      print('🔊 [TTS] 🏆 Announcing: "$announcement"');
      await _flutterTts.speak(announcement);
    } catch (e) {
      print('🔊 [TTS] ❌ Error: $e');
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  void dispose() {
    _flutterTts.stop();
  }
}
