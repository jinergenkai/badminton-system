import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'camera_platform.dart';
import 'recording_session.dart';

/// One camera and its recording session, shared by both roles:
///   corner  the phone in camera mode (preview on screen, events over Wi-Fi)
///   front   the board recording itself (no preview, events fed locally)
///
/// Also keeps the burned-in score in step with the set, checks free space
/// every 10 s, and stops cleanly when the app goes to the background (the
/// camera is taken away then anyway) and resumes when it comes back.
class CameraRig with WidgetsBindingObserver {
  final String role;
  String lens;
  bool overlay;
  final bool preview;
  ClockInfo Function() clock;

  CameraRig({
    required this.role,
    required this.lens,
    required this.overlay,
    required this.preview,
    ClockInfo Function()? clock,
  }) : clock = clock ?? (() => const ClockInfo(0, 0, 0));

  final platform = CameraPlatform();
  late final RecordingSession session = RecordingSession(
    sink: platform,
    now: () => DateTime.now().millisecondsSinceEpoch,
    clock: () => clock(),
    deviceInfo: {'role': role},
  );

  final RxnInt textureId = RxnInt();
  final RxBool opened = false.obs;
  final RxBool recording = false.obs;
  final RxString error = ''.obs;
  final RxMap<String, dynamic> device = <String, dynamic>{}.obs;
  final RxDouble previewAspect = (16 / 9).obs;
  final RxInt previewTurns = 0.obs;
  final RxInt tick = 0.obs;

  /// Below this, recording stops: 2 GB.
  static const minFreeBytes = 2 * 1024 * 1024 * 1024;

  StreamSubscription? _events;
  Timer? _timer;
  bool _resumeOnShow = false;
  String _overlayKey = '';

  Future<bool> open() async {
    _events ??= platform.events.listen(_onEvent);
    WidgetsBinding.instance.addObserver(this);
    session.onChange = _changed;
    try {
      final p = await platform.requestPermissions();
      if (p['camera'] != true) {
        error.value = 'Camera permission denied';
        return false;
      }
      if (p['audio'] != true) error.value = 'No microphone permission: video without sound';
      textureId.value = await platform.open(lens: lens, preview: preview, overlay: overlay);
      opened.value = true;
      final st = await platform.deviceStatus();
      session.deviceInfo['device'] = st['model'];
      session.deviceInfo['lens'] = lens;
    } catch (e) {
      error.value = 'Camera: $e';
      return false;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) => _every10s());
    _every10s();
    return true;
  }

  /// Lens or overlay changed: rebind (not while recording).
  Future<void> reopen() async {
    if (recording.value) return;
    await platform.close();
    opened.value = false;
    await open();
  }

  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    if (recording.value) await stop();
    await _events?.cancel();
    _events = null;
    await platform.close();
    opened.value = false;
  }

  Future<void> start() async {
    if (!opened.value || recording.value) return;
    error.value = '';
    await session.begin();
    recording.value = true;
    _overlayKey = '';
    _changed();
  }

  Future<void> stop() async {
    if (!recording.value) return;
    await session.end();
    recording.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // The camera is unbound in the background: close the file properly.
      _resumeOnShow = recording.value;
      if (recording.value) stop();
    } else if (state == AppLifecycleState.resumed && _resumeOnShow) {
      _resumeOnShow = false;
      start();
    }
  }

  Future<void> _every10s() async {
    try {
      device.assignAll(await platform.deviceStatus());
    } catch (_) {}
    tick.value++;
    if (!recording.value) return;
    final free = (device['freeBytes'] as num?)?.toInt() ?? minFreeBytes;
    if (free < minFreeBytes) {
      error.value = 'Storage under 2 GB: recording stopped';
      await stop();
      return;
    }
    await session.tick();
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'startWall':
      case 'started':
        session.onStartWall((e['wall'] as num).toInt());
        break;
      case 'finalized':
        session.onFinalized(e['uri'] as String?, error: e['error'] as String?).catchError((_) {});
        break;
      case 'preview':
        final w = (e['width'] as num).toDouble(), h = (e['height'] as num).toDouble();
        final rot = ((e['rotation'] as num?)?.toInt() ?? 0) ~/ 90;
        previewTurns.value = rot;
        if (w > 0 && h > 0) previewAspect.value = rot.isOdd ? h / w : w / h;
        break;
    }
    tick.value++;
  }

  /// Overlay follows the set in the current file.
  void _changed() {
    tick.value++;
    if (!overlay) return;
    final m = session.current?.match;
    final key = m == null ? '-' : '${m.scoreA}:${m.scoreB}';
    if (key == _overlayKey) return;
    _overlayKey = key;
    platform.setOverlay(m?.scoreA ?? 0, m?.scoreB ?? 0, m != null).catchError((_) {});
  }

  /// Seconds into the current file.
  int get fileSeconds {
    final w = session.current?.startWall;
    if (w == null) return 0;
    return ((DateTime.now().millisecondsSinceEpoch - w) / 1000).floor();
  }
}
