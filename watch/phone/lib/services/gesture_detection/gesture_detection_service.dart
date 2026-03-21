import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/hand_gesture.dart';
import 'models/gesture_event.dart';
import 'gesture_classifier.dart';
import 'gesture_smoother.dart';

class _FpsCounter {
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  double current = 0.0;

  void tick() {
    _frameCount++;
    final now = DateTime.now();
    final diff = now.difference(_lastTime).inMilliseconds;
    if (diff >= 1000) {
      current = _frameCount * 1000 / diff;
      _frameCount = 0;
      _lastTime = now;
    }
  }
}

class GestureDetectionService {
  HandLandmarkerPlugin? _handLandmarker;
  CameraController? _controller;
  int _sensorOrientation = 0;

  final _classifier = GestureClassifier();
  final _smoother = GestureSmoother();
  final _fps = _FpsCounter();

  bool _isRunning = false;
  bool _debugMode = false;
  bool _processingFrame = false;

  // Throttle: only process one frame every 100 ms (~10 fps max).
  static const int _frameIntervalMs = 100;
  int _lastProcessMs = 0;

  // Hand tracking: lock onto a specific hand to avoid switching between hands.
  static const double _minHandArea = 0.01;     // 1% of frame — ignore tiny/far hands
  static const double _lockRadius = 0.15;       // max center drift to keep lock
  static const int _maxMissFrames = 5;          // ~500ms at 10fps before releasing lock
  double _lockX = 0.0;
  double _lockY = 0.0;
  bool _handLocked = false;
  int _missCount = 0;

  // UI update throttle: only push to stream when something visible changed.
  HandGesture _lastEmittedGesture = HandGesture.none;
  double _lastEmittedHold = 0.0;

  final _frameDataController =
      StreamController<GestureFrameData>.broadcast();
  final _gestureEventController =
      StreamController<GestureEvent>.broadcast();

  Stream<GestureFrameData> get frameDataStream =>
      _frameDataController.stream;
  Stream<GestureEvent> get gestureEvents => _gestureEventController.stream;

  bool get isRunning => _isRunning;
  bool get debugMode => _debugMode;
  CameraController? get cameraController => _controller;

  Future<void> start({
    bool debugMode = false,
    CameraLensDirection lensDirection = CameraLensDirection.back,
  }) async {
    if (_isRunning) return;

    final status = await Permission.camera.request();
    if (!status.isGranted) throw Exception('Camera permission denied');

    _debugMode = debugMode;

    _handLandmarker = HandLandmarkerPlugin.create(
      numHands: 2,
      minHandDetectionConfidence: 0.6,
      delegate: HandLandmarkerDelegate.GPU,
    );

    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras available');

    CameraDescription? selected;
    for (final cam in cameras) {
      if (cam.lensDirection == lensDirection) {
        selected = cam;
        break;
      }
    }
    selected ??= cameras.first;
    _sensorOrientation = selected.sensorOrientation;

    _controller = CameraController(
      selected,
      ResolutionPreset.low, // 320×240 — enough for hand detection, much faster JNI
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    _isRunning = true;
    _fps.current = 0;
    _lastProcessMs = 0;

    await _controller!.startImageStream((CameraImage image) {
      if (!_isRunning || _processingFrame) return;

      // Time-based throttle — skip frames to stay ≤ 10 fps
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastProcessMs < _frameIntervalMs) return;
      _lastProcessMs = nowMs;

      _processingFrame = true;
      _processFrame(image);
    });
  }

