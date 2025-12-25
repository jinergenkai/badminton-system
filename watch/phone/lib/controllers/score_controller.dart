import 'package:get/get.dart';
import '../models/game_state.dart';
import '../services/voice_service.dart';

class ScoreController extends GetxController {
  final VoiceService _voiceService = VoiceService();

  final Rx<GameState> _gameState = GameState().obs;
  final RxString lastCommand = ''.obs;
  final RxBool isVoiceActive = false.obs;

  // Expose the observable for Obx to track
  Rx<GameState> get gameStateObservable => _gameState;

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

    if (upperCommand.contains('A') ||
        upperCommand.contains('ONE') ||
        upperCommand == '1') {
      incrementTeamA();
    } else if (upperCommand.contains('B') ||
        upperCommand.contains('TWO') ||
        upperCommand == '2') {
      incrementTeamB();
    } else if (upperCommand.contains('RESET')) {
      resetGame();
    }
  }

  void incrementTeamA() {
    if (!gameState.isGameActive) return;

    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: [...gameState.history, 'Team A scored'],
    );

    _checkGameEnd();
  }

  void incrementTeamB() {
    if (!gameState.isGameActive) return;

    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: [...gameState.history, 'Team B scored'],
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
      Get.snackbar(
        'Game Over! 🏸',
        '${gameState.winner} Wins!',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
    }
  }

  void resetGame() {
    _gameState.value = GameState();
    lastCommand.value = '';
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

  @override
  void onClose() {
    _voiceService.dispose();
    super.onClose();
  }
}
