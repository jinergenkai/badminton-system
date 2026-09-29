import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/match.dart';
import '../models/team_config.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../services/score_announcer_service.dart';
import '../services/foreground_service.dart';
import '../services/database_service.dart';
import '../services/watch_connectivity_service.dart';
import '../services/music_service.dart';
import '../services/audio_settings.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';

class ScoreController extends GetxController {
  final VoiceService _voiceService = VoiceService();
  final TtsService _ttsService = Get.put(TtsService());
  final ScoreAnnouncerService _scoreAnnouncer = Get.put(ScoreAnnouncerService());
  final WatchConnectivityService _watchService = Get.put(WatchConnectivityService());
  final HypeVoiceController _hypeController = Get.put(HypeVoiceController());
  final MusicService _musicService = Get.put(MusicService());
  final AudioSettings _audio = AudioSettings.i;
  final Uuid _uuid = const Uuid();

  final Rx<GameState> _gameState = GameState().obs;
  final RxString lastCommand = ''.obs;
  final RxBool isVoiceActive = false.obs;
  final RxBool isGameEnded = false.obs;
  final RxBool isWatchConnected = false.obs;

  final RxBool isCooldownActive = false.obs;
  final RxDouble cooldownProgress = 0.0.obs;
  Timer? _cooldownTimer;
  Timer? _autoResetTimer;
  Timer? _watchConnectionPoll;

  // Configurable delay before auto-starting next game after a win
  final RxInt autoResetDelay = 60.obs;

  // New settings
  final RxBool scoreAnnouncementsEnabled = true.obs;
  final RxBool hapticFeedbackEnabled = true.obs;
  final RxDouble cooldownDuration = 1.0.obs;

  /// Display-only: which end of the screen each team is drawn on.
  ///
  /// Purely a layout concern — team A stays team A, keeps its score, its name,
  /// its red colour and its watch button (`score_A`). All this does is put the
  /// two team cards in the other order so the phone scoreboard matches where
  /// the players actually stand on court. Nothing downstream (scoring,
  /// announcements, history, hype, watch protocol) reads it.
  ///
  /// Toggled from the watch's settings page, which sends a bare
  /// `{action: 'swap_sides'}` and keeps no state of its own.
  final RxBool sidesSwapped = false.obs;

  /// Band "Blank Phone": black overlay + minimum brightness, e.g. while the
  /// user is off court. Taps on the phone are swallowed until it wakes.
  final RxBool phoneBlank = false.obs;

  void setPhoneBlank(bool on) {
    if (phoneBlank.value == on) return;
    phoneBlank.value = on;
    _watchService.setWindowBlank(on);
    print('⌚ [Controller] phone blank = $on');
  }

  TeamConfig? _teamConfig;
  StreamSubscription? _watchCommandSubscription;
  bool _isSyncingFromWatch = false;
  String? _lastBandMatchId;
  int _lastBandRevision = -1;
  String _lastBandRallies = '';
  DateTime? _lastBandSeen;
  Future<void> _dbChain = Future.value();

  /// The band app has spoken recently, so it is the scoreboard's authority:
  /// phone taps become commands, and saved history comes from band records.
  /// Without a recent band message the phone runs standalone as before.
  bool get _bandLive =>
      _lastBandSeen != null &&
      DateTime.now().difference(_lastBandSeen!) < const Duration(minutes: 15);

  Rx<GameState> get gameStateObservable => _gameState;
  TtsService get ttsService => _ttsService;
  WatchConnectivityService get watchService => _watchService;

  GameState get gameState => _gameState.value;
  int get teamAScore => gameState.teamAScore;
  int get teamBScore => gameState.teamBScore;
  bool get isGameActive => gameState.isGameActive;
  String get winner => gameState.winner;

  Color get teamAColor => _teamConfig?.teamAColor ?? Colors.redAccent;
  Color get teamBColor => _teamConfig?.teamBColor ?? Colors.blueAccent;

  @override
  void onInit() {
    super.onInit();
    _loadTeamConfig();
    _loadSettings();
    // _initializeVoiceService(); // DISABLED: Picovoice wake-word
    _ttsService.initialize();
    _scoreAnnouncer.initialize();
    // _initializeForegroundService(); // DISABLED: foreground notification
    _initializeWatchSync();
    _setupAudioChain();
    _musicService.initialize().then((_) => _applyMode(_audio.mode.value));
    // Switching mode takes effect immediately, from the phone or the watch.
    _audio.mode.listen(_applyMode);
  }

