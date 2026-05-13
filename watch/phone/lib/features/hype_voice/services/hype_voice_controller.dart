import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:voice_counter/services/tts_service.dart';
import '../models/hype_state_snapshot.dart';
import '../models/hype_display_event.dart';

class HypeVoiceController extends GetxController {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<HypeStateSnapshot> _historyStack = [];

  final RxBool isEnabled = true.obs;
  final RxDouble volume = 0.8.obs;
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

  static const Map<String, String> _displayTexts = {
    'double_kill': 'DOUBLE KILL',
    'double_shot': 'DOUBLE SHOT',
    'nice_pair': 'NICE PAIR',
    'triple_kill': 'TRIPLE KILL',
    'triple_shot': 'TRIPLE SHOT',
    'hat_trick': 'HAT TRICK',
    'quadra_kill': 'QUADRA KILL',
    'quadra_shot': 'QUADRA SHOT',
    'dominating': 'DOMINATING',
    'penta_shot': 'PENTA SHOT',
    'unstoppable': 'UNSTOPPABLE',
    'badminton_slayer': 'BADMINTON\nSLAYER',
    'rampage': 'RAMPAGE',
    'did_you_see_that': 'DID YOU\nSEE THAT?',
    'godlike': 'GODLIKE',
    'legendary': 'LEGENDARY',
    'to_the_moon': 'TO THE MOON',
    'the_chosen_one': 'THE CHOSEN ONE',
    'mom_are_you_watching': 'MOM, ARE YOU\nWATCHING?',
    'shutdown': 'SHUTDOWN!',
    'comeback_king': 'COMEBACK\nKING',
    'unbelievable': 'UNBELIEVABLE',
    'written_in_history': 'WRITTEN IN\nHISTORY',
    'game_on': 'GAME ON',
    'lets_dance': "LET'S DANCE",
    'here_we_go': 'HERE WE GO',
  };

  static Color _glowColor(String id) {
    const legendary = {
      'godlike', 'legendary', 'to_the_moon', 'the_chosen_one',
      'mom_are_you_watching', 'comeback_king', 'written_in_history',
      'unbelievable',
    };
    const fire = {
      'penta_shot', 'unstoppable', 'badminton_slayer', 'rampage',
      'did_you_see_that', 'streak_7_plus',
    };
    const danger = {'shutdown'};

    if (legendary.contains(id)) return Colors.amberAccent;
    if (fire.contains(id)) return Colors.deepOrangeAccent;
    if (danger.contains(id)) return Colors.redAccent;
    return Colors.cyanAccent; // default streaks
  }

  // Called after hype audio finishes (or immediately if no hype queued)
  Function? onPlaybackCompleted;

  // Called when MP3 is missing — ScoreController injects this to speak via TTS
  Function(String text)? onTtsFallback;

  int _lastOpponentStreak = 0;
  int _maxDeficitTeamA = 0;
  int _maxDeficitTeamB = 0;

  List<dynamic> _triggers = [];
  String? _pendingHypeId;

  // TTS fallback texts when MP3 file is missing
  static const Map<String, String> _ttsFallback = {
    'double_kill': 'Double kill!',
    'double_shot': 'Double shot!',
    'nice_pair': 'Nice pair!',
    'triple_kill': 'Triple kill!',
    'triple_shot': 'Triple shot!',
    'hat_trick': 'Hat trick!',
    'quadra_kill': 'Quadra kill!',
    'quadra_shot': 'Quadra shot!',
    'dominating': 'Dominating!',
    'penta_shot': 'Penta shot!',
    'unstoppable': 'Unstoppable!',
    'badminton_slayer': 'Badminton slayer!',
    'rampage': 'Rampage!',
    'did_you_see_that': 'Did you see that?',
    'godlike': 'Godlike!',
    'legendary': 'Legendary!',
    'to_the_moon': 'To the moon!',
    'the_chosen_one': 'The chosen one!',
    'mom_are_you_watching': 'Mom, are you watching?',
    'shutdown': 'Shutdown!',
    'comeback_king': 'Comeback king!',
    'unbelievable': 'Unbelievable!',
    'written_in_history': 'Written in history!',
    'game_on': 'Game on!',
    'lets_dance': "Let's dance!",
    'here_we_go': 'Here we go!',
  };

  @override
  void onInit() {
    super.onInit();
    _loadConfig();
    _setupAudio();
  }

  Future<void> _loadConfig() async {
    try {
      final String response =
          await rootBundle.loadString('assets/config/hype_voice_config.json');
      final data = json.decode(response);
      _triggers = data['triggers'];
      print('🔥 [Hype] Config loaded: ${_triggers.length} triggers');
      await _validateConfigAgainstAssets();
    } catch (e) {
      print('🔥 [Hype] Config load error: $e');
    }
  }

