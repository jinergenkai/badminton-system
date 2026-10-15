import 'dart:async';

import 'package:flutter/foundation.dart';

/// A looping 0..1 phase that advances [fps] times a second.
///
/// Used instead of a repeating AnimationController for effects that run for
/// minutes: a controller redraws at the display rate (60/s) — on the cheap
/// tablet that was ~70% CPU for a strobe nobody watches frame by frame.
/// Here only [fps] frames a second are drawn. Stopped, it draws nothing.
class FrameClock extends ChangeNotifier {
  Duration period;
  int fps;

  /// 0→1→0 over one [period] (like repeat(reverse: true) over half of it).
  final bool reverse;

  double value = 0;
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();

  FrameClock({required this.period, required this.fps, this.reverse = false});

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _sw.start();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
  }

  /// Takes effect at once while running.
  void configure({Duration? period, int? fps}) {
    this.period = period ?? this.period;
    final changed = fps != null && fps != this.fps;
    this.fps = fps ?? this.fps;
    if (changed && _timer != null) {
      _timer!.cancel();
      _schedule();
    }
  }

  void _schedule() {
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps.clamp(1, 60)), (_) {
      final p = period.inMicroseconds;
      final t = (_sw.elapsedMicroseconds % p) / p;
      value = reverse ? (t < 0.5 ? t * 2 : 2 - t * 2) : t;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
