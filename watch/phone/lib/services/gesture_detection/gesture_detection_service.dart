import 'dart:async';
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
  // Keeps the main isolate free for UI rendering between detections.
  static const int _frameIntervalMs = 100;
  int _lastProcessMs = 0;

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
      numHands: 1,
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
    if (hands.isEmpty) return null;
    return hands.reduce((a, b) =>
        _boundingBoxArea(a) > _boundingBoxArea(b) ? a : b);
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