  /// Cross-checks the config pools against bundled mp3 files. Purely
  /// informational — logs warnings, never throws. Helps catch:
  ///   • files dropped into assets/audio/hype/ but forgotten in config
  ///   • files referenced in config but missing on disk (rename/typo)
  Future<void> _validateConfigAgainstAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const String dir = 'assets/audio/hype/';
      const String ext = '.mp3';
      final bundled = <String>{
        for (final p in manifest.listAssets())
          if (p.startsWith(dir) && p.endsWith(ext))
            p.substring(dir.length, p.length - ext.length),
      };

      final referenced = <String>{};
      for (final t in _triggers) {
        final pool = t['pool'];
        if (pool is List) {
          for (final f in pool) {
            referenced.add(f.toString());
          }
        }
      }

      final unreferenced = bundled.difference(referenced).toList()..sort();
      final missing = referenced.difference(bundled).toList()..sort();

      if (unreferenced.isEmpty && missing.isEmpty) {
        print('🔥 [Hype] ✓ Config valid: ${bundled.length} files wired up');
        return;
      }
      if (unreferenced.isNotEmpty) {
        print('🔥 [Hype] ⚠️  Unreferenced mp3 files (drop them into a pool in hype_voice_config.json):');
        for (final f in unreferenced) {
          print('🔥 [Hype]    • $f');
        }
      }
      if (missing.isNotEmpty) {
        print('🔥 [Hype] ⚠️  Missing mp3 files (referenced in config but not bundled):');
        for (final f in missing) {
          final users = _triggers
              .where((t) {
                final pool = t['pool'];
                return pool is List && pool.contains(f);
              })
              .map((t) => t['id'])
              .join(', ');
          print('🔥 [Hype]    • $f (used by: $users)');
        }
      }
    } catch (e) {
      print('🔥 [Hype] Validator skipped (manifest load failed): $e');
    }
  }

  void _setupAudio() {
    // Use transient AudioFocus so hype sounds (short, foreground) yield focus back
    // to tension music automatically after playback ends — prevents music staying
    // silently paused because it received AUDIOFOCUS_LOSS (permanent) from hype.
    _audioPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        audioFocus: AndroidAudioFocus.gainTransient,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        stayAwake: false,
        isSpeakerphoneOn: false,
      ),
    ));
    _audioPlayer.setVolume(volume.value);
    volume.listen((v) => _audioPlayer.setVolume(v));
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
        final bool isTrigger = _triggers.any((t) => t['id'] == manualHype);
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
        displayText: _displayTexts[voiceId] ?? voiceId.toUpperCase().replaceAll('_', ' '),
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

  List<Map<String, String>> getHypeList() {
    return _ttsFallback.keys.map((id) {
      return {
        'id': id,
        'name': _displayTexts[id] ?? id.toUpperCase().replaceAll('_', ' '),
      };
    }).toList();
  }

  Future<void> playManualHype(String voiceId) async {
    // 1. Set as pending (overwrites auto-hype for the next playback slot)
    _pendingHypeId = voiceId;

    // 2. Trigger display overlay immediately
    if (koEffectEnabled.value) {
      displayEvent.value = HypeDisplayEvent(
        voiceId: voiceId,
        displayText: _displayTexts[voiceId] ?? voiceId.toUpperCase().replaceAll('_', ' '),
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

    for (final trigger in _triggers) {
      final String id = trigger['id'];
      final int priority = trigger['priority'];

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
      final trigger = _triggers.firstWhere(
        (t) => t['id'] == id,
        orElse: () => null,
      );
      if (trigger == null) continue;
      final pool = trigger['pool'];
      if (pool is! List) continue;
      for (final f in pool) {
        final s = f.toString();
        if (seen.add(s)) mergedPool.add(s);
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
        displayText: _displayTexts[chosen] ??
            chosen.toUpperCase().replaceAll('_', ' '),
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
    if (_pendingHypeId == null || !isEnabled.value) {
      onPlaybackCompleted?.call();
      return;
    }

    final String id = _pendingHypeId!;
    _pendingHypeId = null;
    final String assetPath = 'audio/hype/$id.mp3';

    // Pre-check: verify asset is actually bundled before handing to AudioPlayer
    try {
      await rootBundle.load('assets/$assetPath');
    } catch (_) {
      print('🔥 [Hype] Asset not bundled: $assetPath — needs rebuild');
      _doTtsFallback(id);
      return;
    }

    try {
      await _audioPlayer.play(AssetSource(assetPath));
      print('🔥 [Hype] Playing: $id');
      // onPlaybackCompleted fires via onPlayerComplete listener
    } catch (e) {
      print('🔥 [Hype] Player error for $id: $e');
      _doTtsFallback(id);
    }
  }

  void _doTtsFallback(String id) {
    if (onTtsFallback != null) {
      final text = _ttsFallback[id] ?? id.replaceAll('_', ' ');
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
