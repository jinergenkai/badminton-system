import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wear/wear.dart';
import '../../controllers/score_controller.dart';
import 'package:google_fonts/google_fonts.dart';

/// WearOS optimized score screen
class WatchScoreScreen extends StatelessWidget {
  const WatchScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScoreController controller = Get.put(ScoreController());

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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Sport Icon
                      if (!isAmbient)
                        Icon(
                          Icons.sports_tennis,
                          color: Colors.white70,
                          size: 24,
                        ),

                      const SizedBox(height: 8),

                      // Team A Score
                      _buildTeamScore(
                        teamName: state.teamAName,
                        score: state.teamAScore,
                        color: isAmbient ? Colors.white : Colors.blue[300]!,
                        isAmbient: isAmbient,
                      ),

                      const SizedBox(height: 4),

                      // VS Divider
                      Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isAmbient ? Colors.white54 : Colors.white70,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Team B Score
                      _buildTeamScore(
                        teamName: state.teamBName,
                        score: state.teamBScore,
                        color: isAmbient ? Colors.white : Colors.orange[300]!,
                        isAmbient: isAmbient,
                      ),

                      const SizedBox(height: 12),

                      // Winner Indicator
                      if (state.hasWinner && !isAmbient)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emoji_events,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                state.winner,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Game Paused Indicator
                      if (!state.isGameActive && !state.hasWinner && !isAmbient)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.pause_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'PAUSED',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildTeamScore({
    required String teamName,
    required int score,
    required Color color,
    required bool isAmbient,
  }) {
    return Column(
      children: [
        // Team Name
        Text(
          teamName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isAmbient ? Colors.white70 : color,
            letterSpacing: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 2),

        // Score
        Text(
          '$score',
          style: GoogleFonts.orbitron(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: isAmbient ? Colors.white : color,
            height: 1,
          ),
        ),
      ],
    );
  }
}
