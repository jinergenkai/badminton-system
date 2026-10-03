import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/camera/camera_link_service.dart';
import '../features/camera/camera_screen.dart';
import 'ui_kit.dart';

/// Tools that are not part of scoring: the corner camera for now.
class UtilityScreen extends StatelessWidget {
  const UtilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final link = CameraLinkService.maybe;
    return UiPage(
      title: 'Utility',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const UiSection('Corner camera'),
          UiPanel(
            child: ListTile(
              leading: const Icon(Icons.videocam, color: Colors.redAccent, size: 32),
              title: const Text('Use this phone as the corner camera'),
              subtitle: const Text(
                  'Records the court, one file per set, from the board\'s start and end. '
                  'Turn on this phone\'s hotspot and join it from the tablet.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.to(() => const CameraScreen()),
            ),
          ),
          if (link != null) ...[
            const SizedBox(height: 16),
            const UiSection('Link from this board'),
            UiPanel(child: _LinkPanel(link)),
          ],
        ],
      ),
    );
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
            final text = !l.connected.value
                ? 'Not linked${l.host.value.isEmpty ? '' : ' (trying ${l.host.value})'}'
                : 'Linked to ${l.host.value} · '
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
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Camera address',
              hintText: 'empty = the hotspot (automatic)',
            ),
            onSubmitted: l.setHostOverride,
          ),
        ],
      ),
    );
  }
}
