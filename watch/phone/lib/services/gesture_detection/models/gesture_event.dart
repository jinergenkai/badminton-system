import 'package:hand_landmarker/hand_landmarker.dart';
import 'hand_gesture.dart';

class GestureEvent {
  final HandGesture gesture;
  final DateTime timestamp;
  final double confidence;

  GestureEvent({
    required this.gesture,
    required this.timestamp,
    this.confidence = 0.0,
  });
}

class GestureFrameData {
  final List<Hand> hands;
  final HandGesture classifiedGesture;
  final double stability;
  final double holdProgress;
  final double fps;
  final Map<String, bool> fingerStates;

  const GestureFrameData({
    required this.hands,
    required this.classifiedGesture,
    required this.stability,
    required this.holdProgress,
    required this.fps,
    required this.fingerStates,
  });
}
