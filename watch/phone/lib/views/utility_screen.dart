import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/camera/board_recorder.dart';
import '../features/camera/camera_link_service.dart';
import '../features/camera/camera_platform.dart';
import '../features/camera/camera_rig.dart';
import '../features/camera/camera_settings.dart';
import '../features/camera/video_gallery_screen.dart';
import 'ui_kit.dart';

/// Recording tools around the board: the corner camera (another phone),
/// and the board recording with its own camera.
class UtilityScreen extends StatelessWidget {
  const UtilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final link = CameraLinkService.maybe;
    final rec = BoardRecorder.maybe;
    return UiPage(
      title: 'Utility',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (link != null) ...[
            const UiSection('Corner camera'),
            UiPanel(child: _LinkPanel(link)),
            const SizedBox(height: 16),
          ],
          if (rec != null) ...[
            const UiSection('Record on this device too'),
            UiPanel(child: _BoardRecPanel(rec)),
            const SizedBox(height: 16),
          ],
          const UiSection('Saved videos'),
          UiPanel(
            child: ListTile(
              leading: const Icon(Icons.video_library, color: Colors.amber, size: 32),
              title: const Text('Videos on this device'),
              subtitle: const Text('Recorded by this device, newest first. Tap one to play it.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.to(() => const VideoGalleryScreen()),
            ),
          ),
          const SizedBox(height: 16),
          const UiSection('This device'),
          UiPanel(
            child: ListTile(
              leading: const Icon(Icons.videocam, color: Colors.redAccent, size: 32),
              title: const Text('Use this device as the corner camera'),
              subtitle: const Text(
                  'The app restarts as a camera only: no scoreboard, band, voice or music. '
                  '"Board mode" on the camera screen switches back.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _toCamera(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toCamera(BuildContext context) async {
    if (!await uiConfirm(context,
        title: 'Switch to camera mode?',
        message: 'The app restarts and opens straight on the camera.',
        confirm: 'Restart')) {
      return;
    }
    await CameraSettings.setRole(CameraSettings.camera);
    await CameraPlatform.restartApp();
  }
}

class _LinkPanel extends StatefulWidget {
  final CameraLinkService link;
  const _LinkPanel(this.link);

  @override
  State<_LinkPanel> createState() => _LinkPanelState();
}

class _LinkPanelState extends State<_LinkPanel> {
  late final TextEditingController _host = TextEditingController(text: widget.link.hostOverride.value);

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final r = l.remote;
            final how = {'found': 'found on the network', 'gateway': 'hotspot', 'manual': 'address typed'}[l.via.value] ?? '';
            final text = !l.connected.value
                ? 'Not linked${l.host.value.isEmpty ? '' : ' (trying ${l.host.value})'}'
                : 'Linked to ${l.host.value} ($how) · '
                    '${r['recording'] == true ? 'recording' : 'not recording'} · '
                    '${r['freeGB'] ?? '?'} GB free · ${r['battery'] ?? '?'}%';
            return Row(children: [
              Icon(Icons.circle,
                  size: 12,
                  color: l.recording
                      ? Colors.redAccent
                      : (l.connected.value ? Colors.greenAccent : Colors.white24)),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
            ]);
          }),
          const SizedBox(height: 12),
          const Text(
            'Two ways to connect, both automatic:\n'
            '• Hotspot: turn on the camera phone\'s hotspot, join it from this device.\n'
            '• Same Wi-Fi: both devices on one Wi-Fi; the camera announces itself.\n'
            'Then open camera mode on the phone. If it is not found (some Wi-Fi '
            'blocks announcements), type the address the camera screen shows.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Camera address',
              hintText: 'empty = automatic',
            ),
            onSubmitted: l.setHostOverride,
          ),
        ],
      ),
    );
  }
}

class _BoardRecPanel extends StatefulWidget {
  final BoardRecorder rec;
  const _BoardRecPanel(this.rec);

  @override
  State<_BoardRecPanel> createState() => _BoardRecPanelState();
}

class _BoardRecPanelState extends State<_BoardRecPanel> {
  BoardRecorder get rec => widget.rec;

  @override
  void initState() {
    super.initState();
    // The preview is fed only while this panel is on screen.
    rec.rig?.setPreviewActive(true);
  }

  @override
  void dispose() {
    rec.rig?.setPreviewActive(false);
    super.dispose();
  }

  Future<void> _enable(bool v) async {
    await rec.enable(v);
    if (v) await rec.rig?.setPreviewActive(true);
  }

  Future<void> _reconfigure() async {
    rec.on.refresh();
    await rec.reconfigure();
    await rec.rig?.setPreviewActive(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Obx(() {
        final on = rec.on.value;
        final rig = rec.rig;
        rig?.tick.value;
        final recording = rig?.recording.value ?? false;
        final err = rig?.error.value ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Record with this device's camera"),
              subtitle: Text(on
                  ? (recording
                      ? 'Recording · ${rig!.session.finished.length} file(s) saved · Download/Godminton'
                      : 'Starting…')
                  : 'One file per set, behind the scoreboard. Adds load to this device.'),
              value: on,
              onChanged: _enable,
            ),
            if (err.isNotEmpty) Text(err, style: const TextStyle(color: Colors.orangeAccent)),
            if (on && rig != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CameraPreviewBox(rig),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'front', label: Text('Front cam')),
                ButtonSegment(value: 'back', label: Text('Back cam')),
              ],
              selected: {CameraSettings.boardLens},
              onSelectionChanged: (v) async {
                await CameraSettings.setBoardLens(v.first);
                await _reconfigure();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lock focus & exposure'),
              subtitle: Text(recording && (rig?.lockOn ?? false)
                  ? (rig!.lockState.value.isEmpty ? 'locking…' : 'locked: ${rig.lockState.value}')
                  : 'Locked 2 s after recording starts'),
              value: CameraSettings.lock,
              onChanged: (v) async {
                await CameraSettings.setLock(v);
                await rec.rig?.setLockOn(v);
                rec.on.refresh();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Score on video'),
              subtitle: const Text('Costs this device about a fifth of a CPU core'),
              value: CameraSettings.boardOverlay,
              onChanged: (v) async {
                await CameraSettings.setBoardOverlay(v);
                await _reconfigure();
              },
            ),
          ],
        );
      }),
    );
  }
}
