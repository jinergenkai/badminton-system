import 'dart:async';

import 'package:flutter/material.dart';
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

  /// Whether the preview is fed right now (the board keeps it dark unless
  /// its preview is on screen).
  bool previewActive;
  ClockInfo Function() clock;

  CameraRig({
    required this.role,
    required this.lens,
    required this.overlay,
    required this.preview,
    this.previewActive = true,
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

  /// What the burned-in score shows. Follows the board's events whether or
  /// not a file is being recorded, so the preview shows it before Start.
  int _liveA = 0, _liveB = 0;
  bool _liveShow = false;

  Future<bool> open() async {
    _events ??= platform.events.listen(_onEvent);
    WidgetsBinding.instance.addObserver(this);
    session.onChange = () => tick.value++;
    try {
      final p = await platform.requestPermissions();
      if (p['camera'] != true) {
        error.value = 'Camera permission denied';
        return false;
      }
      if (p['audio'] != true) error.value = 'No microphone permission: video without sound';
      textureId.value = await platform.open(
          lens: lens, preview: preview, previewActive: previewActive, overlay: overlay);
      _pushOverlay();
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

  /// A match event (from the board over Wi-Fi, or straight from this
  /// board): updates the burned-in score.
  void live(Map<String, dynamic> m) {
    int? n(dynamic v) => v is num ? v.toInt() : null;
    switch (m['type']) {
      case 'match_start':
      case 'point':
      case 'undo':
        _liveA = n(m['scoreA']) ?? (m['type'] == 'match_start' ? 0 : _liveA);
        _liveB = n(m['scoreB']) ?? (m['type'] == 'match_start' ? 0 : _liveB);
        _liveShow = true;
        break;
      case 'match_end':
        // The final score stays up until the next set starts.
        _liveA = n(m['scoreA']) ?? _liveA;
        _liveB = n(m['scoreB']) ?? _liveB;
        break;
    }
    _pushOverlay();
  }

  void _pushOverlay() {
    if (!overlay || !opened.value) return;
    platform.setOverlay(_liveA, _liveB, _liveShow).catchError((_) {});
  }

  Future<void> setPreviewActive(bool on) async {
    previewActive = on;
    if (opened.value) await platform.setPreviewActive(on).catchError((_) {});
  }

  /// Seconds into the current file.
  int get fileSeconds {
    final w = session.current?.startWall;
    if (w == null) return 0;
    return ((DateTime.now().millisecondsSinceEpoch - w) / 1000).floor();
  }
}

/// The camera's preview cropped to what is recorded: the 16:9 centre of the
/// sensor's (usually 4:3) frame. The burned-in score then sits in the
/// corner here exactly as it does in the file.
class CameraPreviewBox extends StatelessWidget {
  final CameraRig rig;
  const CameraPreviewBox(this.rig, {super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
        final id = rig.textureId.value;
        if (id == null) {
          return AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: Text(rig.error.value.isEmpty ? 'Opening camera…' : rig.error.value,
                  style: const TextStyle(color: Colors.white38)),
            ),
          );
        }
        final a = rig.previewAspect.value;
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 1000 * a,
                height: 1000,
                child: RotatedBox(quarterTurns: rig.previewTurns.value, child: Texture(textureId: id)),
              ),
            ),
          ),
        );
      });
}
