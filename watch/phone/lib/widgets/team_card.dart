import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';

class TeamCard extends StatefulWidget {
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

  @override
  State<TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends State<TeamCard> with SingleTickerProviderStateMixin {
  late AnimationController _servicePulseCtrl;

  @override
  void initState() {
    super.initState();
    _servicePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // Faster for strobe feel
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _servicePulseCtrl.dispose();
    super.dispose();
  }

  int _streak(HypeVoiceController hype) =>
      hype.currentStreakTeam.value == widget.teamId ? hype.streakCount.value : 0;

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
          final bool isServing = streak > 0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.primaryColor.withOpacity(0.5),
                  widget.accentColor.withOpacity(0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.primaryColor.withOpacity(onStreak ? 0.4 + intensity * 0.4 : 0.2),
                  blurRadius: onStreak ? 40 + intensity * 30 : 20,
                  spreadRadius: onStreak ? 3 + intensity * 6 : -5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isServing
                        ? Colors.white.withOpacity(0.3 + intensity * 0.5)
                        : Colors.white.withOpacity(0.15),
                    width: isServing ? 2.5 : 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // ── Active Corner Highlight (Strobing) ──
                    if (isServing)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _servicePulseCtrl,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _ServiceHighlightPainter(
                                teamId: widget.teamId,
                                streak: streak,
                                score: widget.score,
                                pulse: _servicePulseCtrl.value,
                                color: widget.primaryColor,
                                intensity: intensity,
                              ),
                            );
                          },
                        ),
                      ),

                    // ── Original fire effect (streak >= 2) ────────────────
                    if (onStreak)
                      Positioned.fill(
                        child: _ModernFireEffect(
                          color: widget.primaryColor.withOpacity(0.35 + intensity * 0.25),
                        ),
                      ),

                    // ── Balloon celebration (streak >= 3) ─────────────────
                    if (streak >= 3)
                      Positioned.fill(
                        child: _BalloonEffect(
                          color: widget.accentColor.withOpacity(0.20 + intensity * 0.20),
                        ),
                      ),

                    if (widget.mascotAsset != null)
                      _buildWatermark(widget.mascotAsset!, width, height, intensity),

                    _buildScoreArea(width, height, isTablet, streak, intensity),

                    Positioned(
                      top: 10,
                      left: 10,
                      child: _buildControl(
                          icon: Icons.remove,
                          onTap: widget.onDecrement,
                          size: isTablet ? 52 : 38),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _buildControl(
                          icon: Icons.add,
                          onTap: widget.onIncrement,
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
    if (widget.score > 9) fontSize *= 0.8;
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
          if (widget.isActive) {
            HapticFeedback.heavyImpact();
            widget.onIncrement();
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
                  if (widget.mascotAsset != null) ...[
                    Image.asset(widget.mascotAsset!,
                        width: iconSize, height: iconSize, fit: BoxFit.contain),
                    SizedBox(width: isTablet ? 12 : 8),
                  ],
                  Text(
                    widget.teamName.toUpperCase(),
                    style: TextStyle(
                      fontSize: w < h ? 14 : (isTablet ? 26 : 16),
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(streak >= 2 ? 0.9 : 0.6),
                      letterSpacing: 4,
                    ),
                  ),
                  // 🔥 streak badge
                  if (streak >= 2) ...[
                    SizedBox(width: isTablet ? 8 : 5),
                    _buildStreakBadge(streak, isTablet, intensity),
                  ],
                ],
              ).animate().fadeIn(duration: 400.ms),

              // ── Score (continuous pulse + pop on change) ──────────────
              _PulsingScore(
                score: widget.score,
                streak: streak,
                intensity: intensity,
                fontSize: fontSize,
                primaryColor: widget.primaryColor,
                accentColor: widget.accentColor,
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
      'x$streak',
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

// ── Service Highlight Painter ───────────────────────────────────────
class _ServiceHighlightPainter extends CustomPainter {
  final String teamId;
  final int streak;
  final int score;
  final double pulse;
  final Color color;
  final double intensity;

  _ServiceHighlightPainter({
    required this.teamId,
    required this.streak,
    required this.score,
    required this.pulse,
    required this.color,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle global dim to help the flash stand out slightly
    final baseDim = Paint()..color = Colors.black.withOpacity(0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), baseDim);

    // 2. Parity Logic
    // Team A (Left - Red): Lẻ (Odd) = Chéo Trên, Chẵn (Even) = Chéo Dưới
    // Team B (Right - Blue): Chẵn (Even) = Chéo Trên, Lẻ (Odd) = Chéo Dưới
    final bool isEven = score % 2 == 0;
    final bool highlightTop;
    if (teamId == 'A') {
      highlightTop = !isEven; // Odd -> Top
    } else {
      highlightTop = isEven;  // Even -> Top
    }

    // 3. Calculation for 20-degree line split
    // tan(20°) ≈ 0.36397
    const double tan20 = 0.36397;
    final double halfW = size.width / 2;
    final double halfH = size.height / 2;
    
    // Points at edges for a line through center
    final double yLeft = tan20 * halfW + halfH;
    final double yRight = -tan20 * halfW + halfH;
    
    final Offset pLeft = Offset(0, yLeft);
    final Offset pRight = Offset(size.width, yRight);

    final pathTop = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(pRight.dx, pRight.dy)
      ..lineTo(pLeft.dx, pLeft.dy)
      ..close();

    final pathBottom = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(pRight.dx, pRight.dy)
      ..lineTo(pLeft.dx, pLeft.dy)
      ..close();

    final Path activePath = highlightTop ? pathTop : pathBottom;
    final Path inactivePath = highlightTop ? pathBottom : pathTop;

    // 4. Draw Active Light (High-Intensity Solid Strobe)
    // -------------------------------------------------------------------------
    // HƯỚNG DẪN CHỈNH SỬA:
    // - Muốn nháy nhanh/chậm: Chỉnh số '4' trong (pulse * 4 * math.pi). Số càng lớn nháy càng nhanh.
    // - Muốn độ sáng nháy mạnh/nhẹ: Chỉnh số '0.1' (độ sáng nền) và '0.4' (biên độ nháy).
    // -------------------------------------------------------------------------
    final double strobe = (math.sin(pulse * 4 * math.pi) * 0.5 + 0.5); 
    final double activeAlpha = (0.1 + strobe * 0.4); // Giảm nhẹ: 0.1 đến 0.5
    
    final lightPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(activeAlpha);
    
    canvas.drawPath(activePath, lightPaint);

    // ── Dim for inactive side (Làm tối vùng đối diện) ──
    // HƯỚNG DẪN: Chỉnh '0.2' lớn hơn nếu muốn vùng kia tối hơn.
    final sideDimPaint = Paint()..color = Colors.black.withOpacity(0.2); 
    canvas.drawPath(inactivePath, sideDimPaint);

    // 5. NEON SEPARATOR LINE (20 degrees)
    final double neonAlpha = (0.3 + strobe * 0.5); 
    
    // Outer Glow (Wide)
    final outerGlow = Paint()
      ..color = color.withOpacity(0.2 + intensity * 0.5)
      ..strokeWidth = 15.0 + intensity * 25.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pLeft, pRight, outerGlow);

    // Inner Line (Solid White Strobe)
    final innerLine = Paint()
      ..color = Colors.white.withOpacity(neonAlpha)
      ..strokeWidth = 3.0 + intensity * 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pLeft, pRight, innerLine);
  }

  @override
  bool shouldRepaint(covariant _ServiceHighlightPainter oldDelegate) =>
      oldDelegate.pulse != pulse || 
      oldDelegate.streak != streak || 
      oldDelegate.score != score || 
      oldDelegate.intensity != intensity;
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
    );
    if (widget.streak >= 2) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulsingScore old) {
    super.didUpdateWidget(old);
    final bool wasActive = old.streak >= 2;
    final bool isActive = widget.streak >= 2;
    if (isActive && !wasActive) {
      _ctrl.repeat();
    } else if (!isActive && wasActive) {
      _ctrl.stop();
      _ctrl.value = 0; // reset so Transform.scale returns 1.0
    }
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
        final pulse = widget.streak >= 2
            ? 1.0 + math.sin(_ctrl.value * 2 * math.pi) * _amplitude
            : 1.0;
        return Transform.scale(scale: pulse, child: child);
      },
    );
  }
}

