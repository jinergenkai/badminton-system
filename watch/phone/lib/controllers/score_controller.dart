import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/match.dart';
import '../models/team_config.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../services/foreground_service.dart';
import '../services/database_service.dart';
import '../services/watch_connectivity_service.dart';
import '../widgets/win_dialog.dart';

class ScoreController extends GetxController {
  final VoiceService _voiceService = VoiceService();
  final TtsService _ttsService = TtsService();
  final WatchConnectivityService _watchService = WatchConnectivityService();
  final Uuid _uuid = const Uuid();

  final Rx<GameState> _gameState = GameState().obs;
  final RxString lastCommand = ''.obs;
  final RxBool isVoiceActive = false.obs;
  final RxBool isGameEnded = false.obs;
  final RxBool isWatchConnected = false.obs;

  // Cooldown to prevent rapid scoring
  final RxBool isCooldownActive = false.obs;
  final RxDouble cooldownProgress = 0.0.obs;
  final int cooldownDurationMs = 1000;
  Timer? _cooldownTimer;

  // Team configuration
  TeamConfig? _teamConfig;

  // Watch command subscription
  StreamSubscription? _watchCommandSubscription;

  // Expose the observable for Obx to track
  Rx<GameState> get gameStateObservable => _gameState;

  // Expose services for settings
  TtsService get ttsService => _ttsService;
  WatchConnectivityService get watchService => _watchService;

  // Convenience getters for direct access (non-reactive)
  GameState get gameState => _gameState.value;
  int get teamAScore => gameState.teamAScore;
  int get teamBScore => gameState.teamBScore;
  bool get isGameActive => gameState.isGameActive;
  String get winner => gameState.winner;

  @override
  void onInit() {
    super.onInit();
    _loadTeamConfig();
    _initializeVoiceService();
    _ttsService.initialize();
    _initializeForegroundService();
    _initializeWatchSync();
  }

  /// Initialize watch connectivity and auto-sync
  Future<void> _initializeWatchSync() async {
    try {
      await _watchService.initialize();

      // Auto-send updates when game state changes
      ever<GameState>(_gameState, (gameState) {
        _watchService.sendScoreUpdate(gameState);
      });

      // Listen for commands from watch
      _watchCommandSubscription = _watchService.watchCommandStream.listen((event) {
        _handleWatchCommand(event);
      });

      // Periodic connection check
      Timer.periodic(const Duration(seconds: 5), (timer) async {
        isWatchConnected.value = await _watchService.isWatchConnected();
      });

      print('⌚ [Controller] Watch sync initialized');
    } catch (e) {
      print('⌚ [Controller] Watch sync initialization error: $e');
      // Not critical if watch isn't available
    }
  }

  void _handleWatchCommand(Map<String, dynamic> event) {
    if (event['type'] == 'command') {
      final command = event['data'] as String;
      print('⌚ [Controller] Handling watch command: $command');
      
      if (!gameState.isGameActive && command != 'undo') {
        print('⌚ [Controller] Ignored $command: Game is PAUSED');
      }

      switch (command) {
        case 'team1_add':
          incrementTeamA();
          break;
        case 'team1_sub':
          decrementTeamA();
          break;
        case 'team2_add':
          incrementTeamB();
          break;
        case 'team2_sub':
          decrementTeamB();
          break;
        case 'undo':
          undo();
          break;
        default:
          print('⌚ [Controller] Unknown watch command: $command');
      }
    }
  }

  /// Load team configuration from database
  void _loadTeamConfig() {
    try {
      _teamConfig = DatabaseService.getTeamConfig();
      _gameState.value = gameState.copyWith(
        teamAName: _teamConfig!.teamAName,
        teamBName: _teamConfig!.teamBName,
        startTime: DateTime.now(),
      );
      print('📋 [Controller] Team config loaded: ${_teamConfig!.teamAName} vs ${_teamConfig!.teamBName}');
    } catch (e) {
      print('❌ [Controller] Error loading team config: $e');
    }
  }

