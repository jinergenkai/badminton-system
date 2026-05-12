import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:voice_counter/services/music_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../controllers/score_controller.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';
import '../widgets/team_card.dart';
import '../widgets/kill_overlay.dart';
import '../widgets/cooldown_bar.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  late final ScoreController controller;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    controller = Get.put(ScoreController());
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                                    teamId: 'A',
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
                                    teamId: 'B',
                                    teamName: state.teamBName,
                                    score: state.teamBScore,
                                    primaryColor: Colors.blueAccent,
                                    accentColor: Colors.cyanAccent,
                                    onIncrement: controller.incrementTeamB,
                                    onDecrement: controller.decrementTeamB,
                                    isActive: state.isGameActive,
                                    mascotAsset: 'assets/image/cat_dropshot.png',
                                  ),
                                ),                              ],
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
    final winnerName = controller.gameState.winnerName;
    final isTeamA = winner == 'A';
    final winColor = isTeamA ? Colors.redAccent : Colors.blueAccent;
    final mascot = isTeamA ? 'assets/image/dog_smash.png' : 'assets/image/cat_dropshot.png';
    final delay = controller.autoResetDelay.value;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        controller.resetGame();
      },
      child: Container(
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
              winnerName.toUpperCase(),
              style: TextStyle(
                color: winColor,
                fontSize: 60,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: winColor, blurRadius: 40)],
              ),
              textAlign: TextAlign.center,
            ).animate().scale(
                delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 40),

            const SizedBox(height: 24),

            Text(
              'Tap anywhere or wait ${delay}s to reset',
              style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 14,
                  fontStyle: FontStyle.italic),
            ).animate().fadeIn(delay: 1000.ms),
          ],
        ),
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
    final MusicService musicService = Get.find<MusicService>();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Music Controls Area
              Expanded(
                child: Obx(() {
                  final isPlaying = musicService.isPlaying.value;
                  final trackName = musicService.currentTrackName.value;
                  final isNonStop = musicService.isNonStop.value;
                  final playMode = musicService.playMode.value;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        // Play/Pause
                        _buildMusicAction(
                          icon: isPlaying ? Icons.pause : Icons.play_arrow,
                          onTap: () => isPlaying ? musicService.pause() : musicService.resume(),
                          color: isPlaying ? Colors.greenAccent : Colors.white70,
                        ),
                        
                        const SizedBox(width: 8),

                        // Track Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                trackName.isEmpty ? 'MUSIC STANDBY' : trackName.toUpperCase(),
                                style: TextStyle(
                                  color: trackName.isEmpty ? Colors.white24 : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => musicService.toggleNonStop(),
                                    child: Text(
                                      isNonStop ? 'NON-STOP ON' : 'SINGLE PLAY',
                                      style: TextStyle(
                                        color: isNonStop ? Colors.orangeAccent : Colors.white24,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      musicService.playMode.value = (playMode == 'random' ? 'sequential' : 'random');
                                      musicService.savePreferences();
                                    },
                                    child: Text(
                                      playMode.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Next Track
                        _buildMusicAction(
                          icon: Icons.skip_next,
                          onTap: () => musicService.next(),
                          color: Colors.white70,
                          isSmall: true,
                        ),
                      ],
                    ),
                  );
                }),
              ),

              const SizedBox(width: 16),

              // Action Buttons
              _buildCircleAction(icon: Icons.undo, color: Colors.orangeAccent, onTap: () => controller.undo(), isEnabled: true),
              const SizedBox(width: 12),
              _buildCircleAction(icon: Icons.refresh, color: Colors.redAccent, onTap: () => _confirmReset(controller), isEnabled: true),
            ],
          ),
          
          // Voice Status (Mini)
          const SizedBox(height: 8),
          Obx(() {
            final isListening = controller.isVoiceActive.value;
            if (!isListening) return const SizedBox.shrink();
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, color: Colors.greenAccent, size: 12),
                const SizedBox(width: 4),
                const Text('VOICE LISTENING', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMusicAction({required IconData icon, required VoidCallback onTap, required Color color, bool isSmall = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isSmall ? 6 : 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: isSmall ? 18 : 22),
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
