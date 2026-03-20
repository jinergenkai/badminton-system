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

    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw Exception('Camera permission denied');
    }

    _debugMode = debugMode;

    // Initialize hand landmarker
    _handLandmarker = HandLandmarkerPlugin.create(
      numHands: 1,
      minHandDetectionConfidence: 0.7,
      delegate: HandLandmarkerDelegate.GPU,
    );

    // Select camera
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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    _isRunning = true;
    _fps.current = 0;

    // Start image stream — skip frames when still processing the previous one
    await _controller!.startImageStream((CameraImage image) {
      if (!_isRunning || _processingFrame) return;
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
        // Normalize landmark coordinates to canonical portrait space before
        // classification. Raw landmarks from detect() are in the ORIGINAL
        // UNROTATED sensor coordinate space (landscape for sensorOrientation=90),
        // so the x/y axes do NOT map to portrait up/down directly.
        // We remap so that "up in portrait" always = small canonical y,
        // enabling the y-based finger-extension checks to work correctly.
        final canonical = _toCanonical(primary.landmarks, _sensorOrientation);
        gesture = _classifier.classify(canonical);
        fingerStates = _classifier.getFingerStates(canonical);
      }

      final event = _smoother.update(gesture);

      // Always emit frame data — status indicator uses it in both modes
      if (!_frameDataController.isClosed) {
        _frameDataController.add(GestureFrameData(
          hands: hands,
          classifiedGesture: gesture,
          stability: _smoother.stability,
          holdProgress: _smoother.holdProgress,
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

  /// Remap landmarks from the raw sensor coordinate space to canonical
  /// portrait space where "up on screen" always corresponds to small y.
  ///
  /// The canvas painter rotates by [sensorOrientation]° to display correctly.
  /// Each rotation below is the inverse coordinate transform for that rotation:
  ///
  ///  0°  → identity          (portrait: -y is up in original landscape y)
  ///  90° → (x,y) → (y, 1-x) (portrait: +x is up in original landscape)
  /// 180° → (x,y) → (1-x, 1-y)
  /// 270° → (x,y) → (1-y, x)
  List<Landmark> _toCanonical(List<Landmark> lms, int sensorOrientation) {
    // Each case maps raw sensor coords to canonical portrait space
    // where canonical_y = 0 is screen top, 1 is screen bottom.
    //
    // Derivation: canvas.rotate(θ°) maps canvas +x → screen direction.
    // "screen UP" tells us which raw coordinate equals small canonical_y.
    //
    //   0°:  canvas -y → up  →  canonical_y = lm.y        (identity)
    //  90°:  canvas -x → up  →  canonical_y = lm.x        (swap x↔y)
    // 180°:  canvas +y → up  →  canonical_y = 1 - lm.y
    // 270°:  canvas +x → up  →  canonical_y = 1 - lm.x
    switch (sensorOrientation) {
      case 90:
        return lms.map((l) => Landmark(l.y, l.x, l.z)).toList();
      case 180:
        return lms.map((l) => Landmark(1.0 - l.x, 1.0 - l.y, l.z)).toList();
      case 270:
        return lms.map((l) => Landmark(l.y, 1.0 - l.x, l.z)).toList();
      default: // 0°
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
  }

  void setDebugMode(bool debug) {
    _debugMode = debug;
  }

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
