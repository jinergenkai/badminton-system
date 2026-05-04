import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:wear/wear.dart';
import '../../controllers/score_controller.dart';
import '../../services/watch_connectivity_service.dart';
import 'package:google_fonts/google_fonts.dart';

/// WearOS optimized score screen
class WatchScoreScreen extends StatelessWidget {
  const WatchScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScoreController controller = Get.put(ScoreController());
    final WatchConnectivityService watchService = WatchConnectivityService();

    return WatchShape(
      builder: (context, shape, child) {
        return AmbientMode(
          builder: (context, mode, child) {
            final isAmbient = mode == WearMode.ambient;

            return Scaffold(
              backgroundColor: isAmbient ? Colors.black : Colors.grey[900],
              body: Obx(() {
                final state = controller.gameStateObservable.value;

                return Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Main Score View
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Team A Column
                            Expanded(
                              child: _buildScoreColumn(
                                teamName: state.teamAName,
                                score: state.teamAScore,
                                color: isAmbient ? Colors.white : controller.teamAColor,
                                isAmbient: isAmbient,
                                onIncrement: () {
                                  HapticFeedback.mediumImpact();
                                  watchService.sendCommand('team1_add');
                                },
                                onDecrement: () {
                                  HapticFeedback.mediumImpact();
                                  watchService.sendCommand('team1_sub');
                                },
                              ),
                            ),

                            // Divider
                            Container(
                              width: 1,
                              height: 60,
                              color: isAmbient ? Colors.white24 : Colors.white10,
                            ),

                            // Team B Column
                            Expanded(
                              child: _buildScoreColumn(
                                teamName: state.teamBName,
                                score: state.teamBScore,
                                color: isAmbient ? Colors.white : controller.teamBColor,
                                isAmbient: isAmbient,
                                onIncrement: () {
                                  HapticFeedback.mediumImpact();
                                  watchService.sendCommand('team2_add');
                                },
                                onDecrement: () {
                                  HapticFeedback.mediumImpact();
                                  watchService.sendCommand('team2_sub');
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Undo Button (Only in non-ambient)
                      if (!isAmbient)
                        Positioned(
                          bottom: 10,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              watchService.sendCommand('undo');
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.undo,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),

                      // VS Label
                      if (!isAmbient)
                        Positioned(
                          top: 25,
                          child: Text(
                            'VS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white38,
                            ),
                          ),
                        ),

                      // Winner / Paused Overlay
                      if (state.hasWinner && !isAmbient)
                        _buildStatusOverlay(
                          text: state.winnerName,
                          icon: Icons.emoji_events,
                          color: state.winner == 'A' ? controller.teamAColor : controller.teamBColor,
                        ),
                      if (!state.isGameActive && !state.hasWinner && !isAmbient)
                        _buildStatusOverlay(
                          text: 'PAUSED',
                          icon: Icons.pause_circle,
                          color: Colors.red[700]!,
                        ),
                    ],
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }

  Widget _buildScoreColumn({
    required String teamName,
    required int score,
    required Color color,
    required bool isAmbient,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Plus Button
        if (!isAmbient)
          _buildActionButton(
            icon: Icons.add,
            onTap: onIncrement,
            color: color,
          ),

        const SizedBox(height: 4),

        // Score
        Text(
          '$score',
          style: GoogleFonts.orbitron(
            fontSize: isAmbient ? 42 : 36,
            fontWeight: FontWeight.w900,
            color: isAmbient ? Colors.white : color,
            height: 1,
          ),
        ),

        // Team Name
        Text(
          teamName.toUpperCase(),
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: isAmbient ? Colors.white70 : color.withOpacity(0.7),
            letterSpacing: 0.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 4),

        // Minus Button
        if (!isAmbient)
          _buildActionButton(
            icon: Icons.remove,
            onTap: onDecrement,
            color: color,
            isSmall: true,
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    bool isSmall = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isSmall ? 40 : 56,
        height: isSmall ? 32 : 56,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(isSmall ? 8 : 16),
        ),
        child: Icon(
          icon,
          color: color,
          size: isSmall ? 18 : 28,
        ),
      ),
    );
  }

  Widget _buildStatusOverlay({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Positioned(
      top: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
