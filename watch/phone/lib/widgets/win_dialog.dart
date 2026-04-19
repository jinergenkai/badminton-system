import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:confetti/confetti.dart';

class WinDialog extends StatefulWidget {
  final String winner;
  final int teamAScore;
  final int teamBScore;
  final String teamAName;
  final String teamBName;
  final VoidCallback onNewGame;

  const WinDialog({
    super.key,
    required this.winner,
    required this.teamAScore,
    required this.teamBScore,
    required this.teamAName,
    required this.teamBName,
    required this.onNewGame,
  });

  @override
  State<WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends State<WinDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 5));
    // Trigger confetti and haptic feedback
    Future.delayed(const Duration(milliseconds: 300), () {
      _confettiController.play();
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTeamA = widget.winner == 'Team A' || widget.winner == widget.teamAName;
    final winnerScore = isTeamA ? widget.teamAScore : widget.teamBScore;
    final loserScore = isTeamA ? widget.teamBScore : widget.teamAScore;
    final winnerColor = isTeamA ? Colors.redAccent : Colors.blueAccent;

    return Stack(
      children: [
        // Confetti Layer
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              Colors.amber,
              Colors.redAccent,
              Colors.blueAccent,
              Colors.greenAccent,
              Colors.purpleAccent,
            ],
            createParticlePath: _drawStar,
            numberOfParticles: 50,
            gravity: 0.2,
            emissionFrequency: 0.05,
          ),
        ),

        // Dialog
        Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E1B4B),
                  const Color(0xFF0F172A),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: winnerColor.withOpacity(0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: winnerColor.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Trophy Icon with Glow
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .scale(begin: const Offset(1,1), end: const Offset(1.2, 1.2), duration: 2000.ms),
                    Icon(Icons.emoji_events_rounded, size: 90, color: Colors.amber[400])
                        .animate(onPlay: (c) => c.repeat())
                        .shimmer(duration: 3000.ms)
                        .shake(hz: 1, curve: Curves.easeInOut),
                  ],
                ),

                const SizedBox(height: 24),

                // Winner Text
                Text(
                  'VICTORY!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.6),
                    letterSpacing: 4,
                  ),
                ).animate().fadeIn().scale(begin: const Offset(0.5, 0.5)),

                const SizedBox(height: 8),

                Text(
                  widget.winner.toUpperCase(),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: winnerColor,
                    letterSpacing: 1,
                    shadows: [
                      Shadow(color: winnerColor.withOpacity(0.5), blurRadius: 15),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),

                const SizedBox(height: 32),

                // Score Display
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildScoreDigit(winnerScore, Colors.white, 54),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                      _buildScoreDigit(loserScore, Colors.white.withOpacity(0.5), 54),
                    ],
                  ),
                ).animate().fadeIn(delay: 600.ms).scale(begin: const Offset(0.8, 0.8)),

                const SizedBox(height: 40),

                // Actions
                Column(
                  children: [
                    Text(
                      'READY FOR ANOTHER ROUND?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.4),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Voice Hint
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic, color: Colors.greenAccent, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            'Say "Red Point" or "Blue Point" to start',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ).animate(onPlay: (c) => c.repeat())
                     .shimmer(duration: 2000.ms, delay: 1000.ms),
                    
                    const SizedBox(height: 24),

                    // Manual Start Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          widget.onNewGame();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'START NEW MATCH',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 900.ms).slideY(begin: 0.2, end: 0),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreDigit(int score, Color color, double size) {
    return Text(
      '$score',
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: color,
        fontFamily: 'Orbitron', // Using the sporty font
      ),
    );
  }

  Path _drawStar(Size size) {
    double degToRad(double deg) => deg * (pi / 180.0);

    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);

    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(halfWidth + externalRadius * cos(step),
          halfWidth + externalRadius * sin(step));
      path.lineTo(halfWidth + internalRadius * cos(step + halfDegreesPerStep),
          halfWidth + internalRadius * sin(step + halfDegreesPerStep));
    }
    path.close();
    return path;
  }
}
