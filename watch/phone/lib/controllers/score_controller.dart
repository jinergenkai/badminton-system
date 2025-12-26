import 'dart:async';
import 'package:get/get.dart';
import '../models/game_state.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../services/foreground_service.dart';
import '../widgets/win_dialog.dart';

class ScoreController extends GetxController {
  final VoiceService _voiceService = VoiceService();
  final TtsService _ttsService = TtsService();

  final Rx<GameState> _gameState = GameState().obs;
  final RxString lastCommand = ''.obs;
  final RxBool isVoiceActive = false.obs;
  final RxBool isGameEnded = false.obs;

  // Cooldown to prevent rapid scoring
  final RxBool isCooldownActive = false.obs;
  final RxDouble cooldownProgress = 0.0.obs;
  final int cooldownDurationMs = 5000;
  Timer? _cooldownTimer;

  // Expose the observable for Obx to track
  Rx<GameState> get gameStateObservable => _gameState;

  // Expose TTS service for settings
  TtsService get ttsService => _ttsService;

  // Convenience getters for direct access (non-reactive)
  GameState get gameState => _gameState.value;
  int get teamAScore => gameState.teamAScore;
  int get teamBScore => gameState.teamBScore;
  bool get isGameActive => gameState.isGameActive;
  String get winner => gameState.winner;

  @override
  void onInit() {
    super.onInit();
    _initializeVoiceService();
    _ttsService.initialize();
    _initializeForegroundService();
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

  void incrementTeamA({bool fromVoice = false}) {
    if (!gameState.isGameActive) return;

    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: [...gameState.history, 'Team A scored'],
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

    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: [...gameState.history, 'Team B scored'],
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
      _gameState.value = gameState.copyWith(
        teamAScore: gameState.teamAScore - 1,
        history: [...gameState.history, 'Team A -1'],
      );
    }
  }

  void decrementTeamB() {
    if (gameState.teamBScore > 0) {
      _gameState.value = gameState.copyWith(
        teamBScore: gameState.teamBScore - 1,
        history: [...gameState.history, 'Team B -1'],
      );
    }
  }

  void _checkGameEnd() {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;

      // Đọc người thắng kèm tỉ số
      _ttsService.announceWinner(
        gameState.winner,
        gameState.teamAScore,
        gameState.teamBScore,
      );

      // Show win dialog
      _showWinDialog();
    }
  }

  void _showWinDialog() {
    Get.dialog(
      WinDialog(
        winner: gameState.winner,
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
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
    _gameState.value = GameState();
    lastCommand.value = '';
    isGameEnded.value = false;
    _cooldownTimer?.cancel();
    isCooldownActive.value = false;
    cooldownProgress.value = 0.0;

    // Update foreground notification
    ForegroundService.updateScores(teamAScore: 0, teamBScore: 0);
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
    _voiceService.dispose();
    _ttsService.dispose();
    ForegroundService.stop();
    super.onClose();
  }
}
