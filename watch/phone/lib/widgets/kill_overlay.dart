import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/hype_voice/models/hype_display_event.dart';

class KillOverlay extends StatelessWidget {
  final HypeDisplayEvent event;
  final String mascotAsset;

  const KillOverlay({
    super.key,
    required this.event,
    required this.mascotAsset,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mascotSize = (size.width * 0.72).clamp(180.0, 380.0);
    final fontSize = _fontSize(event.displayText);

    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── 1. Background Layers ──────────────────────────────────────
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 300.ms),

            // Rotating Cinematic Rays
            Positioned.fill(
              child: _RotatingRays(color: event.glowColor.withOpacity(0.15)),
            ).animate().fadeIn(delay: 200.ms),

            // Animated Speed Lines
            Positioned.fill(
              child: _AnimatedSpeedLines(color: event.glowColor),
            ),

            // ── 2. Impact Burst (Particles) ───────────────────────────────
            Positioned.fill(
              child: _ParticleBurst(color: event.glowColor),
            ),

            // ── 3. Mascot Content (Multi-layered for Motion Blur) ─────────
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Motion Blur Ghost 1
                  Image.asset(mascotAsset, width: mascotSize, height: mascotSize, fit: BoxFit.contain, color: event.glowColor.withOpacity(0.3))
                      .animate()
                      .scale(begin: const Offset(0.1, 0.1), end: const Offset(1.3, 1.3), duration: 300.ms, curve: Curves.easeOut)
                      .fadeOut(duration: 300.ms),

                  // Main Mascot
                  Image.asset(
                    mascotAsset,
                    width: mascotSize,
                    height: mascotSize,
                    fit: BoxFit.contain,
                  )
                      .animate()
                      .scale(begin: const Offset(0.2, 0.2), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut)
                      .rotate(begin: -0.2, end: 0, duration: 500.ms, curve: Curves.elasticOut)
                      .then()
                      .shake(duration: 600.ms, hz: 10, offset: const Offset(8, 8))
                      // IDLE ANIMATION: Float & Breathe
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: -10, end: 10, duration: 2000.ms, curve: Curves.easeInOut)
                      .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.04, 1.04), duration: 1500.ms, curve: Curves.easeInOut),
                ],
              ),
            ),

            // ── 4. Overwhelming Text ──────────────────────────────────────
            Positioned(
              bottom: size.height * 0.15,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Text Glow Aura
                      Text(
                        event.displayText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          color: event.glowColor.withOpacity(0.5),
                          letterSpacing: 4,
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1.0, 1.0), end: const Offset(1.2, 1.2), duration: 1000.ms).blur(begin: const Offset(5, 5), end: const Offset(15, 15)),

                      // Main Text
                      Text(
                        event.displayText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(color: event.glowColor, blurRadius: 30),
                            const Shadow(color: Colors.black, offset: Offset(0, 5), blurRadius: 15),
                          ],
                        ),
                      )
                          .animate()
                          .scale(begin: const Offset(4, 4), end: const Offset(1, 1), duration: 400.ms, curve: Curves.easeOutExpo)
                          .fadeIn()
                          .then()
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(duration: 2000.ms, color: event.glowColor)
                          .shake(duration: 2000.ms, hz: 2, offset: const Offset(2, 0)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeOut(delay: 1200.ms, duration: 300.ms),
    );
  }

  double _fontSize(String text) {
    if (text.length > 18) return 26;
    if (text.length > 12) return 36;
    return 52;
  }
}

// ── Background Ray Painter ───────────────────────────────────────────
class _RotatingRays extends StatefulWidget {
  final Color color;
  const _RotatingRays({required this.color});
  @override
  State<_RotatingRays> createState() => _RotatingRaysState();
}

class _RotatingRaysState extends State<_RotatingRays> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
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
      builder: (context, child) => CustomPaint(painter: RayPainter(color: widget.color, rotation: _controller.value * 2 * math.pi)),
    );
  }
}

class RayPainter extends CustomPainter {
  final Color color;
  final double rotation;
  RayPainter({required this.color, required this.rotation});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 1.5;
    const rayCount = 12;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i * 2 * math.pi / rayCount) + rotation;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + math.cos(angle - 0.15) * radius, center.dy + math.sin(angle - 0.15) * radius)
        ..lineTo(center.dx + math.cos(angle + 0.15) * radius, center.dy + math.sin(angle + 0.15) * radius)
        ..close();
      canvas.drawPath(path, paint);
    }
  }
  @override
  bool shouldRepaint(RayPainter oldDelegate) => oldDelegate.rotation != rotation;
}

// ── Particle Burst ───────────────────────────────────────────────────
class _ParticleBurst extends StatefulWidget {
  final Color color;
  const _ParticleBurst({required this.color});
  @override
  State<_ParticleBurst> createState() => _ParticleBurstState();
}

class _ParticleBurstState extends State<_ParticleBurst> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = List.generate(30, (index) => _Particle());
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
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
      builder: (context, child) => CustomPaint(painter: ParticlePainter(particles: _particles, progress: _controller.value, color: widget.color)),
    );
  }
}

class _Particle {
  final double angle = math.Random().nextDouble() * 2 * math.pi;
  final double speed = 2.0 + math.Random().nextDouble() * 4.0;
  final double size = 2.0 + math.Random().nextDouble() * 4.0;
}

class ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;
  ParticlePainter({required this.particles, required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(1.0 - progress);
    final center = Offset(size.width / 2, size.height / 2);
    for (var p in particles) {
      final distance = progress * p.speed * 150;
      canvas.drawCircle(Offset(center.dx + math.cos(p.angle) * distance, center.dy + math.sin(p.angle) * distance), p.size, paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// ── Animated Speed Lines (Improved) ──────────────────────────────────
class _AnimatedSpeedLines extends StatefulWidget {
  final Color color;
  const _AnimatedSpeedLines({required this.color});
  @override
  State<_AnimatedSpeedLines> createState() => _AnimatedSpeedLinesState();
}

class _AnimatedSpeedLinesState extends State<_AnimatedSpeedLines> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..repeat();
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
      builder: (context, child) => CustomPaint(painter: SpeedLinesPainter(color: widget.color.withOpacity(0.4), progress: _controller.value)),
    );
  }
}

class SpeedLinesPainter extends CustomPainter {
  final Color color;
  final double progress;
  SpeedLinesPainter({required this.color, required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final random = math.Random(42);
    for (var i = 0; i < 45; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final startRadius = 40 + random.nextDouble() * 100 + (progress * 80);
      final length = 100 + random.nextDouble() * 250;
      final start = Offset(center.dx + math.cos(angle) * startRadius, center.dy + math.sin(angle) * startRadius);
      final end = Offset(center.dx + math.cos(angle) * (startRadius + length), center.dy + math.sin(angle) * (startRadius + length));
      final opacity = (1.0 - (startRadius / (size.width / 1.2))).clamp(0.0, 1.0);
      paint.color = color.withOpacity(opacity * 0.8);
      canvas.drawLine(start, end, paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