  void _processFrame(CameraImage image) {
    try {
      _fps.tick();

      final hands = _handLandmarker!.detect(image, _sensorOrientation);

      final primary = _selectPrimaryHand(hands);
      HandGesture gesture = HandGesture.none;
      Map<String, bool> fingerStates = {};

      if (primary != null) {
        final canonical = _toCanonical(primary.landmarks, _sensorOrientation);
        gesture = _classifier.classify(canonical);
        fingerStates = _classifier.getFingerStates(canonical);
      }

      final event = _smoother.update(gesture);
      final holdProgress = _smoother.holdProgress;

      // Only push UI update when gesture or hold progress changed meaningfully.
      // Avoids rebuilding widgets on every frame when nothing visible changed.
      final gestureChanged = gesture != _lastEmittedGesture;
      final holdChanged = (holdProgress - _lastEmittedHold).abs() > 0.02;

      if ((gestureChanged || holdChanged || event != null) &&
          !_frameDataController.isClosed) {
        _lastEmittedGesture = gesture;
        _lastEmittedHold = holdProgress;
        _frameDataController.add(GestureFrameData(
          hands: hands,
          classifiedGesture: gesture,
          stability: _smoother.stability,
          holdProgress: holdProgress,
          fps: _fps.current,
          fingerStates: fingerStates,
        ));
      }

      if (event != null && !_gestureEventController.isClosed) {
        _gestureEventController.add(event);
      }
    } catch (e) {
      print('🖐 [GestureService] Frame error: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /// Remap from raw sensor space to canonical portrait space (up = small y).
  ///
  ///   0°:  canonical_y = lm.y        (identity)
  ///  90°:  canonical_y = lm.x        (canvas -x → screen up)
  /// 180°:  canonical_y = 1 - lm.y
  /// 270°:  canonical_y = 1 - lm.x   (canvas +x → screen up)
  List<Landmark> _toCanonical(List<Landmark> lms, int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return lms.map((l) => Landmark(l.y, l.x, l.z)).toList();
      case 180:
        return lms.map((l) => Landmark(1.0 - l.x, 1.0 - l.y, l.z)).toList();
      case 270:
        return lms.map((l) => Landmark(l.y, 1.0 - l.x, l.z)).toList();
      default:
        return lms;
    }
  }

  Hand? _selectPrimaryHand(List<Hand> hands) {
    if (hands.isEmpty) {
      // No hands → increment miss counter
      _missCount++;
      if (_missCount > _maxMissFrames) _releaseLock();
      return null;
    }

    // Filter out hands that are too small (too far from camera)
    final viable = <Hand>[];
    for (final hand in hands) {
      if (_boundingBoxArea(hand) >= _minHandArea) {
        viable.add(hand);
      }
    }
    if (viable.isEmpty) {
      _missCount++;
      if (_missCount > _maxMissFrames) _releaseLock();
      return null;
    }

    if (_handLocked) {
      // Find hand closest to lock position
      Hand? best;
      double bestDist = double.infinity;
      for (final hand in viable) {
        final center = _handCenter(hand);
        final dist = _dist2D(center[0], center[1], _lockX, _lockY);
        if (dist < bestDist) {
          bestDist = dist;
          best = hand;
        }
      }

      if (best != null && bestDist <= _lockRadius) {
        // Still tracking the same hand — update lock position
        final center = _handCenter(best);
        _lockX = center[0];
        _lockY = center[1];
        _missCount = 0;
        return best;
      } else {
        // Locked hand drifted too far or disappeared
        _missCount++;
        if (_missCount > _maxMissFrames) _releaseLock();
        return null;
      }
    } else {
      // No lock — pick largest hand and lock onto it
      final largest = viable.reduce((a, b) =>
          _boundingBoxArea(a) > _boundingBoxArea(b) ? a : b);
      final center = _handCenter(largest);
      _lockX = center[0];
      _lockY = center[1];
      _handLocked = true;
      _missCount = 0;
      return largest;
    }
  }

  List<double> _handCenter(Hand hand) {
    double sumX = 0, sumY = 0;
    for (final lm in hand.landmarks) {
      sumX += lm.x;
      sumY += lm.y;
    }
    final n = hand.landmarks.length;
    return [sumX / n, sumY / n];
  }

  double _dist2D(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _releaseLock() {
    _handLocked = false;
    _missCount = 0;
  }

  double _boundingBoxArea(Hand hand) {
    if (hand.landmarks.isEmpty) return 0.0;
    double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final lm in hand.landmarks) {
      if (lm.x < minX) minX = lm.x;
      if (lm.x > maxX) maxX = lm.x;
      if (lm.y < minY) minY = lm.y;
      if (lm.y > maxY) maxY = lm.y;
    }
    return (maxX - minX) * (maxY - minY);
  }

  Future<void> stop() async {
    _isRunning = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    await _controller?.dispose();
    _controller = null;
    _handLandmarker?.dispose();
    _handLandmarker = null;
    _smoother.resetCooldown();
    _releaseLock();
    _lastEmittedGesture = HandGesture.none;
    _lastEmittedHold = 0.0;
  }

  void setDebugMode(bool debug) => _debugMode = debug;

  Future<void> switchCamera(CameraLensDirection direction) async {
    await stop();
    await start(debugMode: _debugMode, lensDirection: direction);
  }

  void dispose() {
    stop();
    _frameDataController.close();
    _gestureEventController.close();
  }
}