  /// Update team configuration
  Future<void> updateTeamConfig(TeamConfig newConfig) async {
    _teamConfig = newConfig;
    await DatabaseService.saveTeamConfig(newConfig);
    _gameState.value = gameState.copyWith(
      teamAName: newConfig.teamAName,
      teamBName: newConfig.teamBName,
    );
    print('💾 [Controller] Team config updated');
  }

  Future<void> _initializeForegroundService() async {
    try {
      await ForegroundService.initialize();
      await ForegroundService.start(
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
      );
      print('🔔 [Controller] Foreground service started');
    } catch (e) {
      print('🔔 [Controller] Error starting foreground service: $e');
    }
  }

  Future<void> _initializeVoiceService() async {
    try {
      await _voiceService.initialize(
        onWakeWord: (wakeWord) {
          lastCommand.value = wakeWord;
        },
      );

      // Listen to voice commands
      _voiceService.commandStream.listen((command) {
        lastCommand.value = command;
        _handleVoiceCommand(command);
      });

      // Listen to voice active state
      _voiceService.listeningStream.listen((listening) {
        isVoiceActive.value = listening;
      });
    } catch (e) {
      // Error initializing voice service
    }
  }

  void _handleVoiceCommand(String command) {
    final upperCommand = command.toUpperCase();

    // If game has ended, any A or B command starts a new game
    if (isGameEnded.value) {
      if (upperCommand.contains('A') ||
          upperCommand.contains('B') ||
          upperCommand.contains('ONE') ||
          upperCommand.contains('TWO') ||
          upperCommand == '1' ||
          upperCommand == '2') {
        startNewGameFromVoice();
        return;
      }
    }

    // Block scoring during cooldown
    if (isCooldownActive.value) {
      print('⏳ [Score] Cooldown active - ignoring command: $command');
      return;
    }

    // Check for UNDO command
    if (upperCommand.contains('UNDO') || upperCommand.contains('BACK')) {
      undo();
      return;
    }

    // Normal gameplay
    if (upperCommand.contains('A') ||
        upperCommand.contains('ONE') ||
        upperCommand == '1') {
      incrementTeamA(fromVoice: true);
    } else if (upperCommand.contains('B') ||
        upperCommand.contains('TWO') ||
        upperCommand == '2') {
      incrementTeamB(fromVoice: true);
    } else if (upperCommand.contains('RESET')) {
      resetGame();
    }
  }

  /// Push current state to stack (for undo functionality)
  void _pushStateToStack() {
    const maxStackSize = 10;
    final currentStack = List<GameState>.from(gameState.stateStack);

    // Create a snapshot of current state (without the stack itself to avoid recursion)
    final snapshot = gameState.copyWith(stateStack: []);
    currentStack.add(snapshot);

    // Keep only last maxStackSize states
    if (currentStack.length > maxStackSize) {
      currentStack.removeAt(0);
    }

    _gameState.value = gameState.copyWith(stateStack: currentStack);
  }

  void incrementTeamA({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;

    // Push current state to stack for undo
    _pushStateToStack();

    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: [...gameState.history, '${gameState.teamAName} scored'],
    );

    // Đọc điểm nếu ghi điểm bằng voice
    if (fromVoice) {
      _ttsService.announceScore(
        gameState.teamAScore,
        gameState.teamBScore,
        'A',
      );
      // Start cooldown after voice scoring
      _startCooldown();
    }

    // Update foreground notification
    ForegroundService.updateScores(
      teamAScore: gameState.teamAScore,
      teamBScore: gameState.teamBScore,
    );

    _checkGameEnd();
  }

  void incrementTeamB({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;

    // Push current state to stack for undo
    _pushStateToStack();

    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: [...gameState.history, '${gameState.teamBName} scored'],
    );

    // Đọc điểm nếu ghi điểm bằng voice
    if (fromVoice) {
      _ttsService.announceScore(
        gameState.teamAScore,
        gameState.teamBScore,
        'B',
      );
      // Start cooldown after voice scoring
      _startCooldown();
    }

    // Update foreground notification
    ForegroundService.updateScores(
      teamAScore: gameState.teamAScore,
      teamBScore: gameState.teamBScore,
    );

    _checkGameEnd();
  }

  void decrementTeamA() {
    if (gameState.teamAScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(
        teamAScore: gameState.teamAScore - 1,
        history: [...gameState.history, '${gameState.teamAName} -1'],
      );
    }
  }

