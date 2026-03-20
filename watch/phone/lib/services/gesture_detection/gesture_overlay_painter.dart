import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'models/hand_gesture.dart';
import 'models/gesture_event.dart';

// Official connection list from hand_landmarker package example
const _connections = [
  [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
  [0, 5], [5, 6], [6, 7], [7, 8], // Index
  [5, 9], [9, 10], [10, 11], [11, 12], // Middle
  [9, 13], [13, 14], [14, 15], [15, 16], // Ring
  [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // Pinky
];

class GestureOverlayPainter extends CustomPainter {
  final GestureFrameData frameData;
  final Size previewSize; // camera sensor's native size (e.g. 1280x720)
  final int sensorOrientation; // e.g. 90 for back camera
  final CameraLensDirection lensDirection;

  GestureOverlayPainter({
    required this.frameData,
    required this.previewSize,
    required this.sensorOrientation,
    required this.lensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frameData.hands.isEmpty) return;

    final hand = frameData.hands.first;
    final landmarks = hand.landmarks;
    if (landmarks.isEmpty) return;

    // --- Coordinate transform (matches official hand_landmarker example) ---
    // Landmarks are in the rotated (portrait) image space.
    // We need to apply sensorOrientation rotation + scaling to align with CameraPreview.
    final scale = size.width / previewSize.height;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sensorOrientation * math.pi / 180);
    if (lensDirection == CameraLensDirection.front) {
      canvas.scale(-1.0, 1.0);
      canvas.rotate(math.pi);
    }
    canvas.scale(scale);

    final logicalW = previewSize.width;
    final logicalH = previewSize.height;

    final fingerStates = frameData.fingerStates;

    final connPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 3.0 / scale
      ..style = PaintingStyle.stroke;

    final extPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    final foldPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    // Draw skeleton connections
    for (final conn in _connections) {
      if (conn[0] < landmarks.length && conn[1] < landmarks.length) {
        canvas.drawLine(
          _lmToOffset(landmarks[conn[0]], logicalW, logicalH),
          _lmToOffset(landmarks[conn[1]], logicalW, logicalH),
          connPaint,
        );
      }
    }

    // Draw landmark dots
    for (int i = 0; i < landmarks.length; i++) {
      final isExt = _isLandmarkExtended(i, fingerStates);
      canvas.drawCircle(
        _lmToOffset(landmarks[i], logicalW, logicalH),
        6.0 / scale,
        isExt ? extPaint : foldPaint,
      );
    }

    canvas.restore();

    // --- HUD elements drawn in screen space (no canvas transform) ---
    _drawHoldRing(canvas, size);
    _drawLabel(canvas, size);
    _drawFingerStates(canvas, size, fingerStates);
    _drawFps(canvas, size);
  }

  /// Maps a landmark to centered canvas coordinates before the scale transform.
  Offset _lmToOffset(Landmark lm, double w, double h) {
    return Offset((lm.x - 0.5) * w, (lm.y - 0.5) * h);
  }

  bool _isLandmarkExtended(int index, Map<String, bool> states) {
    if (index >= 1 && index <= 4) return states['thumb'] ?? false;
    if (index >= 5 && index <= 8) return states['index'] ?? false;
    if (index >= 9 && index <= 12) return states['middle'] ?? false;
    if (index >= 13 && index <= 16) return states['ring'] ?? false;
    if (index >= 17 && index <= 20) return states['pinky'] ?? false;
    return false;
  }

  void _drawHoldRing(Canvas canvas, Size size) {
    final progress = frameData.holdProgress;
    if (progress <= 0) return;

    final center = Offset(size.width / 2, 36);
    const r = 22.0;
    const sw = 4.0;

    canvas.drawCircle(
      center, r,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = progress >= 1.0 ? Colors.greenAccent : Colors.yellowAccent
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawLabel(Canvas canvas, Size size) {
    final gesture = frameData.classifiedGesture;
    if (gesture == HandGesture.none) return;

    final pct = (frameData.stability * 100).round();
    final tp = TextPainter(
      text: TextSpan(
        text: '${gesture.emoji} ${gesture.label}  $pct% stable',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    final bgRect =
        Rect.fromLTWH(8, size.height - 72, tp.width + 14, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()..color = Colors.black.withOpacity(0.55),
    );
    tp.paint(canvas, Offset(15, size.height - 69));
  }

  void _drawFingerStates(Canvas canvas, Size size, Map<String, bool> s) {
    final labels = ['T', 'I', 'M', 'R', 'P'];
    final keys = ['thumb', 'index', 'middle', 'ring', 'pinky'];
    final text = List.generate(
        labels.length, (i) => '${labels[i]}:${s[keys[i]] == true ? '✓' : '✗'}')
        .join(' ');

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, size.height - 46));
  }

  void _drawFps(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'FPS: ${frameData.fps.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 6, 6));
  }

  @override
  bool shouldRepaint(GestureOverlayPainter oldDelegate) => true;
}