  /// Music mode runs a track continuously; commentary mode leaves the speaker
  /// free for the announcer and hype, with music only at tension and win.
  void _applyMode(String mode) {
    if (mode == PlayMode.music) {
      _musicService.startContinuous();
    } else {
      _musicService.stopMusic();
    }
    _watchService.sendSettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    autoResetDelay.value = prefs.getInt('auto_reset_delay') ?? 60;
    scoreAnnouncementsEnabled.value = prefs.getBool('score_announcements_enabled') ?? true;
    hapticFeedbackEnabled.value = prefs.getBool('haptic_feedback_enabled') ?? true;
    cooldownDuration.value = prefs.getDouble('cooldown_duration') ?? 1.0;
    sidesSwapped.value = prefs.getBool('sides_swapped') ?? false;
  }

  Future<void> setSidesSwapped(bool swapped) async {
    sidesSwapped.value = swapped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sides_swapped', swapped);
  }

  Future<void> toggleSidesSwapped() => setSidesSwapped(!sidesSwapped.value);

  Future<void> setAutoResetDelay(int seconds) async {
    autoResetDelay.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_reset_delay', seconds);
  }

  Future<void> setScoreAnnouncementsEnabled(bool enabled) async {
    scoreAnnouncementsEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('score_announcements_enabled', enabled);
  }

  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    hapticFeedbackEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('haptic_feedback_enabled', enabled);
  }

  Future<void> setCooldownDuration(double seconds) async {
    cooldownDuration.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cooldown_duration', seconds);
  }

  void _setupAudioChain() {
    // Score/undo/winner announcement done → hype voice. Two completion
    // sources converge:
    //   1. ScoreAnnouncerService finishes its MP3 chain (score/undo MP3 path)
    //   2. TtsService finishes (covers: winner — always TTS since team name
    //      is dynamic — and any score/undo fallback path)
    // Both wired to the same hype trigger so the chain stays consistent.
    _scoreAnnouncer.onAnnouncementCompleted = () {
      _hypeController.playHype();
    };
    _ttsService.onSpeechCompleted = () {
      _hypeController.playHype();
    };

    // Hype done (or skipped) → win music OR resume/start tension music.
    // Tension music is started HERE (not during score update) so it never
    // competes with TTS or hype for AudioFocus.
    _hypeController.onPlaybackCompleted = () {
      if (isGameEnded.value) {
        _musicService.playWinMusic();
      } else if (_musicService.isTensionMode.value && !_musicService.isPlaying.value) {
        // Defensive: tension should keep playing under hype (no focus stealing
        // anymore), but resume it if it ended up paused for any other reason.
        _musicService.resume();
      } else {
        _checkTensionMusic();
      }
    };

    // When hype MP3 is missing, speak via TTS instead
    _hypeController.onTtsFallback = (String text) {
      _ttsService.speak(text);
    };
  }

  Future<void> _initializeWatchSync() async {
    try {
      await _watchService.initialize();
      _watchCommandSubscription = _watchService.watchCommandStream.listen((event) {
        _handleWatchCommand(event);
      });
      _watchConnectionPoll?.cancel();
      _watchConnectionPoll = Timer.periodic(const Duration(seconds: 5), (timer) async {
        isWatchConnected.value = await _watchService.isWatchConnected();
      });
    } catch (e) {
      print('⌚ [Controller] Watch sync init error: $e');
    }
  }

  void _handleWatchCommand(Map<String, dynamic> event) {
    if (event['type'] != 'command') return;

    final action = event['action'] as String;
    final int newScoreA = event['scoreA'] ?? -1;
    final int newScoreB = event['scoreB'] ?? -1;
    final bool isResetFromWatch = event['reset'] == true;
    // `silent` = sender already mutated its local state (e.g., watch index page).
    // When false (e.g., from settings page), phone MUST echo back so watch index can mirror.
    final bool silent = event['silent'] == true;
    final bool fromBand = event['source'] == 'band';
    final String? bandMatchId = event['matchId'] as String?;
    final int bandRevision = event['revision'] is num
        ? (event['revision'] as num).toInt() : -1;

    // Band history push: upsert by matchId, then ack so the band moves on to
    // the next unsynced record. Upserts are chained so two never race.
    if (action == 'match_record') {
      _lastBandSeen = DateTime.now();
      _storeBandRecord(event);
      return;
    }

    // Revisions only gate side effects (hype, voice). The score itself is
    // always mirrored: an explicit refresh carries the same revision as the
    // last message, and dropping it would leave a diverged phone diverged.
    bool isNewRev = true;
    if (fromBand) {
      _lastBandSeen = DateTime.now();
      if (event['rallies'] != null) _lastBandRallies = event['rallies'].toString();
      if (bandMatchId != null && bandRevision >= 0) {
        isNewRev = !(_lastBandMatchId == bandMatchId && bandRevision <= _lastBandRevision);
        _lastBandMatchId = bandMatchId;
        _lastBandRevision = bandRevision;
      }
      // Band state says this set is open again (undo after a win): reopen it
      // here too, and drop any record already saved for it.
      if (event['status'] == 'active' && isGameEnded.value) {
        _autoResetTimer?.cancel();
        isGameEnded.value = false;
        _gameState.value = gameState.copyWith(isGameActive: true);
        if (bandMatchId != null) {
          _dbChain = _dbChain.then((_) => DatabaseService.deleteMatchById(bandMatchId));
        }
      }
    }

    print('⌚ [Controller] Command from watch: $action (Scores: $newScoreA-$newScoreB, silent=$silent)');

    // Flip which end of the phone screen each team is drawn on. Scores are
    // untouched, so there is nothing to sync back to the watch.
    if (action == 'phone_screen') {
      setPhoneBlank(event['blank'] == true);
      return;
    }

    if (action == 'swap_sides') {
      toggleSidesSwapped();
      if (hapticFeedbackEnabled.value) {
        HapticFeedback.mediumImpact();
      }
      return;
    }

    // Handle sync requests
    if (action == 'request_sync' || action == 'request_current_state') {
      _watchService.sendScoreCommand('request_current_state');
      return;
    }

    // Handle reset/next match
    if (action == 'reset' || action == 'next_match' || action == 'new_match') {
      // Echo of a reset the phone already applied optimistically.
      if (fromBand && gameState.teamAScore == 0 && gameState.teamBScore == 0 &&
          !isGameEnded.value) return;
      if (silent) _isSyncingFromWatch = true;
      resetGame();
      if (silent) _isSyncingFromWatch = false;
      return;
    }

    // Handle undo
    if (action == 'undo') {
      if (newScoreA >= 0 && newScoreB >= 0) {
        // Watch sends post-undo target scores — use them as source of truth.
        // Phone's undo stack is independent and may diverge from watch history;
        // using watch scores prevents the score mismatch / feedback loop.
        final int oldA = gameState.teamAScore;
        final int oldB = gameState.teamBScore;
        if (oldA == newScoreA && oldB == newScoreB) return; // duplicate guard

        final stack = List<GameState>.from(gameState.stateStack);
        if (stack.isNotEmpty) stack.removeLast(); // best-effort stack trim

        _gameState.value = gameState.copyWith(
          teamAScore: newScoreA,
          teamBScore: newScoreB,
          stateStack: stack,
        );
        _hypeController.handleUndo();
        // Undo is almost always an immediate misclick correction — announcing
        // "undo, X Y" out loud right before the real point is noisy and gets
        // talked over. Stay silent here; only the hype voice (if any) plays.
        _hypeController.playHype();
        // Do NOT send sync back — watch already applied undo locally (silent=true).
        // Sending phone's own stack result was the root cause of score corruption.
      } else {
        // No target scores provided — fall back to phone's own stack
        if (!gameState.canUndo) {
          _watchService.sendScoreUpdate(gameState, action: 'sync');
          return;
        }
        undo();
      }
      return;
    }

    // Handle score updates
    if (action == 'score_A' || action == 'score_B' || action == 'seed_score' ||
        action == 'band_online' || action == 'band_ready' ||
        action == 'band_reconnected' || action == 'state_reply' ||
        action == 'manual_state') {
      if (newScoreA >= 0 && newScoreB >= 0) {
        final int oldA = gameState.teamAScore;
        final int oldB = gameState.teamBScore;
        final String? manualHype = event['manualHype'];
        
        // Duplicate-message guard. Also absorbs the band's echo of a point
        // the phone already applied optimistically — no second announcement.
        if (newScoreA == oldA && newScoreB == oldB && manualHype == null) return;

        // DEFENSIVE LOGIC: If watch sends a score that is lower than phone (and not a reset), 
        // it likely means the watch app just restarted and hasn't synced yet.
        // We catch this BEFORE the 'hasWinner' reset check to avoid accidental match resets.
        if (!fromBand && !isResetFromWatch && (newScoreA < oldA || newScoreB < oldB)) {
          print('⌚ [Controller] Rejected lower scores from watch. Forcing sync back.');
          _watchService.sendScoreCommand('request_current_state');
          return;
        }

        // If game ended, any score button from watch resets the game (if it's not a stale update from restart)
        if (!fromBand && gameState.hasWinner) {
          resetGame();
          return;
        }

        _isSyncingFromWatch = true;
        
        final currentStack = List<GameState>.from(gameState.stateStack);
        final snapshot = gameState.copyWith(stateStack: []);
        currentStack.add(snapshot);
        if (currentStack.length > 20) currentStack.removeAt(0);

        _gameState.value = gameState.copyWith(
          teamAScore: newScoreA,
          teamBScore: newScoreB,
          stateStack: currentStack,
          history: _appendHistory('Watch: $action${manualHype != null ? " ($manualHype)" : ""}'),
        );

        _isSyncingFromWatch = false;

        final bool isPoint = (action == 'score_A' || action == 'score_B') && isNewRev;
        // Scoring again on the band means the user is back on court.
        if (isPoint) setPhoneBlank(false);
        if (isPoint) {
          _hypeController.processScoreUpdate(oldA, oldB, newScoreA, newScoreB, manualHype: manualHype);
        }
        if (!gameState.hasWinner && isPoint) {
          _announceScoreChange(newScoreA, newScoreB, action == 'score_A' ? 'A' : 'B');
        }
        // _checkTensionMusic() moved to onPlaybackCompleted — avoids AudioFocus conflict
        // ForegroundService.updateScores(teamAScore: newScoreA, teamBScore: newScoreB);
        _checkGameEnd(fromBand: fromBand);
      }
    }
  }

  void _storeBandRecord(Map<String, dynamic> event) {
    final id = event['matchId'];
    final rev = event['revision'] is num ? (event['revision'] as num).toInt() : -1;
    _dbChain = _dbChain.then((_) async {
      try {
        await _persistBandTerminalMatch(event);
      } catch (e) {
        print('⌚ [Controller] band record save failed: $e');
        return; // no ack: the band retries on its next trigger
      }
      if (id is String) {
        _watchService.sendScoreCommand('match_ack', extra: {'matchId': id, 'revision': rev});
      }
    });
  }

  Future<void> _persistBandTerminalMatch(Map<String, dynamic> event) async {
    final id = event['matchId'];
    final status = event['status'];
    if (id is! String || (status != 'completed' && status != 'stopped')) return;
    final a = event['scoreA'] is num ? (event['scoreA'] as num).toInt() : teamAScore;
    final b = event['scoreB'] is num ? (event['scoreB'] as num).toInt() : teamBScore;
    final startMs = event['startedAt'] is num ? (event['startedAt'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final endMs = event['endedAt'] is num ? (event['endedAt'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final seeded = event['seededScoreA'] is num && (event['seededScoreA'] as num) >= 0;
    final rallies = event['rallies']?.toString() ?? '';
    final winner = status == 'completed' ? (a > b ? 'A' : 'B') : '';
    await DatabaseService.upsertMatch(Match(
      id: id,
      teamAName: gameState.teamAName,
      teamBName: gameState.teamBName,
      teamAScore: a,
      teamBScore: b,
      winner: winner,
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
      actionHistory: rallies.split('').where((x) => x == 'A' || x == 'B').toList(),
      durationSeconds: ((endMs - startMs) ~/ 1000).clamp(0, 1 << 31),
      status: status,
      durationEstimated: seeded,
      rallySequence: rallies,
    ));
  }

  void _announceScoreChange(int a, int b, String team) {
    // Music mode: nothing speaks over the track. Talking across a song that is
    // already playing is exactly what kills the mood, so the whole
    // announce-then-hype chain is skipped rather than merely quietened.
    if (_audio.isMusicMode) return;

    if (scoreAnnouncementsEnabled.value) {
      _scoreAnnouncer.announceScore(a, b, team);
    } else {
      // If score announcement is disabled, we must trigger hype manually
      // so the audio chain continues.
      _hypeController.playHype();
    }
  }

  void _loadTeamConfig() {
    try {
      _teamConfig = DatabaseService.getTeamConfig();
      _gameState.value = gameState.copyWith(
        teamAName: _teamConfig!.teamAName,
        teamBName: _teamConfig!.teamBName,
        startTime: DateTime.now(),
      );
    } catch (e) {}
  }

  Future<void> updateTeamConfig(TeamConfig newConfig) async {
    _teamConfig = newConfig;
    await DatabaseService.saveTeamConfig(newConfig);
    _gameState.value = gameState.copyWith(
      teamAName: newConfig.teamAName,
      teamBName: newConfig.teamBName,
    );
  }

  Future<void> _initializeForegroundService() async {
    try {
      await ForegroundService.initialize();
      await ForegroundService.start(
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
      );
    } catch (e) {}
  }

  Future<void> _initializeVoiceService() async {
    try {
      await _voiceService.initialize(
        onWakeWord: (wakeWord) => lastCommand.value = wakeWord,
      );
      _voiceService.commandStream.listen((command) {
        lastCommand.value = command;
        _handleVoiceCommand(command);
      });
      _voiceService.listeningStream.listen((listening) {
        isVoiceActive.value = listening;
      });
    } catch (e) {}
  }

  void _handleVoiceCommand(String command) {
    final upperCommand = command.toUpperCase();
    if (isGameEnded.value) {
      if (upperCommand.contains('A') || upperCommand.contains('B')) {
        startNewGame();
        return;
      }
    }
    if (isCooldownActive.value) return;
    if (upperCommand.contains('UNDO')) {
      undo();
      return;
    }
    if (upperCommand.contains('A')) {
      incrementTeamA(fromVoice: true);
    } else if (upperCommand.contains('B')) {
      incrementTeamB(fromVoice: true);
    } else if (upperCommand.contains('RESET')) {
      resetGame();
    }
  }

  // Bound history to last 50 entries — list copy on every score otherwise grows O(n).
  List<String> _appendHistory(String entry) {
    const int maxHistory = 50;
    final h = gameState.history;
    if (h.length < maxHistory) return [...h, entry];
    return [...h.sublist(h.length - maxHistory + 1), entry];
  }

  void _pushStateToStack() {
    final currentStack = List<GameState>.from(gameState.stateStack);
    final snapshot = gameState.copyWith(stateStack: []);
    currentStack.add(snapshot);
    if (currentStack.length > 20) currentStack.removeAt(0);
    _gameState.value = gameState.copyWith(stateStack: currentStack);
  }

  void incrementTeamA({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: _appendHistory('${gameState.teamAName} scored'),
    );
    // Applied here at once and sent to the band as a command. The band's
    // resulting state overrides this when it arrives, so a lost command
    // snaps back instead of drifting — and if band->phone is the broken
    // direction, the phone board still moves.
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('point_A');
    }

    if (hapticFeedbackEnabled.value) {
      HapticFeedback.lightImpact();
    }

    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (!gameState.hasWinner) {
      _announceScoreChange(gameState.teamAScore, gameState.teamBScore, 'A');
    }
    if (fromVoice) _startCooldown();
    // ForegroundService.updateScores(teamAScore: gameState.teamAScore, teamBScore: gameState.teamBScore);
    _checkGameEnd();
  }

  void incrementTeamB({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: _appendHistory('${gameState.teamBName} scored'),
    );
    // Applied here at once and sent to the band as a command. The band's
    // resulting state overrides this when it arrives, so a lost command
    // snaps back instead of drifting — and if band->phone is the broken
    // direction, the phone board still moves.
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('point_B');
    }

    if (hapticFeedbackEnabled.value) {
      HapticFeedback.lightImpact();
    }

    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (!gameState.hasWinner) {
      _announceScoreChange(gameState.teamAScore, gameState.teamBScore, 'B');
    }
    if (fromVoice) _startCooldown();
    // ForegroundService.updateScores(teamAScore: gameState.teamAScore, teamBScore: gameState.teamBScore);
    _checkGameEnd();
  }

  void _checkTensionMusic() {
    final threshold = _musicService.tensionThreshold.value;
    if (gameState.teamAScore >= threshold &&
        gameState.teamBScore >= threshold &&
        !_musicService.isPlaying.value) {
      _musicService.playTensionMusic();
    }
  }

  /// With the band live, -1 is only allowed as an undo of that team's last
  /// rally — anything else would break the band's rally log.
  bool _bandMinus(String team) {
    if (!_bandLive) return false;
    if (_lastBandRallies.isNotEmpty &&
        _lastBandRallies[_lastBandRallies.length - 1] == team) {
      undo();
    } else {
      print('⌚ [Controller] -1 $team refused: last rally is not $team');
      if (hapticFeedbackEnabled.value) HapticFeedback.heavyImpact();
    }
    return true;
  }

  void decrementTeamA() {
    if (_bandMinus('A')) return;
    if (gameState.teamAScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamAScore: gameState.teamAScore - 1);
    }
  }

  void decrementTeamB() {
    if (_bandMinus('B')) return;
    if (gameState.teamBScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamBScore: gameState.teamBScore - 1);
    }
  }

  void undo() {
    if (!_isSyncingFromWatch) _watchService.sendScoreCommand('undo');
    if (!gameState.canUndo) return;
    final stack = List<GameState>.from(gameState.stateStack);
    final previousState = stack.removeLast();
    _gameState.value = previousState.copyWith(stateStack: stack);
    _hypeController.handleUndo();
    // Undo is almost always an immediate misclick correction — stay silent
    // instead of announcing "undo, X Y" (see matching comment above).
    _hypeController.playHype();
  }

  void _checkGameEnd({bool fromBand = false}) {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;
      // With the band live, the band's own record (pushed with an ack) is
      // the one that gets saved; saving here too would duplicate it.
      if (!fromBand && !_bandLive) _saveMatchToDatabase();
      _musicService.stopMusic(fadeOut: true);
      
      if (scoreAnnouncementsEnabled.value) {
        _scoreAnnouncer.announceWinner(gameState.winnerName, gameState.teamAScore, gameState.teamBScore);
      } else {
        _hypeController.playHype();
      }
      
      _watchService.sendWinnerUpdate(gameState.winner, gameState.teamAScore, gameState.teamBScore);
      _autoResetTimer?.cancel();
      // Never auto-reset while the band is live: it would start a new match
      // on the band before the user had a chance to undo the winning point.
      if (!_bandLive) {
        _autoResetTimer = Timer(Duration(seconds: autoResetDelay.value), () {
          if (isGameEnded.value) resetGame();
        });
      }
    }
  }

  Future<void> _saveMatchToDatabase() async {
    try {
      final endTime = DateTime.now();
      final startTime = gameState.startTime ?? endTime;
      final match = Match(
        id: _uuid.v4(),
        teamAName: gameState.teamAName,
        teamBName: gameState.teamBName,
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
        winner: gameState.winner,
        startTime: startTime,
        endTime: endTime,
        actionHistory: gameState.history,
        durationSeconds: endTime.difference(startTime).inSeconds,
      );
      await DatabaseService.saveMatch(match);
    } catch (e) {}
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    isCooldownActive.value = true;
    cooldownProgress.value = 1.0;
    const updateIntervalMs = 50;
    final durationMs = (cooldownDuration.value * 1000).toInt();
    final steps = durationMs ~/ updateIntervalMs;
    var currentStep = 0;
    _cooldownTimer = Timer.periodic(
      const Duration(milliseconds: updateIntervalMs),
      (timer) {
        currentStep++;
        cooldownProgress.value = 1.0 - (currentStep / steps);
        if (currentStep >= steps) {
          timer.cancel();
          isCooldownActive.value = false;
          cooldownProgress.value = 0.0;
        }
      },
    );
  }

  void resetGame() {
    final oldState = gameState;
    final teamAName = oldState.teamAName;
    final teamBName = oldState.teamBName;
    
    final newStack = List<GameState>.from(oldState.stateStack);
    newStack.add(oldState.copyWith(stateStack: []));
    if (newStack.length > 20) newStack.removeAt(0);

    _gameState.value = GameState(
      teamAName: teamAName,
      teamBName: teamBName,
      startTime: DateTime.now(),
      stateStack: newStack,
    );
    
    lastCommand.value = '';
    isGameEnded.value = false;
    _cooldownTimer?.cancel();
    _autoResetTimer?.cancel();
    isCooldownActive.value = false;
    cooldownProgress.value = 0.0;
    _hypeController.resetState();
    _musicService.stopMusic(fadeOut: true);
    _hypeController.playStartOfMatchHype();
    // ForegroundService.updateScores(teamAScore: 0, teamBScore: 0);
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('new_match');
    }
  }

  void startNewGame() => resetGame();

  Future<void> changeLanguage(String languageCode) async {
    await _ttsService.setLanguage(languageCode);
  }

  @override
  void onClose() {
    _cooldownTimer?.cancel();
    _autoResetTimer?.cancel();
    _watchConnectionPoll?.cancel();
    _watchCommandSubscription?.cancel();
    // _voiceService.dispose(); // DISABLED: Picovoice
    _ttsService.dispose();
    _watchService.dispose();
    // ForegroundService.stop(); // DISABLED: foreground notification
    super.onClose();
  }
}