  void decrementTeamB() {
    if (gameState.teamBScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(
        teamBScore: gameState.teamBScore - 1,
        history: [...gameState.history, '${gameState.teamBName} -1'],
      );
    }
  }

  /// Undo last action
  void undo() {
    if (!gameState.canUndo) {
      print('⚠️ [Undo] No actions to undo');
      return;
    }

    final stack = List<GameState>.from(gameState.stateStack);
    final previousState = stack.removeLast();

    // Detect which team's point is being undone
    final undoneTeam = gameState.teamAScore > previousState.teamAScore ? 'A' : 'B';

    _gameState.value = previousState.copyWith(stateStack: stack);

    _ttsService.announceUndo(
      previousState.teamAScore,
      previousState.teamBScore,
      undoneTeam,
    );

    print('↩️ [Undo] Restored to: ${previousState.teamAScore}-${previousState.teamBScore}');
  }

  void _checkGameEnd() {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;

      // Save match to database
      _saveMatchToDatabase();

      // Đọc người thắng kèm tỉ số
      _ttsService.announceWinner(
        gameState.winner,
        gameState.teamAScore,
        gameState.teamBScore,
      );

      // Notify watch of winner
      _watchService.sendWinnerUpdate(
        gameState.winner,
        gameState.teamAScore,
        gameState.teamBScore,
      );

      // Show win dialog
      _showWinDialog();
    }
  }

  /// Save completed match to database
  Future<void> _saveMatchToDatabase() async {
    try {
      final endTime = DateTime.now();
      final startTime = gameState.startTime ?? endTime;
      final duration = endTime.difference(startTime);

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
        durationSeconds: duration.inSeconds,
      );

      await DatabaseService.saveMatch(match);
      print('💾 [Controller] Match saved: ${match.teamAName} ${match.teamAScore}-${match.teamBScore} ${match.teamBName}');
    } catch (e) {
      print('❌ [Controller] Error saving match: $e');
    }
  }

  void _showWinDialog() {
    Get.dialog(
      WinDialog(
        winner: gameState.winner,
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
        teamAName: gameState.teamAName,
        teamBName: gameState.teamBName,
        onNewGame: startNewGame,
      ),
      barrierDismissible: false,
    );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    isCooldownActive.value = true;
    cooldownProgress.value = 1.0;

    print('⏳ [Score] Starting ${cooldownDurationMs}ms cooldown');

    const updateIntervalMs =
        50; // Update progress every 50ms for smooth animation
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
          print('✅ [Score] Cooldown finished');
        }
      },
    );
  }

  void resetGame() {
    // Preserve team names when resetting
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
    isCooldownActive.value = false;
    cooldownProgress.value = 0.0;

    // Update foreground notification
    ForegroundService.updateScores(teamAScore: 0, teamBScore: 0);

    // Notify watch of reset
    _watchService.sendGameReset();
  }

  void startNewGame() {
    Get.back(); // Close dialog
    resetGame();
  }

  void startNewGameFromVoice() {
    Get.back(); // Close dialog
    resetGame();

    // Announce new game start
    _ttsService.announceNewBattle();
  }

  void pauseGame() {
    _gameState.value = gameState.copyWith(isGameActive: false);
  }

  void resumeGame() {
    if (!gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: true);
    }
  }

  Future<void> startListening() async {
    await _voiceService.start();
  }

  Future<void> stopListening() async {
    await _voiceService.stop();
  }

  void simulateVoiceCommand(String command) {
    _voiceService.manualCommand(command);
  }

  Future<void> changeLanguage(String languageCode) async {
    await _ttsService.setLanguage(languageCode);
    Get.snackbar(
      '🌍 Language Changed',
      'Voice announcements in ${TtsService.supportedLanguages[languageCode]}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  void testTts() {
    _ttsService.testSpeech();
  }

  @override
  void onClose() {
    _cooldownTimer?.cancel();
    _watchCommandSubscription?.cancel();
    _voiceService.dispose();
    _ttsService.dispose();
    _watchService.dispose();
    ForegroundService.stop();
    super.onClose();
  }
}
