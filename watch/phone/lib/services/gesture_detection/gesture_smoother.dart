import 'dart:collection';
import 'models/hand_gesture.dart';
import 'models/gesture_event.dart';

class GestureSmoother {
  static const int windowSize = 10;
  static const double stabilityThreshold = 0.7;
  static const Duration holdDuration = Duration(seconds: 2);
  static const Duration holdDurationUndo = Duration(milliseconds: 2500);
  static const Duration cooldownAfterTrigger = Duration(seconds: 3);

  final Queue<HandGesture> _window = Queue();
  HandGesture? _currentStableGesture;
  DateTime? _holdStartTime;
  DateTime? _lastTriggerTime;

  /// Call each frame. Returns a GestureEvent when a gesture is confirmed.
  GestureEvent? update(HandGesture detected) {
    _window.addLast(detected);
    if (_window.length > windowSize) _window.removeFirst();

    final dominant = _getDominantGesture();

    // Cooldown check — suppress input after a trigger
    if (_lastTriggerTime != null &&
        DateTime.now().difference(_lastTriggerTime!) < cooldownAfterTrigger) {
      return null;
    }

    if (dominant != null && dominant != HandGesture.none) {
      if (dominant == _currentStableGesture) {
        final requiredHold = (dominant == HandGesture.openPalm)
            ? holdDurationUndo
            : holdDuration;
        if (_holdStartTime != null &&
            DateTime.now().difference(_holdStartTime!) >= requiredHold) {
          _lastTriggerTime = DateTime.now();
          final event = GestureEvent(
            gesture: dominant,
            timestamp: DateTime.now(),
            confidence: stability,
          );
          _reset();
          return event;
        }
      } else {
        // New stable gesture — start hold timer
        _currentStableGesture = dominant;
        _holdStartTime = DateTime.now();
      }
    } else {
      _reset();
    }

    return null;
  }

  /// Progress 0.0–1.0 of current hold timer (for UI ring indicator)
  double get holdProgress {
    if (_currentStableGesture == null || _holdStartTime == null) return 0.0;
    final requiredHold = (_currentStableGesture == HandGesture.openPalm)
        ? holdDurationUndo
        : holdDuration;
    final elapsed = DateTime.now().difference(_holdStartTime!);
    return (elapsed.inMilliseconds / requiredHold.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// Fraction of frames in window matching dominant gesture
  double get stability {
    if (_window.isEmpty) return 0.0;
    final dominant = _getDominantGesture();
    if (dominant == null) return 0.0;
    final count = _window.where((g) => g == dominant).length;
    return count / _window.length;
  }

  HandGesture? get currentGesture => _currentStableGesture;

  bool get isInCooldown {
    if (_lastTriggerTime == null) return false;
    return DateTime.now().difference(_lastTriggerTime!) < cooldownAfterTrigger;
  }

  HandGesture? _getDominantGesture() {
    if (_window.isEmpty) return null;
    final counts = <HandGesture, int>{};
    for (final g in _window) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
    HandGesture? dominant;
    int maxCount = 0;
    counts.forEach((gesture, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = gesture;
      }
    });
    if (dominant == null) return null;
    return (maxCount / _window.length) >= stabilityThreshold ? dominant : null;
  }

  void _reset() {
    _currentStableGesture = null;
    _holdStartTime = null;
  }

  void resetCooldown() {
    _lastTriggerTime = null;
    _reset();
  }
}
