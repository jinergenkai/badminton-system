import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_counter/services/tts_service.dart';
import '../models/hype_state_snapshot.dart';
import '../models/hype_display_event.dart';
import 'package:voice_counter/services/audio_settings.dart';
import 'package:voice_counter/services/sound_library_service.dart';
import 'package:voice_counter/services/voice_clip_service.dart';

class HypeVoiceController extends GetxController {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<HypeStateSnapshot> _historyStack = [];

  final RxBool isEnabled = true.obs;
  final RxDouble volume = 0.2.obs;
  final RxBool koEffectEnabled = true.obs;

  final RxString currentStreakTeam = ''.obs;
  final RxInt streakCount = 0.obs;
  final Rx<HypeDisplayEvent?> displayEvent = Rx<HypeDisplayEvent?>(null);
  DateTime? _lastEventTime;

  // Set to true the first time a team has trailed by >=4 within the current
  // match; cleared when that team scores and reaches tied/leading (comeback
  // fired). Allowed to be re-armed if the team later trails again by 4+.
  bool _comebackPendingA = false;
  bool _comebackPendingB = false;

  // Global per-file play count for least-played-random selection.
  // Single namespace for the whole match: a file selected from one pool
  // cannot immediately re-fire from another pool that also contains it.
  // Reset on resetState (new match), restored from snapshot on undo.
  final Map<String, int> _playCounts = {};

  static const int _setPoint = 21;
  static const int _comebackDeficitThreshold = 4;

  /// When each trigger fires — the conditions are code, in
  /// [_triggerMatches]; what they play is the Sound Library. A trigger in
  /// sound_library.json that is not listed here never fires.
  static const Map<String, String> triggerLabels = {
    'manual_trigger': 'Band: long-press a score button',
    'match_end': 'Set won',
    'crucial_moment': 'Set point / 20-all and up',
    'shutdown': 'Ends an opponent streak of 5+',
    'comeback': 'Back level after trailing by 4+',
    'streak_5_plus': 'Streak of 5 or more',
    'streak_4': 'Streak of exactly 4',
    'streak_high': 'Streak of 4 or more',
    'streak_3': 'Streak of exactly 3',
    'streak_2': 'Streak of exactly 2',
    'streak_low': 'Streak of 2 or 3',
    'random_meme': 'Any streak of 2+ (mixed in)',
    'first_point_of_match': 'New set starts',
  };

  SoundLibraryService? get _lib => SoundLibraryService.maybe;

  String _getDisplayText(String id) =>
      (_lib?.sound(id) ?? SoundDef.fromFileId(id)).display;

  Color _glowColor(String id) {
    switch (_lib?.sound(id)?.glow) {
      case 'legendary':
        return Colors.amberAccent;
      case 'fire':
        return Colors.deepOrangeAccent;
      case 'danger':
        return Colors.redAccent;
    }
    return Colors.cyanAccent; // default streaks
  }

  // Called after hype audio finishes (or immediately if no hype queued)
  Function? onPlaybackCompleted;

  // Called when a sound has no file and no rendered clip yet — ScoreController
  // injects this to speak it via TTS (the clip is rendered for next time).
  Function(String text)? onTtsFallback;

  int _lastOpponentStreak = 0;
  int _maxDeficitTeamA = 0;
  int _maxDeficitTeamB = 0;

  String? _pendingHypeId;

  static const String _prefPrefix = 'hype_';

