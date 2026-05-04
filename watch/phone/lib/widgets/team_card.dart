import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';

class TeamCard extends StatelessWidget {
  final String teamName;
  final int score;
  final Color primaryColor;
  final Color accentColor;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool isActive;
  final String? mascotAsset;
  final String teamId; // 'A' or 'B'

  const TeamCard({
    super.key,
    required this.teamName,
    required this.score,
    required this.primaryColor,
    required this.accentColor,
    required this.onIncrement,
    required this.onDecrement,
    required this.teamId,
    this.isActive = true,
    this.mascotAsset,
  });

  int _streak(HypeVoiceController hype) =>
      hype.currentStreakTeam.value == teamId ? hype.streakCount.value : 0;

  double _intensity(int streak) {
    if (streak < 2) return 0.0;
    if (streak == 2) return 0.22;
    if (streak == 3) return 0.48;
    if (streak == 4) return 0.74;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final bool isTablet = width > 400 || height > 400;

        return Obx(() {
          final hype = Get.find<HypeVoiceController>();
          final streak = _streak(hype);
          final intensity = _intensity(streak);
          final bool onStreak = streak >= 2;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primaryColor.withOpacity(0.55 + intensity * 0.30),
                  accentColor.withOpacity(0.45 + intensity * 0.25),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.30 + intensity * 0.45),
                  blurRadius: onStreak ? 40 + intensity * 30 : 20,
                  spreadRadius: onStreak ? 3 + intensity * 6 : -5,
                ),
                if (onStreak)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.10 + intensity * 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: onStreak
                        ? primaryColor.withOpacity(0.5 + intensity * 0.4)
                        : Colors.white.withOpacity(0.15),
                    width: onStreak ? 2.0 + intensity : 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // ── Original fire effect (streak >= 2) ────────────────
                    if (onStreak)
                      Positioned.fill(
                        child: _ModernFireEffect(
                          color: primaryColor.withOpacity(0.35 + intensity * 0.25),
                        ),
                      ),

                    // ── Balloon celebration (streak >= 3) ─────────────────
                    if (streak >= 3)
                      Positioned.fill(
                        child: _BalloonEffect(
                          color: accentColor.withOpacity(0.20 + intensity * 0.20),
                        ),
                      ),

                    if (mascotAsset != null)
                      _buildWatermark(mascotAsset!, width, height, intensity),

                    _buildScoreArea(width, height, isTablet, streak, intensity),

                    Positioned(
                      top: 10,
                      left: 10,
                      child: _buildControl(
                          icon: Icons.remove,
                          onTap: onDecrement,
                          size: isTablet ? 52 : 38),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _buildControl(
                          icon: Icons.add,
                          onTap: onIncrement,
                          size: isTablet ? 52 : 38),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildWatermark(String asset, double w, double h, double intensity) {
    final double size = (w * 0.85).clamp(80.0, 360.0).clamp(0.0, h * 0.65);
    return Positioned(
      bottom: -size * 0.08,
      right: -size * 0.05,
      child: Opacity(
        opacity: 0.13 + intensity * 0.12,
        child: Image.asset(asset, width: size, height: size, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildScoreArea(
      double w, double h, bool isTablet, int streak, double intensity) {
    double fontSize = isTablet
        ? (h * 0.75).clamp(150, 500)
        : (h * 0.7).clamp(100, 250);
    if (score > 9) fontSize *= 0.8;
    final double iconSize = isTablet ? 36.0 : 24.0;

    // Score pop grows dramatically with streak level
    final double scaleBegin = streak >= 5
        ? 0.28
        : streak == 4
            ? 0.44
            : streak == 3
                ? 0.62
                : streak == 2
                    ? 0.78
                    : 0.88;
    final int scaleDurationMs = streak >= 4 ? 400 : 260;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isActive) {
            HapticFeedback.heavyImpact();
            onIncrement();
          }
        },
        splashColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 1),

              // ── Team name + inline streak badge ───────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (mascotAsset != null) ...[
                    Image.asset(mascotAsset!,
                        width: iconSize, height: iconSize, fit: BoxFit.contain),
                    SizedBox(width: isTablet ? 12 : 8),
                  ],
                  Text(
                    teamName.toUpperCase(),
                    style: TextStyle(
                      fontSize: w < h ? 14 : (isTablet ? 26 : 16),
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(streak >= 2 ? 0.9 : 0.6),
                      letterSpacing: 4,
                    ),
                  ),
                  // 🔥 streak badge — static glow, no blink
                  if (streak >= 2) ...[
                    SizedBox(width: isTablet ? 8 : 5),
                    _buildStreakBadge(streak, isTablet, intensity),
                  ],
                ],
              ).animate().fadeIn(duration: 400.ms),

              // ── Score (continuous pulse + pop on change) ──────────────
              _PulsingScore(
                score: score,
                streak: streak,
                intensity: intensity,
                fontSize: fontSize,
                primaryColor: primaryColor,
                accentColor: accentColor,
                scaleBegin: scaleBegin,
                scaleDurationMs: scaleDurationMs,
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakBadge(int streak, bool isTablet, double intensity) {
    final Color c = streak >= 5
        ? Colors.yellowAccent
        : streak == 4
            ? Colors.orangeAccent
            : streak == 3
                ? Colors.orange
                : Colors.deepOrangeAccent;
    final double fs = (isTablet ? 14.0 : 11.0) + (streak - 2) * 1.5;

    return Text(
      '🔥x$streak',
      style: TextStyle(
        fontSize: fs,
        fontWeight: FontWeight.w900,
        color: c,
        shadows: [
          Shadow(color: c, blurRadius: 6 + intensity * 16),
          if (streak >= 4)
            Shadow(color: Colors.orangeAccent, blurRadius: 24 * intensity),
        ],
      ),
    );
  }

  Widget _buildControl({
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
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white70, size: size * 0.6),
      ),
    );
  }
}

