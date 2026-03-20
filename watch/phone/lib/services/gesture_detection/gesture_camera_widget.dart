import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'models/hand_gesture.dart';
import 'models/gesture_event.dart';
import 'gesture_detection_service.dart';
import 'gesture_overlay_painter.dart';

/// Draggable debug overlay showing camera preview + landmark overlay.
/// Must be placed inside a [Stack] in the parent widget.
class GestureCameraWidget extends StatefulWidget {
  final GestureDetectionService service;

  const GestureCameraWidget({super.key, required this.service});

  @override
  State<GestureCameraWidget> createState() => _GestureCameraWidgetState();
}

class _GestureCameraWidgetState extends State<GestureCameraWidget> {
  GestureFrameData? _frame;
  StreamSubscription<GestureFrameData>? _frameSub;
  Offset _position = const Offset(16, 80);

  @override
  void initState() {
    super.initState();
    _frameSub = widget.service.frameDataStream.listen((frame) {
      if (mounted) setState(() => _frame = frame);
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.service.cameraController;

    // Compute aspect ratio from the sensor's native preview size.
    // previewSize is in landscape (e.g. 1280x720), but for portrait display
    // we use height/width to get the correct portrait aspect ratio.
    final previewSize = cam?.value.previewSize;
    final aspectRatio = (previewSize != null)
        ? previewSize.height / previewSize.width // portrait
        : 9 / 16;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _position += d.delta),
        child: Container(
          width: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Camera preview + overlay — use AspectRatio so it matches
                // the actual displayed image (no letterboxing / misalignment)
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cam != null && cam.value.isInitialized)
                        CameraPreview(cam)
                      else
                        Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),

                      // Overlay — only rendered when landmarks are available
                      if (_frame != null &&
                          _frame!.hands.isNotEmpty &&
                          cam != null &&
                          previewSize != null)
                        CustomPaint(
                          size: Size.infinite,
                          painter: GestureOverlayPainter(
                            frameData: _frame!,
                            previewSize: previewSize,
                            sensorOrientation:
                                cam.description.sensorOrientation,
                            lensDirection:
                                cam.description.lensDirection,
                          ),
                        ),
                    ],
                  ),
                ),

                // Info bar
                Container(
                  color: Colors.black.withOpacity(0.85),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: _buildInfoBar(),
                ),

                // Controls row
                Container(
                  color: Colors.black.withOpacity(0.75),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => widget.service.switchCamera(
                          cam?.description.lensDirection ==
                                  CameraLensDirection.front
                              ? CameraLensDirection.back
                              : CameraLensDirection.front,
                        ),
                        child: const Icon(Icons.flip_camera_android,
                            color: Colors.white70, size: 20),
                      ),
                      const Spacer(),
                      if (_frame != null)
                        Text(
                          'FPS: ${_frame!.fps.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.greenAccent, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    final frame = _frame;
    if (frame == null) {
      return const Text('Detecting hand...',
          style: TextStyle(color: Colors.white54, fontSize: 11));
    }

    final gesture = frame.classifiedGesture;
    final pct = (frame.stability * 100).round();
    final s = frame.fingerStates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${gesture.emoji} ${gesture.label}',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'Stable: $pct%  ${_fingerStr(s)}',
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
        if (frame.holdProgress > 0) ...[
          const SizedBox(height: 4),
          _HoldBar(progress: frame.holdProgress),
          const SizedBox(height: 2),
          Text(
            _holdTimerText(frame),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ],
    );
  }

  String _fingerStr(Map<String, bool> s) {
    return ['T', 'I', 'M', 'R', 'P']
        .asMap()
        .entries
        .map((e) {
          final keys = ['thumb', 'index', 'middle', 'ring', 'pinky'];
          return '${e.value}:${s[keys[e.key]] == true ? '✓' : '✗'}';
        })
        .join(' ');
  }

  String _holdTimerText(GestureFrameData frame) {
    final isUndo = frame.classifiedGesture == HandGesture.openPalm;
    final totalMs = isUndo ? 2500 : 2000;
    final elapsed = (frame.holdProgress * totalMs / 1000).toStringAsFixed(1);
    final total = (totalMs / 1000).toStringAsFixed(1);
    return 'Hold: ${elapsed}s / ${total}s';
  }
}

/// Compact production-mode indicator — shows camera dot + current gesture + hold bar.
class GestureStatusIndicator extends StatefulWidget {
  final GestureDetectionService service;

  const GestureStatusIndicator({super.key, required this.service});

  @override
  State<GestureStatusIndicator> createState() =>
      _GestureStatusIndicatorState();
}

class _GestureStatusIndicatorState extends State<GestureStatusIndicator> {
  GestureFrameData? _frame;
  StreamSubscription<GestureFrameData>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.frameDataStream.listen((f) {
      if (mounted) setState(() => _frame = f);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gesture = _frame?.classifiedGesture ?? HandGesture.none;
    final holdProgress = _frame?.holdProgress ?? 0.0;
    final isHolding = gesture != HandGesture.none && holdProgress > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Colors.red, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        if (isHolding) ...[
          Text('${gesture.emoji} Hold',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          _HoldBar(progress: holdProgress),
        ] else
          Text(
            gesture != HandGesture.none
                ? '${gesture.emoji} ${gesture.label}'
                : 'Gesture ready',
            style: TextStyle(
                color: gesture != HandGesture.none
                    ? Colors.white
                    : Colors.white54,
                fontSize: 12),
          ),
      ],
    );
  }
}

class _HoldBar extends StatelessWidget {
  final double progress;
  const _HoldBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation(
            progress >= 1.0 ? Colors.greenAccent : Colors.yellowAccent,
          ),
        ),
      ),
    );
  }
}