  @override
  void onInit() {
    super.onInit();
    _loadPreferences();
    _setupAudio();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled.value = prefs.getBool('${_prefPrefix}enabled') ?? true;
    volume.value = prefs.getDouble('${_prefPrefix}volume') ?? 0.2;
    koEffectEnabled.value = prefs.getBool('${_prefPrefix}ko_enabled') ?? true;
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefPrefix}enabled', isEnabled.value);
    await prefs.setDouble('${_prefPrefix}volume', volume.value);
    await prefs.setBool('${_prefPrefix}ko_enabled', koEffectEnabled.value);
  }

  void _setupAudio() {
    // Request NO audio focus so hype voice lines mix on top of tension music
    // instead of pausing/ducking it — both are meant to play together.
    _audioPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        stayAwake: false,
        isSpeakerphoneOn: false,
      ),
    ));
    // Own level times the master, re-applied whenever either one moves.
    void applyVol() {
      final m = AudioSettings.maybe;
      _audioPlayer.setVolume(m == null ? volume.value : m.scale(volume.value));
    }
    applyVol();
    volume.listen((_) => applyVol());
    AudioSettings.maybe?.masterVolume.listen((_) => applyVol());
    // Fire onPlaybackCompleted when audio finishes naturally
    _audioPlayer.onPlayerComplete.listen((_) {
      onPlaybackCompleted?.call();
    });
  }

  void processScoreUpdate(int oldA, int oldB, int newA, int newB, {String? manualHype}) {
    if (!isEnabled.value) return;

    try {
      // Snapshot pre-event state for undo
      _historyStack.add(HypeStateSnapshot(
        currentStreakTeam: currentStreakTeam.value,
        streakCount: streakCount.value,
        lastOpponentStreak: _lastOpponentStreak,
        maxDeficitTeamA: _maxDeficitTeamA,
        maxDeficitTeamB: _maxDeficitTeamB,
        comebackPendingA: _comebackPendingA,
        comebackPendingB: _comebackPendingB,
        playCounts: Map<String, int>.from(_playCounts),
      ));
      if (_historyStack.length > 20) _historyStack.removeAt(0);

      final String scoringTeam = newA > oldA ? 'A' : 'B';

      // Streak tracking
      if (currentStreakTeam.value == scoringTeam) {
        streakCount.value++;
      } else {
        _lastOpponentStreak = streakCount.value;
        currentStreakTeam.value = scoringTeam;
        streakCount.value = 1;
      }

      // Deficit tracking (legacy max-ever)
      final int deficitA = newB - newA;
      final int deficitB = newA - newB;
      if (deficitA > _maxDeficitTeamA) _maxDeficitTeamA = deficitA;
      if (deficitB > _maxDeficitTeamB) _maxDeficitTeamB = deficitB;

      // Arm comeback flag for the team currently trailing by >=4. Sticky until
      // that team scores back to tied/leading and the comeback trigger fires.
      if (deficitA >= _comebackDeficitThreshold) _comebackPendingA = true;
      if (deficitB >= _comebackDeficitThreshold) _comebackPendingB = true;

      if (manualHype != null) {
        // Check if manualHype is a trigger ID (for randomization from pool)
        final bool isTrigger = _lib?.trigger(manualHype) != null;
        if (isTrigger) {
          print('🔥 [Hype] Manual trigger group: $manualHype');
          _prepareHype([manualHype]);
        } else {
          print('🔥 [Hype] Manual specific sound: $manualHype');
          _prepareHypeDirectly(manualHype);
        }
        return;
      }

      final List<String> matched = _evaluateTriggers(newA, newB, scoringTeam);
      if (matched.isNotEmpty) {
        // Comeback consumes the pending flag for the scoring team.
        if (matched.contains('comeback')) {
          if (scoringTeam == 'A') {
            _comebackPendingA = false;
          } else {
            _comebackPendingB = false;
          }
        }
        _prepareHype(matched);
      }
    } catch (e) {
      print('🔥 [Hype] processScoreUpdate error: $e');
    }
  }

  void _prepareHypeDirectly(String voiceId) {
    _pendingHypeId = voiceId;

    // Trigger display overlay immediately
    if (koEffectEnabled.value) {
      displayEvent.value = HypeDisplayEvent(
        voiceId: voiceId,
        displayText: _getDisplayText(voiceId),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(voiceId),
      );
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == voiceId) {
          displayEvent.value = null;
        }
      });
    }
    print('🔥 [Hype] Manual trigger via score update: $voiceId');
  }

  Future<void> playManualHype(String voiceId) async {
    // 1. Set as pending (overwrites auto-hype for the next playback slot)
    _pendingHypeId = voiceId;

    // 2. Trigger display overlay immediately
    if (koEffectEnabled.value) {
      displayEvent.value = HypeDisplayEvent(
        voiceId: voiceId,
        displayText: _getDisplayText(voiceId),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(voiceId),
      );
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == voiceId) {
          displayEvent.value = null;
        }
      });
    }

    // 3. Play logic:
    // If TTS is active, we do nothing. ScoreController.onSpeechCompleted will
    // eventually call playHype() which will pick up our _pendingHypeId.
    // If TTS is silent, play immediately.
    try {
      final ttsService = Get.find<TtsService>();
      if (!ttsService.isSpeaking.value) {
        await playHype();
      }
    } catch (e) {
      // Fallback if TtsService not found
      await playHype();
    }
  }

  /// Sound check: one hype clip at the current hype volume, bypassing the
  /// triggers and the on/off switch.
  Future<void> preview() async {
    final lib = _lib;
    if (lib == null) return;
    for (final t in const ['streak_2', 'streak_3', 'streak_5_plus', 'first_point_of_match']) {
      final pool = lib.pool(t).where((id) => lib.isBundled(id) || lib.hasUserFile(id));
      if (pool.isNotEmpty) return previewSound(pool.first);
    }
  }

  /// Plays [id] now, the way a match would (same player, same volume),
  /// ignoring the on/off switches. A line never rendered is rendered first,
  /// so a preview always sounds like the real thing.
  Future<void> previewSound(String id) async {
    final src = await _lib?.source(id);
    if (src == null) return;
    if (src.kind == SoundKind.ttsLive) {
      final path = await VoiceClipService.maybe?.prepare(src.value);
      if (path == null) return;
      return _playFile(path);
    }
    await _play(src);
  }

  /// Sound check: a TTS hype line — the first custom one, or a sample.
  Future<void> previewTtsLine() {
    final custom = _lib?.sounds.where((d) => d.custom && !(_lib?.hasUserFile(d.id) ?? false));
    return previewText((custom == null || custom.isEmpty) ? 'Đỉnh nóc kịch trần!' : custom.first.text);
  }

  /// Any text as a hype line would sound (rendered + cached first).
  Future<void> previewText(String text) async {
    if (text.trim().isEmpty) return;
    final path = await VoiceClipService.maybe?.prepare(text.trim());
    if (path != null) await _playFile(path);
  }

  Future<void> _play(SoundSource src) => src.kind == SoundKind.asset
      ? _audioPlayer.play(AssetSource(src.value))
      : _playFile(src.value);

  Future<void> _playFile(String path) => _audioPlayer.play(DeviceFileSource(path));

  Future<void> stopAudio() async {
    _pendingHypeId = null;
    await _audioPlayer.stop();
  }

  /// Returns ALL matched trigger ids at the top priority (so their pools can
  /// be merged in `_prepareHype`). Empty list if nothing matched.
  ///
  /// Same-priority triggers are intentionally additive: e.g. when streak=2
  /// both `streak_low` (generic) and `streak_2` (audio says "double") match
  /// at priority 50 and their pools merge.
  List<String> _evaluateTriggers(int newA, int newB, String scoringTeam) {
    int highestPriority = -1;
    final List<String> winners = [];

    for (final trigger in _lib?.triggers ?? const <TriggerDef>[]) {
      final String id = trigger.id;
      final int priority = trigger.priority;

      if (!_triggerMatches(id, newA, newB, scoringTeam)) continue;
      if (priority > highestPriority) {
        highestPriority = priority;
        winners
          ..clear()
          ..add(id);
      } else if (priority == highestPriority) {
        winners.add(id);
      }
    }
    return winners;
  }

  bool _triggerMatches(String id, int newA, int newB, String scoringTeam) {
    switch (id) {
      case 'match_end':
        return _hasWinner(newA, newB);

      case 'crucial_moment':
        // Tied at setPoint-1 or higher; OR exactly at setPoint-1 while leading.
        if (newA >= _setPoint - 1 && newA == newB) return true;
        if (newA == _setPoint - 1 && newA > newB) return true;
        if (newB == _setPoint - 1 && newB > newA) return true;
        return false;

      case 'streak_high':
        return streakCount.value >= 4;

      case 'streak_4':
        return streakCount.value == 4;

      case 'streak_5_plus':
        return streakCount.value >= 5;

      case 'comeback':
        final bool pending = scoringTeam == 'A' ? _comebackPendingA : _comebackPendingB;
        if (!pending) return false;
        // Scoring brought scoring team to tied or leading.
        return scoringTeam == 'A' ? newA >= newB : newB >= newA;

      case 'streak_low':
        final int s = streakCount.value;
        return s >= 2 && s <= 3;

      case 'streak_2':
        return streakCount.value == 2;

      case 'streak_3':
        return streakCount.value == 3;

      case 'shutdown':
        return _lastOpponentStreak >= 5 && streakCount.value == 1;

      case 'random_meme':
        // Merges with whichever same-priority streak triggers are matching;
        // selection within the merged pool keeps these "meme" files in
        // rotation alongside the regular streak voices.
        return streakCount.value >= 2;

      case 'first_point_of_match':
      case 'manual_trigger':
        // Not auto-matched from score events. first_point_of_match is fired
        // explicitly via playStartOfMatchHype(); manual_trigger goes through
        // playManualHype() or the manualHype param.
        return false;
    }
    return false;
  }

  bool _hasWinner(int a, int b) {
    if (a == 30 || b == 30) return true;
    if (a >= _setPoint && (a - b) >= 2) return true;
    if (b >= _setPoint && (b - a) >= 2) return true;
    return false;
  }

  void _prepareHype(List<String> triggerIds) {
    if (triggerIds.isEmpty) return;

    // Merge pools (deduped, order-preserved) across all matched triggers.
    final List<String> mergedPool = [];
    final Set<String> seen = {};
    for (final id in triggerIds) {
      for (final f in _lib?.pool(id) ?? const <String>[]) {
        if (seen.add(f)) mergedPool.add(f);
      }
    }
    if (mergedPool.isEmpty) {
      print('🔥 [Hype] Empty merged pool for triggers: $triggerIds');
      return;
    }

    final String chosen = _chooseFromPool(mergedPool);
    _pendingHypeId = chosen;

    print('🔥 [Hype] Triggers: $triggerIds → pending: $chosen');

    // Emit display event for full-screen overlay
    if (koEffectEnabled.value) {
      // Allow interruption if the previous event has been showing for a while (2.5s+)
      final now = DateTime.now();
      if (displayEvent.value != null && _lastEventTime != null) {
        if (now.difference(_lastEventTime!).inMilliseconds < 1500) {
          print('🔥 [Hype] Overlay too recent, skipping: $chosen');
          return;
        }
      }

      _lastEventTime = now;
      displayEvent.value = HypeDisplayEvent(
        voiceId: chosen,
        displayText: _getDisplayText(chosen),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(chosen),
      );
      // Auto-clear after overlay animation completes (~1.5s)
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == chosen) {
          displayEvent.value = null;
        }
      });
    }
  }

  /// Least-played random over GLOBAL per-file counts: pick uniformly among
  /// files in the pool with the minimum play count, then increment that
  /// file's count. A file shared between pools rotates more slowly than a
  /// pool-exclusive file — by design.
  String _chooseFromPool(List<String> pool) {
    int minCount = 1 << 30;
    for (final f in pool) {
      final c = _playCounts[f] ?? 0;
      if (c < minCount) minCount = c;
    }

    final candidates = [for (final f in pool) if ((_playCounts[f] ?? 0) == minCount) f];
    final chosen = candidates[Random().nextInt(candidates.length)];
    _playCounts[chosen] = (_playCounts[chosen] ?? 0) + 1;
    return chosen;
  }

  /// Play pending hype. Called after TTS finishes.
  Future<void> playHype() async {
    // Music mode never speaks. Gated here as well as at the call site so any
    // other path into the chain — undo, manual trigger — stays silent too.
    // onPlaybackCompleted is still fired: the chain must not stall.
    if (AudioSettings.maybe?.isMusicMode == true) {
      onPlaybackCompleted?.call();
      return;
    }
    if (_pendingHypeId == null || !isEnabled.value) {
      onPlaybackCompleted?.call();
      return;
    }

    final String id = _pendingHypeId!;
    _pendingHypeId = null;

    final src = await _lib?.source(id);
    if (src == null) {
      print('🔥 [Hype] Unknown sound: $id');
      onPlaybackCompleted?.call();
      return;
    }
    if (src.kind == SoundKind.ttsLive) {
      print('🔥 [Hype] $id: no clip yet, spoken live');
      _doTtsFallback(src.value);
      return;
    }
    try {
      await _play(src);
      print('🔥 [Hype] Playing: $id (${src.kind.name})');
      // onPlaybackCompleted fires via onPlayerComplete listener
    } catch (e) {
      print('🔥 [Hype] Player error for $id: $e');
      _doTtsFallback(_lib?.sound(id)?.text ?? _getDisplayText(id));
    }
  }

  void _doTtsFallback(String text) {
    if (onTtsFallback != null) {
      onTtsFallback!.call(text);
    } else {
      onPlaybackCompleted?.call();
    }
  }

  void playStartOfMatchHype() {
    _prepareHype(['first_point_of_match']);
    playHype();
  }

  void handleUndo() {
    if (_historyStack.isEmpty) return;
    final snapshot = _historyStack.removeLast();
    currentStreakTeam.value = snapshot.currentStreakTeam ?? '';
    streakCount.value = snapshot.streakCount;
    _lastOpponentStreak = snapshot.lastOpponentStreak;
    _maxDeficitTeamA = snapshot.maxDeficitTeamA;
    _maxDeficitTeamB = snapshot.maxDeficitTeamB;
    _comebackPendingA = snapshot.comebackPendingA;
    _comebackPendingB = snapshot.comebackPendingB;
    // Restore global play counts (copy so future mutations don't reach back
    // into the snapshot).
    _playCounts
      ..clear()
      ..addAll(snapshot.playCounts);
    _pendingHypeId = null;
  }

  void resetState() {
    currentStreakTeam.value = '';
    streakCount.value = 0;
    _lastOpponentStreak = 0;
    _maxDeficitTeamA = 0;
    _maxDeficitTeamB = 0;
    _comebackPendingA = false;
    _comebackPendingB = false;
    _playCounts.clear();
    _historyStack.clear();
    _pendingHypeId = null;
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    super.onClose();
  }
}
