import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WinDialog extends StatelessWidget {
  final String winner;
  final int teamAScore;
  final int teamBScore;
  final VoidCallback onNewGame;

  const WinDialog({
    super.key,
    required this.winner,
    required this.teamAScore,
    required this.teamBScore,
    required this.onNewGame,
  });

  @override
  Widget build(BuildContext context) {
    final isTeamA = winner == 'Team A';
    final winnerScore = isTeamA ? teamAScore : teamBScore;
    final loserScore = isTeamA ? teamBScore : teamAScore;
    final winnerColor = isTeamA ? Colors.blue : Colors.orange;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [winnerColor[700]!, winnerColor[900]!],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: winnerColor.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trophy Icon
            Icon(Icons.emoji_events, size: 80, color: Colors.amber[300])
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 5000.ms)
                .shake(hz: 2, curve: Curves.easeInOut),

            const SizedBox(height: 16),

            // Game Over Text
            const Text(
              'GAME OVER!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ).animate().fadeIn(duration: 600.ms).scale(),

            const SizedBox(height: 8),

            // Winner Text
            Text(
              winner == 'Team A' ? 'GAU GAU WINS!' : 'MEO MEO WINS!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.amber[300],
                letterSpacing: 1,
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3, end: 0),

            const SizedBox(height: 20),

            // Final Score
            Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$winnerScore',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '-',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$loserScore',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms)
                .scale(begin: const Offset(0.8, 0.8)),

            const SizedBox(height: 24),

            // Voice Instruction
            Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Start New Game',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Say "Red Point" or "Meow Meow"',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 3000.ms, delay: 1000.ms),

            const SizedBox(height: 20),

            // Manual Button
            ElevatedButton(
              onPressed: onNewGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: winnerColor[900],
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'NEW GAME',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.3, end: 0),
          ],
        ),
      ),
    );
  }
}