// ── Pulsing score: continuous breathe loop + pop on score change ─────
class _PulsingScore extends StatefulWidget {
  final int score;
  final int streak;
  final double intensity;
  final double fontSize;
  final Color primaryColor;
  final Color accentColor;
  final double scaleBegin;
  final int scaleDurationMs;

  const _PulsingScore({
    required this.score,
    required this.streak,
    required this.intensity,
    required this.fontSize,
    required this.primaryColor,
    required this.accentColor,
    required this.scaleBegin,
    required this.scaleDurationMs,
  });

  @override
  State<_PulsingScore> createState() => _PulsingScoreState();
}

class _PulsingScoreState extends State<_PulsingScore>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Pulse amplitude grows with streak: 0 → 3% → 6% → 9% → 12%
  double get _amplitude {
    if (widget.streak < 2) return 0.0;
    if (widget.streak == 2) return 0.030;
    if (widget.streak == 3) return 0.060;
    if (widget.streak == 4) return 0.090;
    return 0.120;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      // child is rebuilt only when parent rebuilds (score/streak change)
      // AnimatedBuilder reuses child each frame — no unnecessary rebuilds
      child: Text(
        '${widget.score}',
        key: ValueKey(widget.score),
        style: GoogleFonts.orbitron(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.0,
          shadows: [
            Shadow(
              color: widget.primaryColor,
              blurRadius: 30 + widget.intensity * 55,
            ),
            if (widget.streak >= 3)
              Shadow(
                color: widget.accentColor.withOpacity(0.75),
                blurRadius: 55 * widget.intensity,
              ),
            const Shadow(
              color: Colors.black,
              offset: Offset(0, 6),
              blurRadius: 20,
            ),
          ],
        ),
      )
          .animate(key: ValueKey(widget.score))
          .scale(
            duration: Duration(milliseconds: widget.scaleDurationMs),
            curve: Curves.easeOutBack,
            begin: Offset(widget.scaleBegin, widget.scaleBegin),
            end: const Offset(1.0, 1.0),
          )
          .shimmer(
            duration:
                Duration(milliseconds: widget.streak >= 4 ? 480 : 1200),
            color: Colors.white.withOpacity(0.20 + widget.intensity * 0.55),
          ),
      builder: (_, child) {
        // Sine wave: smooth full oscillation each 600ms cycle
        final pulse = widget.streak >= 2
            ? 1.0 + math.sin(_ctrl.value * 2 * math.pi) * _amplitude
            : 1.0;
        return Transform.scale(scale: pulse, child: child);
      },
    );
  }
}

// ── MODERN FIRE EFFECT (Stylized vertical streaks) ───────────────────
class _ModernFireEffect extends StatefulWidget {
  final Color color;
  const _ModernFireEffect({required this.color});
  @override
  State<_ModernFireEffect> createState() => _ModernFireEffectState();
}

class _ModernFireEffectState extends State<_ModernFireEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _FirePainter(progress: _controller.value, color: widget.color),
      ),
    );
  }
}

class _FirePainter extends CustomPainter {
  final double progress;
  final Color color;
  _FirePainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);
    for (int i = 0; i < 25; i++) {
      final double x = random.nextDouble() * size.width;
      final double h = 40 + random.nextDouble() * 100;
      final double p = (progress + random.nextDouble()) % 1.0;
      final double y = size.height - (p * size.height * 1.2);
      final double w = (1.0 - p) * 12;

      final rect = Rect.fromLTWH(x - w / 2, y, w, h * (1.0 - p));
      paint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [color.withOpacity(0.8 * (1.0 - p)), Colors.transparent],
      ).createShader(rect);

      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(10)), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── BALLOON CELEBRATION EFFECT ──────────────────────────────────────
class _BalloonEffect extends StatefulWidget {
  final Color color;
  const _BalloonEffect({required this.color});
  @override
  State<_BalloonEffect> createState() => _BalloonEffectState();
}

class _BalloonEffectState extends State<_BalloonEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Balloon> _balloons =
      List.generate(12, (index) => _Balloon());
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _BalloonPainter(
            balloons: _balloons,
            progress: _controller.value,
            color: widget.color),
      ),
    );
  }
}

class _Balloon {
  final double x = math.Random().nextDouble();
  final double size = 15 + math.Random().nextDouble() * 25;
  final double speed = 0.5 + math.Random().nextDouble() * 1.5;
  final double drift = math.Random().nextDouble() * 2 * math.pi;
}

class _BalloonPainter extends CustomPainter {
  final List<_Balloon> balloons;
  final double progress;
  final Color color;
  _BalloonPainter(
      {required this.balloons, required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var b in balloons) {
      final double p = (progress * b.speed) % 1.0;
      final double y = size.height - (p * (size.height + 100));
      final double x =
          (b.x * size.width) + math.sin(progress * 2 * math.pi + b.drift) * 20;
      final double opacity = (1.0 - p).clamp(0.0, 1.0);

      paint.color = color.withOpacity(opacity * 0.6);
      canvas.drawCircle(Offset(x, y), b.size / 2, paint);

      final tailPaint = Paint()
        ..color = paint.color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(x, y + b.size / 2)
        ..quadraticBezierTo(
            x + 5, y + b.size / 2 + 10, x, y + b.size / 2 + 20);
      canvas.drawPath(path, tailPaint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
