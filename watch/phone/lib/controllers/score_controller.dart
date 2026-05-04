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
  final TtsService _ttsService = TtsService();
  final WatchConnectivityService _watchService = WatchConnectivityService();
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

  // Configurable delay before auto-starting next game after a win
  final RxInt autoResetDelay = 30.obs;

  TeamConfig? _teamConfig;
  StreamSubscription? _watchCommandSubscription;

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
    _initializeVoiceService();
    _ttsService.initialize();
    _initializeForegroundService();
    _initializeWatchSync();
    _setupAudioChain();
    _musicService.initialize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    autoResetDelay.value = prefs.getInt('auto_reset_delay') ?? 30;
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

    // Hype done (or skipped) → win music if game ended
    _hypeController.onPlaybackCompleted = () {
      if (isGameEnded.value) {
        _musicService.playWinMusic();
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
      ever<GameState>(_gameState, (gameState) {
        _watchService.sendScoreUpdate(gameState);
      });
      _watchCommandSubscription = _watchService.watchCommandStream.listen((event) {
        _handleWatchCommand(event);
      });
      Timer.periodic(const Duration(seconds: 5), (timer) async {
        isWatchConnected.value = await _watchService.isWatchConnected();
      });
    } catch (e) {
      print('⌚ [Controller] Watch sync init error: $e');
    }
  }

  void _handleWatchCommand(Map<String, dynamic> event) {
    if (event['type'] == 'command') {
      final action = event['action'] as String;
      final int scoreA = event['scoreA'] ?? -1;
      final int scoreB = event['scoreB'] ?? -1;

      if (action == 'request_sync') {
        _watchService.sendScoreUpdate(gameState, action: 'sync');
        return;
      }

      if (gameState.hasWinner && (action == 'score_A' || action == 'score_B')) {
        resetGame();
        return;
      }

      if (scoreA != -1 && scoreB != -1) {
        _gameState.value = gameState.copyWith(
          teamAScore: scoreA,
          teamBScore: scoreB,
          history: [...gameState.history, 'Watch sync: $action'],
        );
        if (action == 'score_A') _ttsService.announceScore(scoreA, scoreB, 'A');
        if (action == 'score_B') _ttsService.announceScore(scoreA, scoreB, 'B');
        if (action == 'undo') _ttsService.announceUndo(scoreA, scoreB, 'None');
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

  void _pushStateToStack() {
    final currentStack = List<GameState>.from(gameState.stateStack);
    final snapshot = gameState.copyWith(stateStack: []);
    currentStack.add(snapshot);
    if (currentStack.length > 10) currentStack.removeAt(0);
    _gameState.value = gameState.copyWith(stateStack: currentStack);
  }

  void incrementTeamA({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: [...gameState.history, '${gameState.teamAName} scored'],
    );
    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    // Skip score announcement on winning point — _checkGameEnd handles it
    if (!gameState.hasWinner) {
      _ttsService.announceScore(gameState.teamAScore, gameState.teamBScore, 'A');
    }
    _checkTensionMusic();
    if (fromVoice) _startCooldown();
    ForegroundService.updateScores(teamAScore: gameState.teamAScore, teamBScore: gameState.teamBScore);
    _checkGameEnd();
  }

  void incrementTeamB({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: [...gameState.history, '${gameState.teamBName} scored'],
    );
    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    // Skip score announcement on winning point — _checkGameEnd handles it
    if (!gameState.hasWinner) {
      _ttsService.announceScore(gameState.teamAScore, gameState.teamBScore, 'B');
    }
    _checkTensionMusic();
    if (fromVoice) _startCooldown();
    ForegroundService.updateScores(teamAScore: gameState.teamAScore, teamBScore: gameState.teamBScore);
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
    }
  }

  void decrementTeamB() {
    if (gameState.teamBScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamBScore: gameState.teamBScore - 1);
    }
  }

  void undo() {
    if (!gameState.canUndo) return;
    final stack = List<GameState>.from(gameState.stateStack);
    final previousState = stack.removeLast();
    final undoneTeam = gameState.teamAScore > previousState.teamAScore ? 'A' : 'B';
    _gameState.value = previousState.copyWith(stateStack: stack);
    _hypeController.handleUndo();
    _ttsService.announceUndo(previousState.teamAScore, previousState.teamBScore, undoneTeam);
  }

  void _checkGameEnd() {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;
      _saveMatchToDatabase();
      // Stop tension music, then: TTS winner → hype (comeback_king etc.) → win music
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
    final teamAName = gameState.teamAName;
    final teamBName = gameState.teamBName;
    _gameState.value = GameState(
      teamAName: teamAName,
      teamBName: teamBName,
      startTime: DateTime.now(),
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
    ForegroundService.updateScores(teamAScore: 0, teamBScore: 0);
    _watchService.sendGameReset();
  }

  void startNewGame() => resetGame();

  Future<void> changeLanguage(String languageCode) async {
    await _ttsService.setLanguage(languageCode);
  }

  @override
  void onClose() {
    _cooldownTimer?.cancel();
    _autoResetTimer?.cancel();
    _watchCommandSubscription?.cancel();
    _voiceService.dispose();
    _ttsService.dispose();
    _watchService.dispose();
    ForegroundService.stop();
    super.onClose();
  }
}
