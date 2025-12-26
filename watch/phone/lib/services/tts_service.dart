import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  String _currentLanguage = 'en-US'; // Default

  // Ngôn ngữ hỗ trợ
  static const Map<String, String> supportedLanguages = {
    'en-US': 'English',
    'vi-VN': 'Tiếng Việt',
    'zh-CN': '中文',
    'ja-JP': '日本語',
    'ko-KR': '한국어',
  };

  Future<void> initialize() async {
    try {
      print('🔊 [TTS] Initializing Text-to-Speech...');

      // Load saved language
      final prefs = await SharedPreferences.getInstance();
      _currentLanguage = prefs.getString('tts_language') ?? 'en-US';

      // Cấu hình TTS
      await _flutterTts.setLanguage(_currentLanguage);
      await _flutterTts.setSpeechRate(0.6); // Chậm để nghe rõ
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
      print('🔊 [TTS] ✅ Ready! Language: $_currentLanguage');
    } catch (e) {
      print('🔊 [TTS] ❌ Error initializing: $e');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    try {
      _currentLanguage = languageCode;
      await _flutterTts.setLanguage(languageCode);

      // Save preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_language', languageCode);

      print('🔊 [TTS] Language changed to: $languageCode');
    } catch (e) {
      print('🔊 [TTS] ❌ Error setting language: $e');
    }
  }

  String get currentLanguage => _currentLanguage;

  Future<void> announceScore(
    int teamAScore,
    int teamBScore,
    String scoringTeam,
  ) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Chỉ đọc 2 số, chậm rãi
      String announcement = "$teamAScore, $teamBScore";

      print('🔊 [TTS] 📢 Announcing: "$announcement"');

      // Đọc điểm
      await _flutterTts.speak(announcement);
    } catch (e) {
      print('🔊 [TTS] ❌ Error speaking: $e');
    }
  }

  Future<void> announceWinner(
    String winner,
    int teamAScore,
    int teamBScore,
  ) async {
    if (!_isInitialized) return;

    try {
      // Đọc người thắng kèm tỉ số theo ngôn ngữ
      String announcement;
      if (_currentLanguage.startsWith('vi')) {
        announcement = winner == 'Team A'
            ? 'Gâu Gâu thắng $teamAScore $teamBScore'
            : 'Meow Meow thắng $teamBScore $teamAScore';
      } else {
        announcement = winner == 'Team A'
            ? "$winner wins $teamAScore $teamBScore"
            : "$winner wins $teamBScore $teamAScore";
      }

      print('🔊 [TTS] 🏆 Announcing: "$announcement"');
      await _flutterTts.speak(announcement);
    } catch (e) {
      print('🔊 [TTS] ❌ Error: $e');
    }
  }

  Future<void> announceNewBattle() async {
    if (!_isInitialized) await initialize();

    try {
      String announcement;
      if (_currentLanguage.startsWith('vi')) {
        announcement = 'Trận mới bắt đầu!';
      } else {
        announcement = "New battle begins!";
      }

      print('🔊 [TTS] 🆕 Announcing: "$announcement"');
      await _flutterTts.speak(announcement);
    } catch (e) {
      print('🔊 [TTS] ❌ Error: $e');
    }
  }

  Future<void> testSpeech() async {
    if (!_isInitialized) await initialize();

    if (_currentLanguage.startsWith('vi')) {
      await _flutterTts.speak("Xin chào");
    } else if (_currentLanguage.startsWith('zh')) {
      await _flutterTts.speak("你好");
    } else if (_currentLanguage.startsWith('ja')) {
      await _flutterTts.speak("こんにちは");
    } else if (_currentLanguage.startsWith('ko')) {
      await _flutterTts.speak("안녕하세요");
    } else {
      await _flutterTts.speak("Hello");
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  void dispose() {
    _flutterTts.stop();
  }
}
