import 'dart:math';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'models/hand_gesture.dart';

enum _ThumbDirection { up, down, neutral }

class GestureClassifier {
  static const double _thumbDirectionThreshold = 0.02;

  // DIP indices: tipIdx → dipIdx (joint between PIP and TIP)
  static const _dipIndices = {8: 7, 12: 11, 16: 15, 20: 19};
  // MCP indices: tipIdx → mcpIdx (knuckle base)
  static const _mcpIndices = {8: 5, 12: 9, 16: 13, 20: 17};

  // Cosine thresholds for finger state:
  //   extended: both joints have cos > this (angle < ~75°, mostly straight)
  //   folded:   at least one joint has cos < this (angle > ~110°, clearly bent)
  //   between:  ambiguous → HandGesture.none
  static const double _extendedCosThreshold = 0.25;
  static const double _foldedCosThreshold = -0.35;

  HandGesture classify(List<Landmark> landmarks) {
    if (landmarks.length < 21) return HandGesture.none;

    final thumbExtended = _isThumbExtended(landmarks);
    final indexFolded = _isFingerFolded(landmarks, 8, 6);
    final middleFolded = _isFingerFolded(landmarks, 12, 10);
    final ringFolded = _isFingerFolded(landmarks, 16, 14);
    final pinkyFolded = _isFingerFolded(landmarks, 20, 18);

    final allFingersFolded =
        indexFolded && middleFolded && ringFolded && pinkyFolded;

    // Thumbs Up / Down: thumb extended + 4 fingers clearly folded
    if (thumbExtended && allFingersFolded) {
      final direction = _getThumbDirection(landmarks);
      if (direction == _ThumbDirection.up) return HandGesture.thumbsUp;
      if (direction == _ThumbDirection.down) return HandGesture.thumbsDown;
    }

    // Open Palm: 4 fingers clearly extended (thumb doesn't matter)
    final indexExtended = _isFingerExtended(landmarks, 8, 6);
    final middleExtended = _isFingerExtended(landmarks, 12, 10);
    final ringExtended = _isFingerExtended(landmarks, 16, 14);
    final pinkyExtended = _isFingerExtended(landmarks, 20, 18);

    final allFingersExtended =
        indexExtended && middleExtended && ringExtended && pinkyExtended;
    if (allFingersExtended) {
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

  /// Cosine of angle between two 2D vectors.
  /// Returns 0.0 (ambiguous) if either vector is too short — avoids
  /// noise-dominated results when hand is far from camera.
  double _cosAngle(double ax, double ay, double bx, double by) {
    final magA = sqrt(ax * ax + ay * ay);
    final magB = sqrt(bx * bx + by * by);
    if (magA < 0.005 || magB < 0.005) return 0.0;
    return (ax * bx + ay * by) / (magA * magB);
  }

  /// Compute cosines at PIP and DIP joints for a finger.
  List<double> _fingerJointCosines(
      List<Landmark> landmarks, int tipIdx, int pipIdx) {
    final mcpIdx = _mcpIndices[tipIdx]!;
    final dipIdx = _dipIndices[tipIdx]!;

    final v1x = landmarks[pipIdx].x - landmarks[mcpIdx].x;
    final v1y = landmarks[pipIdx].y - landmarks[mcpIdx].y;
    final v2x = landmarks[dipIdx].x - landmarks[pipIdx].x;
    final v2y = landmarks[dipIdx].y - landmarks[pipIdx].y;
    final v3x = landmarks[tipIdx].x - landmarks[dipIdx].x;
    final v3y = landmarks[tipIdx].y - landmarks[dipIdx].y;

    return [_cosAngle(v1x, v1y, v2x, v2y), _cosAngle(v2x, v2y, v3x, v3y)];
  }

  /// Finger is clearly EXTENDED: both joints mostly straight (angle < ~75°).
  bool _isFingerExtended(List<Landmark> landmarks, int tipIdx, int pipIdx) {
    final cos = _fingerJointCosines(landmarks, tipIdx, pipIdx);
    return cos[0] > _extendedCosThreshold && cos[1] > _extendedCosThreshold;
  }

  /// Finger is clearly FOLDED: at least one joint significantly bent (angle > ~110°).
  bool _isFingerFolded(List<Landmark> landmarks, int tipIdx, int pipIdx) {
    final cos = _fingerJointCosines(landmarks, tipIdx, pipIdx);
    return cos[0] < _foldedCosThreshold || cos[1] < _foldedCosThreshold;
  }

  // Thumb is extended when TIP is farther from WRIST than MCP.
  bool _isThumbExtended(List<Landmark> landmarks) {
    final tipToWrist = _distance(landmarks[4], landmarks[0]);
    final mcpToWrist = _distance(landmarks[2], landmarks[0]);
    if (tipToWrist < 0.03 || mcpToWrist < 0.02) return false;
    return tipToWrist > mcpToWrist * 1.2;
  }

  _ThumbDirection _getThumbDirection(List<Landmark> landmarks) {
    final dy = (landmarks[4].y - landmarks[2].y).abs();
    if (dy < 0.01) return _ThumbDirection.neutral;
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
