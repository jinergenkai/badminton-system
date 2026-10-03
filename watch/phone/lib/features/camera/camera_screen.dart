import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../views/ui_kit.dart';
import 'camera_beacon.dart';
import 'camera_platform.dart';
import 'camera_rig.dart';
import 'camera_server.dart';
import 'camera_settings.dart';
import 'video_gallery_screen.dart';

/// Camera mode: this device is the corner camera and nothing else. It
/// records continuously, one file per set, from the board's events
/// (docs/camera-recording-requirements.md §3).
class CornerCameraController extends GetxController {
  late final CameraRig rig;
  late final CameraServer server;
  final beacon = CameraBeacon();
  final RxList<String> addresses = <String>[].obs;
  Timer? _addr;

  @override
  void onInit() {
    super.onInit();
    rig = CameraRig(
      role: 'corner',
      lens: CameraSettings.cornerLens,
      overlay: CameraSettings.overlay,
      preview: true,
      quality: CameraSettings.cornerQuality,
    )
      ..lockOn = CameraSettings.lock
      ..focus = CameraSettings.focus;
    server = CameraServer(rig.session, _statusForBoard);
    rig.clock = () => server.clock;
    server.onEvent = rig.live;
    server.onChange = () => rig.tick.value++;
    _start();
  }

  Future<void> _start() async {
    WakelockPlus.enable();
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await rig.open();
    beacon.name = '${rig.session.deviceInfo['device'] ?? 'camera'}';
    try {
      await server.start();
      await beacon.start();
    } catch (e) {
      rig.error.value = 'Network: $e';
    }
    _refreshAddresses();
    _addr = Timer.periodic(const Duration(seconds: 10), (_) => _refreshAddresses());
  }

  Future<void> _refreshAddresses() async => addresses.assignAll(await CameraBeacon.myAddresses());

  Future<void> start() async {
    await rig.start();
    server.resync();
    // Less heat and battery while it runs; the preview can be hidden too.
    await rig.platform.setDim(true);
  }

  Future<void> stop() async {
    await rig.stop();
    await rig.platform.setDim(false);
  }

  Future<void> setLens(String v) async {
    await CameraSettings.setCornerLens(v);
    rig.lens = v;
    await rig.reopen();
  }

  Future<void> setLock(bool v) async {
    await CameraSettings.setLock(v);
    await rig.setLockOn(v);
    rig.tick.value++;
  }

  Future<void> setFocus(String v) async {
    await CameraSettings.setFocus(v);
    await rig.setFocus(v);
    rig.tick.value++;
  }

  Future<void> setQuality(String v) async {
    await CameraSettings.setCornerQuality(v);
    rig.quality = v;
    await rig.reopen();
  }

  Future<void> setOverlay(bool v) async {
    await CameraSettings.setOverlay(v);
    rig.overlay = v;
    await rig.reopen();
  }

  Future<Map<String, dynamic>> _statusForBoard() async {
    final free = (rig.device['freeBytes'] as num?)?.toDouble() ?? 0;
    return {
      'recording': rig.recording.value,
      'file': rig.session.current?.base,
      'freeGB': (free / 1e9 * 10).round() / 10,
      'battery': rig.device['battery'],
      'tempC': rig.device['tempC'],
    };
  }

