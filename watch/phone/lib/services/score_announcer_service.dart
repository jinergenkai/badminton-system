import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';
import 'audio_settings.dart';
import 'voice_clip_service.dart';
import 'clip_gain_service.dart';
import 'dart:io';

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

  /// The announcer's own level, kept so the master can be re-applied to it
  /// without losing what the user set for this source.
  double _ownVolume = 1.0;

  double _scaled(double v) {
    final m = AudioSettings.maybe;
    return m == null ? v : m.scale(v);
  }

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
    _ownVolume = savedVolume;
    await _player.setVolume(_scaled(savedVolume));
    AudioSettings.maybe?.masterVolume
        .listen((_) => _player.setVolume(_scaled(_ownVolume)));

    // Mirror live TTS language + volume changes so the two stay aligned.
    try {
      final tts = Get.find<TtsService>();
      _ttsLangSub = tts.currentLanguageRx.listen((code) {
        currentLanguage.value = _normalize(code);
      });
      _ttsVolSub = tts.volume.listen((v) {
        _ownVolume = v;
        _player.setVolume(_scaled(v));
      });
      // Past 100%: render this language's clips at the new level ahead of
      // the next point, once the slider has settled.
      debounce(tts.volume, (_) => warmBoost(), time: const Duration(milliseconds: 800));
      debounce(currentLanguage, (_) => warmBoost(), time: const Duration(milliseconds: 800));
    } catch (_) {}
    warmBoost();

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

  /// [serverName], when the set is named, is read after the score:
  /// "Năm – Ba, Hùng giao cầu".
  Future<void> announceScore(
    int teamAScore,
    int teamBScore,
    String scoringTeam, {
    String? serverName,
  }) async {
    final int myJob = ++_currentJob;
    await _cancelInFlight();
    if (myJob != _currentJob) return;

    Future<void> fallback() => _fallbackTts(
        () => Get.find<TtsService>().announceScore(teamAScore, teamBScore, scoringTeam));

    final lang = currentLanguage.value;
    int say(int n) => AudioSettings.spokenScore(n, lang);

    // Badminton convention: server reads first; on tie, single number + "all".
    final List<String> files;
    if (teamAScore == teamBScore) {
      if (!_inRange(teamAScore)) return fallback();
      files = [
        'audio/score/$lang/${say(teamAScore)}.mp3',
        'audio/score/$lang/all.mp3',
      ];
    } else {
      final int first = say(scoringTeam == 'A' ? teamAScore : teamBScore);
      final int second = say(scoringTeam == 'A' ? teamBScore : teamAScore);
      if (!_inRange(first) || !_inRange(second)) return fallback();
      files = [
        'audio/score/$lang/$first.mp3',
        'audio/score/$lang/$second.mp3',
      ];
    }

    String? tail = serverName == null || serverName.isEmpty ? null : serveTail(serverName, lang);
    // Boosted clip ready: it simply joins the file sequence. Otherwise the
    // tail is spoken live by TTS after the files.
    final clip = tail == null ? null : await _clip(tail);
    if (myJob != _currentJob) return;
    if (clip != null) {
      files.add(clip);
      tail = null;
    }
    await _playSequence(myJob, files, fallback, tail: tail);
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
    int say(int n) => AudioSettings.spokenScore(n, lang);

    // After undo, the team that LOST the point no longer serves — the other
    // team is now the server and reads first.
    final List<String> files;
    if (teamAScore == teamBScore) {
      if (!_inRange(teamAScore)) return fallback();
      files = [
        'audio/score/$lang/undo.mp3',
        'audio/score/$lang/${say(teamAScore)}.mp3',
        'audio/score/$lang/all.mp3',
      ];
    } else {
      final bool serverIsA = undoneTeam == 'B';
      final int first = say(serverIsA ? teamAScore : teamBScore);
      final int second = say(serverIsA ? teamBScore : teamAScore);
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

    // Boosted clip + bundled number clips when ready; plain TTS otherwise.
    final lang = currentLanguage.value;
    final clip = await _clip(winnerLine(winnerName, lang));
    if (myJob != _currentJob) return;
    if (clip != null && _inRange(teamAScore) && _inRange(teamBScore)) {
      await _playSequence(
        myJob,
        [clip, 'audio/score/$lang/$teamAScore.mp3', 'audio/score/$lang/$teamBScore.mp3'],
        () => _fallbackTts(
            () => Get.find<TtsService>().announceWinner(winnerName, teamAScore, teamBScore)),
      );
      return;
    }
    await _fallbackTts(
        () => Get.find<TtsService>().announceWinner(winnerName, teamAScore, teamBScore));
  }

  bool _inRange(int score) => score >= 0 && score <= _maxScore;

  /// Every number clip of the current language at the current Voice level.
  void warmBoost() {
    final lang = currentLanguage.value;
    ClipGainService.maybe?.warm([
      for (var n = 0; n <= _maxScore; n++) 'audio/score/$lang/$n.mp3',
      'audio/score/$lang/all.mp3',
      'audio/score/$lang/undo.mp3',
    ], _ownVolume);
  }

  /// "<name> giao cầu" — read after the score when the set is named.
  static String serveTail(String name, String lang) =>
      lang.startsWith('vi') ? '$name giao cầu' : '$name to serve';

  /// "<winner> thắng" — followed by the two scores as bundled number clips.
  static String winnerLine(String winnerName, String lang) =>
      lang.startsWith('vi') ? '$winnerName thắng' : '$winnerName wins';

  /// The cached clip for [text] (level-matched and boosted); null when it
  /// was never rendered — it is then rendered in the background for next time.
  Future<String?> _clip(String text) async => VoiceClipService.maybe?.resolve(text);

  /// Plays `files` sequentially with cancel awareness. On any missing asset
  /// or playback error, delegates to `onFallback` (which speaks via TTS).
  Future<void> _playSequence(
    int myJob,
    List<String> files,
    Future<void> Function() onFallback, {
    String? tail,
  }) async {
    // Pre-flight: verify every file is actually bundled. Cheaper than failing
    // mid-chain (which would leave the hype callback un-fired). Boosted
    // copies are resolved here too, so there is no gap between clips.
    final play = <String>[];
    for (final f in files) {
      try {
        if (f.startsWith('/')) {
          if (!File(f).existsSync()) throw Exception('gone');
          continue;
        }
        await rootBundle.load('assets/$f');
      } catch (_) {
        print('🔊 [ScoreAnnouncer] Missing asset: $f — falling back to TTS');
        if (myJob != _currentJob) return;
        await onFallback();
        return;
      }
    }
    for (final f in files) {
      play.add(await ClipGainService.maybe?.boosted(f, _ownVolume) ?? f);
    }
    if (myJob != _currentJob) return;

    try {
      for (final f in play) {
        if (myJob != _currentJob) return;
        // Held locally: a newer announcement's _cancelInFlight() nulls the
        // field while play() is still awaiting, and `_playCompleter!` then
        // threw "Null check operator used on a null value" (seen in logcat
        // on quick taps). The local completer is completed by that cancel.
        final done = Completer<void>();
        _playCompleter = done;
        await _player.play(f.startsWith('/') ? DeviceFileSource(f) : AssetSource(f));
        await done.future;
        if (myJob != _currentJob) return;
      }
      if (tail != null) {
        // Spoken by TTS; its completion handler continues the hype chain
        // exactly like the MP3 path would have.
        await _fallbackTts(() => Get.find<TtsService>().speak(tail));
        return;
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
