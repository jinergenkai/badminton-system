import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/score_controller.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';
import '../widgets/team_card.dart';
import '../widgets/kill_overlay.dart';
import '../widgets/cooldown_bar.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScoreController controller = Get.put(ScoreController());

    return Scaffold(
      body: Stack(
        children: [
          // MAIN APP UI
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Obx(() => CooldownBar(
                    isActive: controller.isCooldownActive.value,
                    progress: controller.cooldownProgress.value,
                  )),

                  _buildModernTopBar(context, controller),

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
                                    mascotAsset: 'assets/image/dog_smash.png',
                                  ),
                                ),
                                const SizedBox(width: 4, height: 4),
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
                                    mascotAsset: 'assets/image/cat_dropshot.png',
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      }),
                    ),
                  ),

                  _buildBottomControls(controller),
                ],
              ),
            ),
          ),

          // EPIC WIN OVERLAY
          Obx(() {
            if (controller.isGameEnded.value) {
              return _buildEpicWinOverlay(controller);
            }
            return const SizedBox.shrink();
          }),

          // KILL / HYPE OVERLAY (full screen, above everything)
          Obx(() {
            final hype = Get.find<HypeVoiceController>();
            final event = hype.displayEvent.value;
            if (event == null) return const SizedBox.shrink();
            final mascot = event.team == 'A'
                ? 'assets/image/dog_smash.png'
                : 'assets/image/cat_dropshot.png';
            return KillOverlay(key: ValueKey(event.voiceId), event: event, mascotAsset: mascot);
          }),
        ],
      ),
    );
  }

  Widget _buildEpicWinOverlay(ScoreController controller) {
    final winner = controller.gameState.winner;
    final isTeamA = winner == controller.gameState.teamAName;
    final winColor = isTeamA ? Colors.redAccent : Colors.blueAccent;
    final mascot = isTeamA ? 'assets/image/dog_smash.png' : 'assets/image/cat_dropshot.png';
    final delay = controller.autoResetDelay.value;

    return Container(
      color: Colors.black.withOpacity(0.92),
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mascot large celebratory image
          Image.asset(mascot, width: 160, height: 160, fit: BoxFit.contain)
              .animate()
              .scale(duration: 600.ms, curve: Curves.elasticOut)
              .then()
              .shake(duration: 400.ms, hz: 4),
          const SizedBox(height: 16),
          Text(
            'WINNER',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 8),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text(
            winner.toUpperCase(),
            style: TextStyle(
              color: winColor,
              fontSize: 80,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: winColor, blurRadius: 40)],
            ),
            textAlign: TextAlign.center,
          ).animate().scale(
              delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 40),
          Text(
            'Next match in ${delay}s...',
            style: const TextStyle(
                color: Colors.white24,
                fontSize: 16,
                fontStyle: FontStyle.italic),
          ).animate().fadeIn(delay: 1500.ms),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildModernTopBar(BuildContext context, ScoreController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Obx(() {
            final isConnected = controller.isWatchConnected.value;
            return GestureDetector(
              onTap: () => _showWatchSettings(context, controller),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.blueAccent : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isConnected ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 10)] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isConnected ? Icons.watch : Icons.watch_off, size: 20, color: isConnected ? Colors.white : Colors.white24),
                    const SizedBox(width: 10),
                    Text(
                      isConnected ? 'MI BAND 10 ONLINE' : 'BAND DISCONNECTED',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            );
          }),
          Row(
            children: [
              _buildTopIconButton(icon: Icons.history, onPressed: () => Get.to(() => const HistoryScreen())),
              const SizedBox(width: 12),
              _buildTopIconButton(icon: Icons.settings, onPressed: () => Get.to(() => const SettingsScreen())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopIconButton({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white70, size: 24),
      ),
    );
  }

  Widget _buildBottomControls(ScoreController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Voice status indicator (Static, no button needed)
          Obx(() {
            final isListening = controller.isVoiceActive.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isListening ? Colors.greenAccent.withOpacity(0.1) : Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isListening ? Colors.greenAccent.withOpacity(0.3) : Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(isListening ? Icons.mic : Icons.mic_none, color: isListening ? Colors.greenAccent : Colors.white24, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    isListening ? 'VOICE READY' : 'VOICE INACTIVE',
                    style: TextStyle(color: isListening ? Colors.greenAccent : Colors.white24, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            );
          }),

          const Spacer(),

          _buildCircleAction(icon: Icons.undo, color: Colors.orangeAccent, onTap: () => controller.undo(), isEnabled: true),
          const SizedBox(width: 16),
          _buildCircleAction(icon: Icons.refresh, color: Colors.redAccent, onTap: () => _confirmReset(controller), isEnabled: true),
        ],
      ),
    );
  }

  Widget _buildCircleAction({required IconData icon, required Color color, required VoidCallback onTap, required bool isEnabled}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  void _showWatchSettings(BuildContext context, ScoreController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(color: Color(0xFF1E1B4B), borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 32),
            const Text('Watch Connectivity', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            _settingsListTile(icon: Icons.bluetooth_searching, title: 'Reconnect Watch', color: Colors.blueAccent, onTap: () { Navigator.pop(context); controller.watchService.initialize(); }),
            const SizedBox(height: 16),
            _settingsListTile(icon: Icons.sync, title: 'Force Sync to Watch', color: Colors.greenAccent, onTap: () { Navigator.pop(context); controller.watchService.sendScoreUpdate(controller.gameState, action: 'manual_sync'); }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _settingsListTile({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tileColor: Colors.white.withOpacity(0.04),
    );
  }

  void _confirmReset(ScoreController controller) {
    Get.dialog(AlertDialog(
      backgroundColor: const Color(0xFF1E1B4B),
      title: const Text('Reset Match?', style: TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { controller.resetGame(); Get.back(); }, child: const Text('RESET')),
      ],
    ));
  }
}
