import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/score_controller.dart';
import '../widgets/team_card.dart';
import '../widgets/voice_indicator.dart';
import '../widgets/cooldown_bar.dart';
import '../services/tts_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScoreController controller = Get.put(ScoreController());

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF1E1B4B),
              const Color(0xFF312E81),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 1. Thin Cooldown Line (Top Overlay)
              Obx(() => CooldownBar(
                isActive: controller.isCooldownActive.value,
                progress: controller.cooldownProgress.value,
              )),

              // 2. Compact Top Bar
              _buildCompactTopBar(context, controller),

              // 3. Maximized Scoring Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Obx(() {
                    final state = controller.gameStateObservable.value;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isPortrait = constraints.maxWidth < constraints.maxHeight;

                        return Flex(
                          direction: isPortrait ? Axis.vertical : Axis.horizontal,
                          children: [
                            Expanded(
                              flex: 10,
                              child: TeamCard(
                                teamName: state.teamAName,
                                score: state.teamAScore,
                                primaryColor: Colors.redAccent,
                                accentColor: Colors.orangeAccent,
                                onIncrement: controller.incrementTeamA,
                                onDecrement: controller.decrementTeamA,
                                isActive: state.isGameActive,
                              ),
                            ),
                            
                            // Minimal Divider
                            if (isPortrait) 
                              const SizedBox(height: 4)
                            else 
                              const SizedBox(width: 4),
                              
                            Expanded(
                              flex: 10,
                              child: TeamCard(
                                teamName: state.teamBName,
                                score: state.teamBScore,
                                primaryColor: Colors.blueAccent,
                                accentColor: Colors.cyanAccent,
                                onIncrement: controller.incrementTeamB,
                                onDecrement: controller.decrementTeamB,
                                isActive: state.isGameActive,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  }),
                ),
              ),

              // 4. Ultra Compact Bottom Controls
              _buildUltraCompactBottomControls(controller),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTopBar(BuildContext context, ScoreController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_tennis, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text(
                'VOICE COUNTER PRO',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          
          Row(
            children: [
              _buildMinimalTopButton(
                icon: Icons.history,
                onPressed: () => Get.to(() => const HistoryScreen()),
              ),
              const SizedBox(width: 8),
              _buildMinimalTopButton(
                icon: Icons.settings_rounded,
                onPressed: () => Get.to(() => const SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalTopButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white60, size: 18),
      ),
    );
  }

  Widget _buildUltraCompactBottomControls(ScoreController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          // 1. Voice Toggle (Compact)
          Obx(() {
            final isListening = controller.isVoiceActive.value;
            return GestureDetector(
              onTap: () async {
                if (isListening) {
                  await controller.stopListening();
                } else {
                  await controller.startListening();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isListening ? Colors.greenAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isListening ? Colors.greenAccent.withOpacity(0.5) : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isListening ? Icons.mic : Icons.mic_none,
                      color: isListening ? Colors.greenAccent : Colors.white30,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isListening ? 'LISTENING' : 'VOICE OFF',
                      style: TextStyle(
                        color: isListening ? Colors.greenAccent : Colors.white30,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(width: 8),

          // 2. Language Quick Info
          Expanded(
            child: Obx(() {
              final isConnected = controller.isWatchConnected.value;
              final lang = controller.ttsService.currentLanguageRx.value;
              final langName = TtsService.supportedLanguages[lang] ?? 'English';
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.watch,
                        size: 12,
                        color: isConnected ? Colors.blueAccent : Colors.white10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConnected ? 'WATCH ON' : 'WATCH OFF',
                        style: TextStyle(
                          color: isConnected ? Colors.blueAccent : Colors.white10,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _showLanguageSettings(Get.context!, controller),
                    child: Text(
                      'TTS: ${langName.toUpperCase()}',
                      style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(width: 8),

          // 3. Quick Actions (Undo/Reset)
          Obx(() {
            final canUndo = controller.gameStateObservable.value.canUndo;
            return _buildMicroActionButton(
              icon: Icons.undo,
              color: Colors.orangeAccent,
              onTap: canUndo ? () => controller.undo() : null,
              isEnabled: canUndo,
            );
          }),
          
          const SizedBox(width: 8),
          
          _buildMicroActionButton(
            icon: Icons.refresh,
            color: Colors.redAccent,
            onTap: () => _confirmReset(controller),
            isEnabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMicroActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required bool isEnabled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isEnabled ? color.withOpacity(0.1) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? color.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          color: isEnabled ? color : Colors.white10,
          size: 20,
        ),
      ),
    );
  }

  void _confirmReset(ScoreController controller) {
    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        title: const Text('Reset Match?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              controller.resetGame();
              Get.back();
            },
            child: const Text('RESET'),
          ),
        ],
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
          color: const Color(0xFF1E1B4B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Voice Language', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ...TtsService.supportedLanguages.entries.map((entry) {
              return ListTile(
                title: Text(entry.value, style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  await controller.changeLanguage(entry.key);
                  Navigator.pop(context);
                },
                trailing: controller.ttsService.currentLanguage == entry.key 
                  ? const Icon(Icons.check, color: Colors.greenAccent) 
                  : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
