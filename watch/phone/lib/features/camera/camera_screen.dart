import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../views/ui_kit.dart';
import 'camera_link_service.dart';
import 'camera_platform.dart';
import 'camera_server.dart';
import 'recording_session.dart';

/// Corner camera: records continuously, one file per set, driven by the
/// tablet's match events (docs/camera-recording-requirements.md §3).
class CameraController extends GetxController {
  final platform = CameraPlatform();
  late final RecordingSession session;
  late final CameraServer server;

  final RxnInt textureId = RxnInt();
  final RxBool showPreview = true.obs;
  final RxBool recording = false.obs;
  final RxString error = ''.obs;
  final RxMap<String, dynamic> device = <String, dynamic>{}.obs;
  final RxDouble previewAspect = (16 / 9).obs;
  final RxInt previewTurns = 0.obs; // quarter turns to show the sensor upright
  final RxInt tick = 0.obs; // redraw clock-driven text

  /// Below this, recording stops: 2 GB.
  static const minFreeBytes = 2 * 1024 * 1024 * 1024;

  StreamSubscription? _events;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    session = RecordingSession(
      sink: platform,
      now: () => DateTime.now().millisecondsSinceEpoch,
      clock: () => server.clock,
    );
    server = CameraServer(session, _statusForTablet);
    session.onChange = () => tick.value++;
    server.onChange = () => tick.value++;
    _events = platform.events.listen(_onEvent);
    _open();
  }

  Future<void> _open() async {
    CameraLinkService.localServerRunning = true;
    WakelockPlus.enable();
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    try {
      final p = await platform.requestPermissions();
      if (p['camera'] != true) {
        error.value = 'Camera permission denied';
        return;
      }
      if (p['audio'] != true) error.value = 'No microphone permission: video without sound';
      textureId.value = await platform.open();
      session.deviceInfo['device'] = (await platform.deviceStatus())['model'];
      await server.start();
    } catch (e) {
      error.value = 'Camera: $e';
    }
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _every10s());
    _every10s();
  }

  Future<void> _every10s() async {
    try {
      device.assignAll(await platform.deviceStatus());
    } catch (_) {}
    tick.value++;
    if (recording.value) {
      final free = (device['freeBytes'] as num?)?.toInt() ?? minFreeBytes;
      if (free < minFreeBytes) {
        error.value = 'Storage under 2 GB: recording stopped';
        await stop();
        return;
      }
      await session.tick();
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'startWall':
        session.onStartWall((e['wall'] as num).toInt());
        break;
      case 'started':
        session.onStartWall((e['wall'] as num).toInt());
        break;
      case 'finalized':
        session.onFinalized(e['uri'] as String?, error: e['error'] as String?);
        break;
      case 'preview':
        final w = (e['width'] as num).toDouble(), h = (e['height'] as num).toDouble();
        final rot = ((e['rotation'] as num?)?.toInt() ?? 0) ~/ 90;
        previewTurns.value = rot;
        // Width over height as shown, after turning.
        if (w > 0 && h > 0) previewAspect.value = rot.isOdd ? h / w : w / h;
        break;
    }
    tick.value++;
  }

  Future<void> start() async {
    if (textureId.value == null) return;
    error.value = '';
    await session.begin();
    recording.value = true;
    // Less heat and battery while it runs; the preview can be hidden too.
    await platform.setDim(true);
  }

  Future<void> stop() async {
    await session.end();
    recording.value = false;
    await platform.setDim(false);
  }

  Future<Map<String, dynamic>> _statusForTablet() async {
    final free = (device['freeBytes'] as num?)?.toDouble() ?? 0;
    return {
      'recording': recording.value,
      'file': session.current?.base,
      'freeGB': (free / 1e9 * 10).round() / 10,
      'battery': device['battery'],
      'tempC': device['tempC'],
    };
  }

  /// Seconds into the current file.
  int get fileSeconds {
    final w = session.current?.startWall;
    if (w == null) return 0;
    return ((DateTime.now().millisecondsSinceEpoch - w) / 1000).floor();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _events?.cancel();
    if (recording.value) session.end();
    server.stop();
    platform.close();
    platform.setDim(false);
    CameraLinkService.localServerRunning = false;
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.onClose();
  }
}

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(CameraController());
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (c.recording.value &&
            !await uiConfirm(context,
                title: 'Stop recording?', message: 'The current file is closed and saved.', confirm: 'Stop')) {
          return;
        }
        Get.delete<CameraController>();
        Get.back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 3, child: _preview(c)),
              SizedBox(width: 300, child: _panel(context, c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(CameraController c) => Obx(() {
        final id = c.textureId.value;
        if (id == null || !c.showPreview.value) {
          return Center(
            child: Text(id == null ? 'Opening camera…' : 'Preview hidden',
                style: const TextStyle(color: Colors.white38)),
          );
        }
        return Center(
          child: AspectRatio(
            aspectRatio: c.previewAspect.value,
            child: RotatedBox(quarterTurns: c.previewTurns.value, child: Texture(textureId: id)),
          ),
        );
      });

  Widget _panel(BuildContext context, CameraController c) => Container(
        color: Ui.bg,
        padding: const EdgeInsets.all(16),
        child: Obx(() {
          c.tick.value;
          final rec = c.recording.value;
          final s = c.session;
          final m = s.current?.match;
          final clock = c.server.clock;
          final d = c.device;
          final secs = c.fileSeconds;
          String mmss(int v) => '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
          final free = ((d['freeBytes'] as num?)?.toDouble() ?? 0) / 1e9;
          return ListView(
            children: [
              Row(children: [
                Icon(Icons.circle, size: 14, color: rec ? Colors.redAccent : Colors.white24),
                const SizedBox(width: 8),
                Text(rec ? 'Recording  ${mmss(secs)}' : 'Not recording',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              _row(Icons.tablet_android, c.server.connected
                  ? 'Tablet linked · clock ${clock.offsetMs} ms (rtt ${clock.rttMs})'
                  : 'Tablet not linked'),
              _row(Icons.sports_tennis,
                  m == null ? 'No set in this file' : 'Set ${m.scoreA} - ${m.scoreB}${m.ended ? ' (ended)' : ''}'),
              _row(Icons.sd_storage, '${free.toStringAsFixed(1)} GB free'),
              _row(Icons.battery_std,
                  '${d['battery'] ?? '?'}%${d['charging'] == true ? ' charging' : ''} · ${d['tempC'] ?? '?'}°C'),
              _row(Icons.movie, '${s.finished.length} file(s) saved · Download/Godminton'),
              if (c.error.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(c.error.value, style: const TextStyle(color: Colors.orangeAccent)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: rec ? Colors.redAccent : Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52)),
                onPressed: c.textureId.value == null ? null : (rec ? c.stop : c.start),
                icon: Icon(rec ? Icons.stop : Icons.fiber_manual_record),
                label: Text(rec ? 'Stop' : 'Start recording'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70, minimumSize: const Size.fromHeight(44)),
                onPressed: rec ? c.session.split : null,
                icon: const Icon(Icons.content_cut),
                label: const Text('Split file now'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: () => c.showPreview.toggle(),
                    child: Text(c.showPreview.value ? 'Hide preview' : 'Show preview'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: c.platform.openHotspotSettings,
                    child: const Text('Hotspot'),
                  ),
                ),
              ]),
            ],
          );
        }),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ]),
      );
}
