import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';

/// Plays badminton-style score announcements using bundled MP3s
/// (`assets/audio/score/<lang>/<number>.mp3` + `all.mp3`).
///
/// Falls back to TtsService.announceScore when:
///   - asset for required number is not bundled
///   - AudioPlayer fails to play
///   - score out of supported range (0..30)
///
/// Language is derived from the existing `tts_language` SharedPreferences key
/// so existing TTS settings continue to work without a separate toggle.
/// (UI for a dedicated app language picker can land later without touching this.)
class ScoreAnnouncerService extends GetxService {
  static const List<String> _supported = ['vi', 'en'];
  static const int _maxScore = 30;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<String>? _ttsLangSub;
  StreamSubscription<double>? _ttsVolSub;
  Completer<void>? _playCompleter;
  int _currentJob = 0;
  bool _initialized = false;

  final RxString currentLanguage = 'en'.obs;

  /// Fires once when the score MP3 chain completes naturally.
  /// NOT fired when:
  ///   - announcement was cancelled by a newer score
  ///   - fallback to TTS was used (TtsService.onSpeechCompleted fires instead)
  VoidCallback? onAnnouncementCompleted;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Transient audio focus — same as hype — so tension music auto-resumes
    // after the announcement instead of staying permanently ducked.
    try {
      await _player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          audioFocus: AndroidAudioFocus.gainTransient,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.assistanceNavigationGuidance,
          stayAwake: false,
          isSpeakerphoneOn: false,
        ),
      ));
    } catch (_) {}

    _completeSub = _player.onPlayerComplete.listen((_) {
      final c = _playCompleter;
      _playCompleter = null;
      if (c != null && !c.isCompleted) c.complete();
    });

    final prefs = await SharedPreferences.getInstance();
    currentLanguage.value = _normalize(prefs.getString('tts_language'));
    final savedVolume = prefs.getDouble('tts_volume') ?? 1.0;
    await _player.setVolume(savedVolume);

    // Mirror live TTS language + volume changes so the two stay aligned.
    try {
      final tts = Get.find<TtsService>();
      _ttsLangSub = tts.currentLanguageRx.listen((code) {
        currentLanguage.value = _normalize(code);
      });
      _ttsVolSub = tts.volume.listen((v) => _player.setVolume(v));
    } catch (_) {}

    print('🔊 [ScoreAnnouncer] Ready (lang=${currentLanguage.value})');
  }

  String _normalize(String? code) {
    if (code == null) return 'en';
    final lower = code.toLowerCase();
    for (final s in _supported) {
      if (lower.startsWith(s)) return s;
    }
    return 'en';
  }

  Future<void> announceScore(
    int teamAScore,
    int teamBScore,
    String scoringTeam,
  ) async {
    final int myJob = ++_currentJob;
    await _cancelInFlight();
    if (myJob != _currentJob) return;

    Future<void> fallback() => _fallbackTts(
        () => Get.find<TtsService>().announceScore(teamAScore, teamBScore, scoringTeam));

    final lang = currentLanguage.value;

    // Badminton convention: server reads first; on tie, single number + "all".
    final List<String> files;
    if (teamAScore == teamBScore) {
      if (!_inRange(teamAScore)) return fallback();
      files = [
        'audio/score/$lang/$teamAScore.mp3',
        'audio/score/$lang/all.mp3',
      ];
    } else {
      final int first = scoringTeam == 'A' ? teamAScore : teamBScore;
      final int second = scoringTeam == 'A' ? teamBScore : teamAScore;
      if (!_inRange(first) || !_inRange(second)) return fallback();
      files = [
        'audio/score/$lang/$first.mp3',
        'audio/score/$lang/$second.mp3',
      ];
    }

    await _playSequence(myJob, files, fallback);
  }

  Future<void> announceUndo(
    int teamAScore,
    int teamBScore,
    String undoneTeam,
  ) async {
    final int myJob = ++_currentJob;
    await _cancelInFlight();
    if (myJob != _currentJob) return;

    Future<void> fallback() => _fallbackTts(
        () => Get.find<TtsService>().announceUndo(teamAScore, teamBScore, undoneTeam));

    final lang = currentLanguage.value;

    // After undo, the team that LOST the point no longer serves — the other
    // team is now the server and reads first.
    final List<String> files;
    if (teamAScore == teamBScore) {
      if (!_inRange(teamAScore)) return fallback();
      files = [
        'audio/score/$lang/undo.mp3',
        'audio/score/$lang/$teamAScore.mp3',
        'audio/score/$lang/all.mp3',
      ];
    } else {
      final bool serverIsA = undoneTeam == 'B';
      final int first = serverIsA ? teamAScore : teamBScore;
      final int second = serverIsA ? teamBScore : teamAScore;
      if (!_inRange(first) || !_inRange(second)) return fallback();
      files = [
        'audio/score/$lang/undo.mp3',
        'audio/score/$lang/$first.mp3',
        'audio/score/$lang/$second.mp3',
      ];
    }

    await _playSequence(myJob, files, fallback);
  }

  /// Winner announcement contains the dynamic team name — no MP3 path can
  /// cover it. Centralized here so the same cancel + completion chain applies;
  /// implementation always delegates to TTS.
  Future<void> announceWinner(
    String winnerName,
    int teamAScore,
    int teamBScore,
  ) async {
    final int myJob = ++_currentJob;
    await _cancelInFlight();
    if (myJob != _currentJob) return;

    await _fallbackTts(
        () => Get.find<TtsService>().announceWinner(winnerName, teamAScore, teamBScore));
  }

  bool _inRange(int score) => score >= 0 && score <= _maxScore;

  /// Plays `files` sequentially with cancel awareness. On any missing asset
  /// or playback error, delegates to `onFallback` (which speaks via TTS).
  Future<void> _playSequence(
    int myJob,
    List<String> files,
    Future<void> Function() onFallback,
  ) async {
    // Pre-flight: verify every file is actually bundled. Cheaper than failing
    // mid-chain (which would leave the hype callback un-fired).
    for (final f in files) {
      try {
        await rootBundle.load('assets/$f');
      } catch (_) {
        print('🔊 [ScoreAnnouncer] Missing asset: $f — falling back to TTS');
        if (myJob != _currentJob) return;
        await onFallback();
        return;
      }
    }

    try {
      for (final f in files) {
        if (myJob != _currentJob) return;
        _playCompleter = Completer<void>();
        await _player.play(AssetSource(f));
        await _playCompleter!.future;
        if (myJob != _currentJob) return;
      }
      onAnnouncementCompleted?.call();
    } catch (e) {
      print('🔊 [ScoreAnnouncer] Playback error: $e — falling back to TTS');
      if (myJob != _currentJob) return;
      await onFallback();
    }
  }

  /// Wraps a TTS call so the hype chain still resolves even if TTS itself
  /// throws synchronously. TtsService's setCompletionHandler fires
  /// onSpeechCompleted on success — we deliberately do NOT also fire
  /// onAnnouncementCompleted there to avoid double-trigger.
  Future<void> _fallbackTts(Future<void> Function() speakFn) async {
    try {
      await speakFn();
    } catch (e) {
      print('🔊 [ScoreAnnouncer] TTS fallback also failed: $e');
      onAnnouncementCompleted?.call();
    }
  }

  Future<void> _cancelInFlight() async {
    final c = _playCompleter;
    _playCompleter = null;
    try {
      await _player.stop();
    } catch (_) {}
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> stop() async {
    _currentJob++;
    await _cancelInFlight();
  }

  @override
  void onClose() {
    _completeSub?.cancel();
    _ttsLangSub?.cancel();
    _ttsVolSub?.cancel();
    _player.dispose();
    super.onClose();
  }
}
