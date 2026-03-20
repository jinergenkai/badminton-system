import 'dart:math';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'models/hand_gesture.dart';

enum _ThumbDirection { up, down, neutral }

class GestureClassifier {
  static const double _thumbDirectionThreshold = 0.04;

  HandGesture classify(List<Landmark> landmarks) {
    if (landmarks.length < 21) return HandGesture.none;

    final thumbExtended = _isThumbExtended(landmarks);
    final indexFolded = !_isFingerExtended(landmarks, 8, 6);
    final middleFolded = !_isFingerExtended(landmarks, 12, 10);
    final ringFolded = !_isFingerExtended(landmarks, 16, 14);
    final pinkyFolded = !_isFingerExtended(landmarks, 20, 18);

    final allFingersFolded =
        indexFolded && middleFolded && ringFolded && pinkyFolded;

    if (thumbExtended && allFingersFolded) {
      final direction = _getThumbDirection(landmarks);
      if (direction == _ThumbDirection.up) return HandGesture.thumbsUp;
      if (direction == _ThumbDirection.down) return HandGesture.thumbsDown;
    }

    final allFingersExtended =
        !indexFolded && !middleFolded && !ringFolded && !pinkyFolded;
    if (thumbExtended && allFingersExtended) {
      return HandGesture.openPalm;
    }

    return HandGesture.none;
  }

  Map<String, bool> getFingerStates(List<Landmark> landmarks) {
    if (landmarks.length < 21) {
      return {
        'thumb': false,
        'index': false,
        'middle': false,
        'ring': false,
        'pinky': false,
      };
    }
    return {
      'thumb': _isThumbExtended(landmarks),
      'index': _isFingerExtended(landmarks, 8, 6),
      'middle': _isFingerExtended(landmarks, 12, 10),
      'ring': _isFingerExtended(landmarks, 16, 14),
      'pinky': _isFingerExtended(landmarks, 20, 18),
    };
  }

  // Finger (non-thumb) is extended when TIP y < PIP y
  // (y=0 is top of frame, y=1 is bottom)
  bool _isFingerExtended(List<Landmark> landmarks, int tipIdx, int pipIdx) {
    return landmarks[tipIdx].y < landmarks[pipIdx].y;
  }

  // Thumb is extended when TIP is farther from WRIST than MCP
  bool _isThumbExtended(List<Landmark> landmarks) {
    final tipToWrist = _distance(landmarks[4], landmarks[0]);
    final mcpToWrist = _distance(landmarks[2], landmarks[0]);
    return tipToWrist > mcpToWrist * 1.2;
  }

  _ThumbDirection _getThumbDirection(List<Landmark> landmarks) {
    if (landmarks[4].y < landmarks[2].y - _thumbDirectionThreshold) {
      return _ThumbDirection.up;
    }
    if (landmarks[4].y > landmarks[2].y + _thumbDirectionThreshold) {
      return _ThumbDirection.down;
    }
    return _ThumbDirection.neutral;
  }

  double _distance(Landmark a, Landmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }
}
