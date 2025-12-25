import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/score_controller.dart';
import '../widgets/team_card.dart';
import '../widgets/voice_indicator.dart';
import '../services/tts_service.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScoreController controller = Get.put(ScoreController());

    return SafeArea(
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo[900]!,
                Colors.purple[900]!,
                Colors.pink[900]!,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                            '🏸 Badminton Score',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 800.ms)
                          .slideX(begin: -0.3, end: 0),
                      IconButton(
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white,
                            ),
                            iconSize: 26,
                            onPressed: () => _showGameMenu(context, controller),
                          )
                          .animate()
                          .fadeIn(duration: 800.ms)
                          .slideX(begin: 0.3, end: 0),
                    ],
                  ),
                ),
      
                const SizedBox(height: 8),
      
                // Score Display
                Expanded(
                  child: Obx(() {
                    // Access the observable to trigger updates
                    final state = controller.gameStateObservable.value;
      
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isPortrait =
                            constraints.maxWidth < constraints.maxHeight;
      
                        return Flex(
                          direction: isPortrait ? Axis.vertical : Axis.horizontal,
                          children: [
                            // Team A Card
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: TeamCard(
                                  teamName: 'TEAM A',
                                  score: state.teamAScore,
                                  primaryColor: Colors.blue[600]!,
                                  accentColor: Colors.cyan[400]!,
                                  onIncrement: controller.incrementTeamA,
                                  onDecrement: controller.decrementTeamA,
                                  isActive: state.isGameActive,
                                ),
                              ),
                            ),
      
                            // VS Divider
                            if (isPortrait)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withOpacity(0.5),
                                    letterSpacing: 2,
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withOpacity(0.5),
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
      
                            // Team B Card
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: TeamCard(
                                  teamName: 'TEAM B',
                                  score: state.teamBScore,
                                  primaryColor: Colors.orange[600]!,
                                  accentColor: Colors.amber[400]!,
                                  onIncrement: controller.incrementTeamB,
                                  onDecrement: controller.decrementTeamB,
                                  isActive: state.isGameActive,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  }),
                ),
      
                // Voice Indicator
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Obx(
                    () => VoiceIndicator(
                      isListening: controller.isVoiceActive.value,
                      lastCommand: controller.lastCommand.value,
                      onToggle: () async {
                        if (controller.isVoiceActive.value) {
                          await controller.stopListening();
                        } else {
                          await controller.startListening();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Test Button A
            FloatingActionButton(
              heroTag: 'testA',
              mini: true,
              backgroundColor: Colors.blue.shade400,
              elevation: 3,
              onPressed: () => controller.simulateVoiceCommand('A'),
              child: const Text(
                'A',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ).animate().fadeIn(delay: 500.ms),
            const SizedBox(height: 10),
            // Test Button B
            FloatingActionButton(
              heroTag: 'testB',
              mini: true,
              backgroundColor: Colors.orange.shade400,
              elevation: 3,
              onPressed: () => controller.simulateVoiceCommand('B'),
              child: const Text(
                'B',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ).animate().fadeIn(delay: 600.ms),
          ],
        ),
      ),
    );
  }

  void _showGameMenu(BuildContext context, ScoreController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo[800]!, Colors.purple[800]!],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Game Menu',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            _buildMenuButton(
              icon: Icons.refresh,
              label: 'Reset Game',
              color: Colors.blue,
              onTap: () {
                controller.resetGame();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            Obx(() {
              final state = controller.gameStateObservable.value;
              return _buildMenuButton(
                icon: state.isGameActive ? Icons.pause : Icons.play_arrow,
                label: state.isGameActive ? 'Pause Game' : 'Resume Game',
                color: Colors.orange,
                onTap: () {
                  if (state.isGameActive) {
                    controller.pauseGame();
                  } else {
                    controller.resumeGame();
                  }
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 12),
            _buildMenuButton(
              icon: Icons.language,
              label: 'Voice Language',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                _showLanguageSettings(context, controller);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSettings(BuildContext context, ScoreController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.green[800]!, Colors.teal[800]!],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.language, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  'Voice Language',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose language for score announcements',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ...TtsService.supportedLanguages.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildLanguageOption(
                  code: entry.key,
                  name: entry.value,
                  controller: controller,
                  context: context,
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String code,
    required String name,
    required ScoreController controller,
    required BuildContext context,
  }) {
    final isSelected = controller.ttsService.currentLanguage == code;

    return InkWell(
      onTap: () async {
        await controller.changeLanguage(code);
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.6)
                : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            if (isSelected)
              TextButton(
                onPressed: () => controller.testTts(),
                child: const Text(
                  'Test',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