  @override
  void onClose() {
    _addr?.cancel();
    beacon.stop();
    server.stop();
    rig.close();
    rig.platform.setDim(false);
    WakelockPlus.disable();
    super.onClose();
  }
}

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(CornerCameraController());
    final rig = c.rig;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (rig.recording.value &&
            !await uiConfirm(context,
                title: 'Stop recording?', message: 'The current file is closed and saved.', confirm: 'Stop')) {
          return;
        }
        await c.stop();
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 3, child: Center(child: CameraPreviewBox(rig))),
              SizedBox(width: 320, child: _panel(context, c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, CornerCameraController c) => Container(
        color: Ui.bg,
        padding: const EdgeInsets.all(16),
        child: Obx(() {
          final rig = c.rig;
          rig.tick.value;
          final rec = rig.recording.value;
          final s = rig.session;
          final m = s.current?.match;
          final clock = c.server.clock;
          final d = rig.device;
          String mmss(int v) => '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
          final free = ((d['freeBytes'] as num?)?.toDouble() ?? 0) / 1e9;
          final addr = c.addresses.isEmpty ? 'no network' : c.addresses.join(', ');
          return ListView(
            children: [
              Row(children: [
                Icon(Icons.circle, size: 14, color: rec ? Colors.redAccent : Colors.white24),
                const SizedBox(width: 8),
                Text(rec ? 'Recording  ${mmss(rig.fileSeconds)}' : 'Not recording',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              _row(Icons.tablet_android, c.server.connected
                  ? 'Board linked · clock ${clock.offsetMs} ms (rtt ${clock.rttMs})'
                  : 'Board not linked · this phone: $addr'),
              _row(Icons.sports_tennis,
                  m == null ? 'No set in this file' : 'Set ${m.scoreA} - ${m.scoreB}${m.ended ? ' (ended)' : ''}'),
              _row(Icons.sd_storage, '${free.toStringAsFixed(1)} GB free'),
              _row(Icons.battery_std,
                  '${d['battery'] ?? '?'}%${d['charging'] == true ? ' charging' : ''} · ${d['tempC'] ?? '?'}°C'),
              _row(Icons.movie,
                  '${s.finished.length} file(s) saved${s.discarded > 0 ? ', ${s.discarded} under 30 s dropped' : ''} · Download/Godminton'),
              if (rig.error.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(rig.error.value, style: const TextStyle(color: Colors.orangeAccent)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: rec ? Colors.redAccent : Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52)),
                onPressed: !rig.opened.value ? null : (rec ? c.stop : c.start),
                icon: Icon(rec ? Icons.stop : Icons.fiber_manual_record),
                label: Text(rec ? 'Stop' : 'Start recording'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: _outline,
                onPressed: rec ? s.split : null,
                icon: const Icon(Icons.content_cut),
                label: const Text('Split file now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: _outline,
                onPressed: () => Get.to(() => const VideoGalleryScreen()),
                icon: const Icon(Icons.video_library),
                label: Text('Videos (${s.finished.length} new)'),
              ),
              const SizedBox(height: 16),
              // Settings: only while not recording (they rebind the camera).
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'back', label: Text('Back cam')),
                  ButtonSegment(value: 'front', label: Text('Front cam')),
                ],
                selected: {rig.lens},
                onSelectionChanged: rec ? null : (v) => c.setLens(v.first),
              ),
              const SizedBox(height: 8),
              CameraOptions(
                rig: rig,
                recording: rec,
                quality: rig.quality,
                onFocus: c.setFocus,
                onLock: c.setLock,
                onQuality: c.setQuality,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Score on video', style: TextStyle(color: Colors.white70)),
                value: rig.overlay,
                onChanged: rec ? null : c.setOverlay,
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: _outline,
                    onPressed: c.rig.platform.openHotspotSettings,
                    child: const Text('Hotspot'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: _outline,
                    onPressed: rec ? null : () => _toBoard(context),
                    child: const Text('Board mode'),
                  ),
                ),
              ]),
            ],
          );
        }),
      );

  static final _outline = OutlinedButton.styleFrom(
      foregroundColor: Colors.white70, minimumSize: const Size.fromHeight(44));

  Future<void> _toBoard(BuildContext context) async {
    if (!await uiConfirm(context,
        title: 'Use this device as the board?',
        message: 'The app restarts as the scoreboard.',
        confirm: 'Restart')) {
      return;
    }
    await CameraSettings.setRole(CameraSettings.board);
    await CameraPlatform.restartApp();
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ]),
      );
}
