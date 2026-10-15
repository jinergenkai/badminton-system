import 'dart:math' as math;
import '../services/display_settings.dart';
import 'frame_clock.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../views/ui_kit.dart';
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
  /// Physical panel position on the tablet, independent of team colour/id.
  /// The service-court stripe must mirror when the scoreboard sides swap.
  final bool isLeftPanel;

  const TeamCard({
    super.key,
    required this.teamName,
    required this.score,
    required this.primaryColor,
    required this.accentColor,
    required this.onIncrement,
    required this.onDecrement,
    required this.teamId,
    required this.isLeftPanel,
    this.isActive = true,
    this.mascotAsset,
  });

  @override
  State<TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends State<TeamCard> {
  late final FrameClock _servicePulseCtrl;

  @override
  void initState() {
    super.initState();
    // Throttled (30 fps high / 10 fps low) and only running while this card
    // is the serving one: a repeating AnimationController drew 60 frames a
    // second even at 0-0 — measured 40% UI + 30% raster CPU on the tablet.
    _servicePulseCtrl = FrameClock(period: _strobePeriod, fps: _fx.fps, reverse: true);
    final hype = Get.find<HypeVoiceController>();
    _pulseSubs = [
      ever(hype.currentStreakTeam, (_) => _syncPulse()),
      ever(hype.streakCount, (_) => _syncPulse()),
      ever(_fx.level, (_) {
        _servicePulseCtrl.configure(period: _strobePeriod, fps: _fx.fps);
        if (mounted) setState(() {});
      }),
    ];
    _syncPulse();
  }

  DisplaySettings get _fx => DisplaySettings.maybe ?? (DisplaySettings()..level.value = DisplaySettings.low);

  /// One full bright→dim→bright cycle; low blinks slowly.
  Duration get _strobePeriod => Duration(milliseconds: _fx.isHigh ? 2000 : 4000);

  late final List<Worker> _pulseSubs;

  void _syncPulse() {
    if (!mounted) return;
    final serving = _streak(Get.find<HypeVoiceController>()) > 0;
    if (serving) {
      _servicePulseCtrl.start();
    } else {
      _servicePulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    for (final w in _pulseSubs) {
      w.dispose();
    }
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
          final bool fxHigh = _fx.level.value == DisplaySettings.high;

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
                                isLeftPanel: widget.isLeftPanel,
                                streak: streak,
                                score: widget.score,
                                pulse: _servicePulseCtrl.value,
                                color: widget.primaryColor,
                                intensity: intensity,
                                glow: fxHigh,
                              ),
                            );
                          },
                        ),
                      ),

                    // ── Original fire effect (streak >= 2) ────────────────
                    if (onStreak && fxHigh)
                      Positioned.fill(
                        child: _ModernFireEffect(
                          color: widget.primaryColor.withOpacity(0.35 + intensity * 0.25),
                        ),
                      ),

                    // ── Balloon celebration (streak >= 3) ─────────────────
                    if (streak >= 3 && fxHigh)
                      Positioned.fill(
                        child: _BalloonEffect(
                          color: widget.accentColor.withOpacity(0.20 + intensity * 0.20),
                        ),
                      ),

                    if (widget.mascotAsset != null)
                      _buildWatermark(widget.mascotAsset!, width, height, intensity),

                    _buildScoreArea(width, height, isTablet, streak, intensity, fxHigh),

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
      double w, double h, bool isTablet, int streak, double intensity, bool fxHigh) {
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
          if (widget.isActive) widget.onIncrement();
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
                fxHigh: fxHigh,
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
      onTap: onTap,
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
  final bool isLeftPanel;
  final int streak;
  final int score;
  final double pulse;
  final Color color;
  final double intensity;

  /// The soft halo around the dividing line: a blur, the costly part of this
  /// painter on a weak GPU. Low graphics draws a flat wide band instead.
  final bool glow;

  _ServiceHighlightPainter({
    required this.isLeftPanel,
    required this.streak,
    required this.score,
    required this.pulse,
    required this.color,
    required this.intensity,
    this.glow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle global dim to help the flash stand out slightly
    final baseDim = Paint()..color = Colors.black.withOpacity(0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), baseDim);

    // 2. Parity Logic
    // This is about the tablet's physical left/right panel, not team id.
    // A/B may move when the umpire swaps scoreboard sides.
    final bool isEven = score % 2 == 0;
    final bool highlightTop;
    if (isLeftPanel) {
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
      ..color = color.withOpacity((0.2 + intensity * 0.5) * (glow ? 1 : 0.5))
      ..strokeWidth = glow ? 15.0 + intensity * 25.0 : 8.0
      ..style = PaintingStyle.stroke;
    if (glow) outerGlow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
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
      oldDelegate.intensity != intensity ||
      oldDelegate.glow != glow;
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

  /// Low graphics: the pop on a new score stays, the breathing and the
  /// shimmer go.
  final bool fxHigh;

  const _PulsingScore({
    required this.score,
    required this.streak,
    required this.intensity,
    required this.fontSize,
    required this.primaryColor,
    required this.accentColor,
    required this.scaleBegin,
    required this.scaleDurationMs,
    this.fxHigh = true,
  });

  @override
  State<_PulsingScore> createState() => _PulsingScoreState();
}

class _PulsingScoreState extends State<_PulsingScore> {
  late final FrameClock _ctrl;

  bool get _breathing => widget.streak >= 2 && widget.fxHigh;

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
    _ctrl = FrameClock(period: const Duration(milliseconds: 600), fps: 30);
    if (_breathing) _ctrl.start();
  }

  @override
  void didUpdateWidget(covariant _PulsingScore old) {
    super.didUpdateWidget(old);
    final bool wasActive = old.streak >= 2 && old.fxHigh;
    if (_breathing && !wasActive) {
      _ctrl.start();
    } else if (!_breathing && wasActive) {
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
    final text = Text(
        '${widget.score}',
        key: ValueKey(widget.score),
        style: Ui.orbitron(
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
      );
    var popped = text.animate(key: ValueKey(widget.score)).scale(
          duration: Duration(milliseconds: widget.scaleDurationMs),
          curve: Curves.easeOutBack,
          begin: Offset(widget.scaleBegin, widget.scaleBegin),
          end: const Offset(1.0, 1.0),
        );
    if (widget.fxHigh) {
      popped = popped.shimmer(
        duration: Duration(milliseconds: widget.streak >= 4 ? 480 : 1200),
        color: Colors.white.withOpacity(0.20 + widget.intensity * 0.55),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      child: popped,
      builder: (_, child) {
        final pulse = _breathing ? 1.0 + math.sin(_ctrl.value * 2 * math.pi) * _amplitude : 1.0;
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

class _ModernFireEffectState extends State<_ModernFireEffect> {
  late final FrameClock _controller;
  late final List<_FireStreak> _streaks;
  @override
  void initState() {
    super.initState();
    final r = math.Random(42);
    _streaks = List.generate(25, (_) => _FireStreak(r));
    _controller = FrameClock(period: const Duration(seconds: 1), fps: 30)..start();
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

class _BalloonEffectState extends State<_BalloonEffect> {
  late final FrameClock _controller;
  final List<_Balloon> _balloons =
      List.generate(12, (index) => _Balloon());
  @override
  void initState() {
    super.initState();
    _controller = FrameClock(period: const Duration(seconds: 3), fps: 30)..start();
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
