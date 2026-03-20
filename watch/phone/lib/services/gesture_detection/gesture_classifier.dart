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

  HandGesture classify(List<Landmark> landmarks) {
    if (landmarks.length < 21) return HandGesture.none;

    final thumbExtended = _isThumbExtended(landmarks);
    final indexExtended = _isFingerExtended(landmarks, 8, 6);
    final middleExtended = _isFingerExtended(landmarks, 12, 10);
    final ringExtended = _isFingerExtended(landmarks, 16, 14);
    final pinkyExtended = _isFingerExtended(landmarks, 20, 18);

    final allFingersFolded =
        !indexExtended && !middleExtended && !ringExtended && !pinkyExtended;

    // Thumbs Up / Down: thumb extended + 4 fingers folded
    if (thumbExtended && allFingersFolded) {
      final direction = _getThumbDirection(landmarks);
      if (direction == _ThumbDirection.up) return HandGesture.thumbsUp;
      if (direction == _ThumbDirection.down) return HandGesture.thumbsDown;
    }

    // Open Palm: 4 fingers extended (thumb doesn't matter)
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

  // Finger is extended when both joints (MCP→PIP and PIP→TIP) continue
  // in roughly the same direction (dot product > 0 = angle < 90°).
  // Direction-agnostic — works regardless of hand orientation.
  bool _isFingerExtended(List<Landmark> landmarks, int tipIdx, int pipIdx) {
    final mcpIdx = _mcpIndices[tipIdx]!;
    final dipIdx = _dipIndices[tipIdx]!;

    // Vector MCP → PIP (first bone direction)
    final v1x = landmarks[pipIdx].x - landmarks[mcpIdx].x;
    final v1y = landmarks[pipIdx].y - landmarks[mcpIdx].y;

    // Vector PIP → DIP (second bone direction)
    final v2x = landmarks[dipIdx].x - landmarks[pipIdx].x;
    final v2y = landmarks[dipIdx].y - landmarks[pipIdx].y;

    // Vector DIP → TIP (third bone direction)
    final v3x = landmarks[tipIdx].x - landmarks[dipIdx].x;
    final v3y = landmarks[tipIdx].y - landmarks[dipIdx].y;

    // If any bone segment is too short (landmarks nearly overlapping),
    // noise makes direction unreliable → treat as folded.
    const minLen2 = 0.001; // squared min length (~3% of normalized space)
    final len1sq = v1x * v1x + v1y * v1y;
    final len2sq = v2x * v2x + v2y * v2y;
    final len3sq = v3x * v3x + v3y * v3y;
    if (len1sq < minLen2 || len2sq < minLen2 || len3sq < minLen2) return false;

    // Both joints must not bend back (dot > 0)
    final dotPip = v1x * v2x + v1y * v2y;
    final dotDip = v2x * v3x + v2y * v3y;

    return dotPip > 0 && dotDip > 0;
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
