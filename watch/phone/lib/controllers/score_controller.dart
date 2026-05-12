import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/match.dart';
import '../models/team_config.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../services/foreground_service.dart';
import '../services/database_service.dart';
import '../services/watch_connectivity_service.dart';
import '../services/music_service.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';

class ScoreController extends GetxController {
  final VoiceService _voiceService = VoiceService();
  final TtsService _ttsService = Get.put(TtsService());
  final WatchConnectivityService _watchService = Get.put(WatchConnectivityService());
  final HypeVoiceController _hypeController = Get.put(HypeVoiceController());
  final MusicService _musicService = Get.put(MusicService());
  final Uuid _uuid = const Uuid();

  final Rx<GameState> _gameState = GameState().obs;
  final RxString lastCommand = ''.obs;
  final RxBool isVoiceActive = false.obs;
  final RxBool isGameEnded = false.obs;
  final RxBool isWatchConnected = false.obs;

  final RxBool isCooldownActive = false.obs;
  final RxDouble cooldownProgress = 0.0.obs;
  final int cooldownDurationMs = 1000;
  Timer? _cooldownTimer;
  Timer? _autoResetTimer;
  Timer? _watchConnectionPoll;

  // Configurable delay before auto-starting next game after a win
  final RxInt autoResetDelay = 60.obs;

  TeamConfig? _teamConfig;
  StreamSubscription? _watchCommandSubscription;
  bool _isSyncingFromWatch = false;

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
    // _initializeForegroundService(); // DISABLED: foreground notification
    _initializeWatchSync();
    _setupAudioChain();
    _musicService.initialize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    autoResetDelay.value = prefs.getInt('auto_reset_delay') ?? 60;
  }

  Future<void> setAutoResetDelay(int seconds) async {
    autoResetDelay.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_reset_delay', seconds);
  }

  void _setupAudioChain() {
    // TTS done → hype voice (or TTS fallback for missing MP3)
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
        // Tension was paused by hype's AudioFocus — resume it
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

    print('⌚ [Controller] Command from watch: $action (Scores: $newScoreA-$newScoreB, silent=$silent)');

    // Handle sync requests
    if (action == 'request_sync' || action == 'sync') {
      _watchService.sendScoreUpdate(gameState, action: 'sync');
      return;
    }

    // Handle reset/next match
    if (action == 'reset' || action == 'next_match') {
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
        final String undoneTeam = oldA > newScoreA ? 'A' : 'B';

        final stack = List<GameState>.from(gameState.stateStack);
        if (stack.isNotEmpty) stack.removeLast(); // best-effort stack trim

        _gameState.value = gameState.copyWith(
          teamAScore: newScoreA,
          teamBScore: newScoreB,
          stateStack: stack,
        );
        _hypeController.handleUndo();
        _ttsService.announceUndo(newScoreA, newScoreB, undoneTeam);
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
    if (action == 'score_A' || action == 'score_B') {
      if (newScoreA >= 0 && newScoreB >= 0) {
        final int oldA = gameState.teamAScore;
        final int oldB = gameState.teamBScore;
        final String? manualHype = event['manualHype'];
        
        // Duplicate-message guard
        if (newScoreA == oldA && newScoreB == oldB && manualHype == null) return;

        // DEFENSIVE LOGIC: If watch sends a score that is lower than phone (and not a reset), 
        // it likely means the watch app just restarted and hasn't synced yet.
        // We catch this BEFORE the 'hasWinner' reset check to avoid accidental match resets.
        if (!isResetFromWatch && (newScoreA < oldA || newScoreB < oldB)) {
          print('⌚ [Controller] Rejected lower scores from watch. Forcing sync back.');
          _watchService.sendScoreUpdate(gameState, action: 'sync');
          return;
        }

        // If game ended, any score button from watch resets the game (if it's not a stale update from restart)
        if (gameState.hasWinner) {
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

        _hypeController.processScoreUpdate(oldA, oldB, newScoreA, newScoreB, manualHype: manualHype);
        _ttsService.announceScore(newScoreA, newScoreB, action == 'score_A' ? 'A' : 'B');
        // _checkTensionMusic() moved to onPlaybackCompleted — avoids AudioFocus conflict
        // ForegroundService.updateScores(teamAScore: newScoreA, teamBScore: newScoreB);
        _checkGameEnd();
      }
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
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreUpdate(gameState, action: 'score_A');
    }
    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (!gameState.hasWinner) {
      _ttsService.announceScore(gameState.teamAScore, gameState.teamBScore, 'A');
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
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreUpdate(gameState, action: 'score_B');
    }
    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (!gameState.hasWinner) {
      _ttsService.announceScore(gameState.teamAScore, gameState.teamBScore, 'B');
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

  void decrementTeamA() {
    if (gameState.teamAScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamAScore: gameState.teamAScore - 1);
      if (!_isSyncingFromWatch) {
        _watchService.sendScoreUpdate(gameState, action: 'score_A');
      }
    }
  }

  void decrementTeamB() {
    if (gameState.teamBScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamBScore: gameState.teamBScore - 1);
      if (!_isSyncingFromWatch) {
        _watchService.sendScoreUpdate(gameState, action: 'score_B');
      }
    }
  }

  void undo() {
    if (!gameState.canUndo) return;
    final stack = List<GameState>.from(gameState.stateStack);
    final previousState = stack.removeLast();
    final undoneTeam = gameState.teamAScore > previousState.teamAScore ? 'A' : 'B';
    _gameState.value = previousState.copyWith(stateStack: stack);
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreUpdate(gameState, action: 'undo');
    }
    _hypeController.handleUndo();
    _ttsService.announceUndo(previousState.teamAScore, previousState.teamBScore, undoneTeam);
  }

  void _checkGameEnd() {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;
      _saveMatchToDatabase();
      _musicService.stopMusic(fadeOut: true);
      _ttsService.announceWinner(gameState.winnerName, gameState.teamAScore, gameState.teamBScore);
      _watchService.sendWinnerUpdate(gameState.winner, gameState.teamAScore, gameState.teamBScore);
      _autoResetTimer?.cancel();
      _autoResetTimer = Timer(Duration(seconds: autoResetDelay.value), () {
        if (isGameEnded.value) resetGame();
      });
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
    final steps = cooldownDurationMs ~/ updateIntervalMs;
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
      _watchService.sendScoreUpdate(gameState, action: 'reset');
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