// ── MODERN FIRE EFFECT (Stylized vertical streaks) ───────────────────
class _FireStreak {
  final double xNorm;       // 0..1 — position along width
  final double height;      // 40..140
  final double phaseOffset; // 0..1 — random phase per streak
  _FireStreak(math.Random r)
      : xNorm = r.nextDouble(),
        height = 40 + r.nextDouble() * 100,
        phaseOffset = r.nextDouble();
}

class _ModernFireEffect extends StatefulWidget {
  final Color color;
  const _ModernFireEffect({required this.color});
  @override
  State<_ModernFireEffect> createState() => _ModernFireEffectState();
}

class _ModernFireEffectState extends State<_ModernFireEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final List<_FireStreak> _streaks;
  @override
  void initState() {
    super.initState();
    final r = math.Random(42);
    _streaks = List.generate(25, (_) => _FireStreak(r));
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _FirePainter(
            progress: _controller.value,
            color: widget.color,
            streaks: _streaks,
          ),
        ),
      ),
    );
  }
}

class _FirePainter extends CustomPainter {
  final double progress;
  final Color color;
  final List<_FireStreak> streaks;
  _FirePainter({
    required this.progress,
    required this.color,
    required this.streaks,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in streaks) {
      final double x = s.xNorm * size.width;
      final double p = (progress + s.phaseOffset) % 1.0;
      final double y = size.height - (p * size.height * 1.2);
      final double w = (1.0 - p) * 12;
      final double rectHeight = s.height * (1.0 - p);

      paint.shader = ui.Gradient.linear(
        Offset(0, y + rectHeight), // bottom
        Offset(0, y),               // top
        [color.withOpacity(0.8 * (1.0 - p)), const Color(0x00000000)],
      );

      final rect = Rect.fromLTWH(x - w / 2, y, w, rectHeight);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(10)), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _FirePainter old) =>
      old.progress != progress || old.color != color;
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _BalloonPainter(
              balloons: _balloons,
              progress: _controller.value,
              color: widget.color),
        ),
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
  bool shouldRepaint(covariant _BalloonPainter old) =>
      old.progress != progress || old.color != color;
}
