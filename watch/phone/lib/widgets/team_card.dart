import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class TeamCard extends StatelessWidget {
  final String teamName;
  final int score;
  final Color primaryColor;
  final Color accentColor;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool isActive;

  const TeamCard({
    super.key,
    required this.teamName,
    required this.score,
    required this.primaryColor,
    required this.accentColor,
    required this.onIncrement,
    required this.onDecrement,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final bool isTablet = width > 400 || height > 400;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primaryColor.withOpacity(0.4),
                accentColor.withOpacity(0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: -5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.white.withOpacity(0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // MAXIMIZED Main Score Area
                    _buildMaximizedScoreArea(width, height, isTablet),

                    // Tiny Minimal Controls
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildMicroControl(
                        icon: Icons.remove,
                        onTap: onDecrement,
                        size: isTablet ? 48 : 36,
                      ),
                    ),

                    Positioned(
                      top: 8,
                      right: 8,
                      child: _buildMicroControl(
                        icon: Icons.add,
                        onTap: onIncrement,
                        size: isTablet ? 48 : 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaximizedScoreArea(double width, double height, bool isTablet) {
    // Dynamically calculate massive font size based on available height
    double scoreFontSize = isTablet 
        ? (height * 0.75).clamp(150, 500) 
        : (height * 0.7).clamp(100, 250);

    // Bóp nhỏ font nếu điểm số có 2 chữ số (từ 10 trở lên) để không bị tràn viền
    if (score > 9) {
      scoreFontSize *= 0.8;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isActive) {
            HapticFeedback.heavyImpact();
            onIncrement();
          }
        },
        splashColor: primaryColor.withOpacity(0.2),
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Team Name (Top edge, small to save space)
              const Spacer(flex: 1),
              Text(
                teamName.toUpperCase(),
                style: TextStyle(
                  fontSize: isTablet ? 24 : 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.5),
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(),

              // GIANT SCORE
              Text(
                '$score',
                key: ValueKey(score),
                style: GoogleFonts.orbitron(
                  fontSize: scoreFontSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                  shadows: [
                    Shadow(color: primaryColor, blurRadius: 30),
                    Shadow(color: Colors.black, offset: const Offset(0, 5), blurRadius: 20),
                  ],
                ),
              )
              .animate(key: ValueKey(score))
              .scale(
                duration: 200.ms,
                curve: Curves.easeOutBack,
                begin: const Offset(0.9, 0.9),
                end: const Offset(1, 1),
              )
              .shimmer(duration: 1500.ms, color: Colors.white.withOpacity(0.3)),
              
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMicroControl({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: Colors.white30, size: size * 0.6),
      ),
    );
  }
}
