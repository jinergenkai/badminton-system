import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/sync_service.dart';
import 'ui_kit.dart';

/// Đồng bộ với backend badminton-system: nhập địa chỉ + token, kéo danh bạ,
/// đẩy trận lên để tính ranking.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final TextEditingController _base;
  late final TextEditingController _token;

  @override
  void initState() {
    super.initState();
    final s = SyncService.to;
    _base = TextEditingController(text: s.baseUrl.value);
    _token = TextEditingController(text: s.token.value);
  }

  @override
  void dispose() {
    _base.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    final s = SyncService.to;
    await s.saveConfig(_base.text, _token.text);
    try {
      await fn();
    } catch (e) {
      s.lastResult.value = 'Lỗi: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SyncService.to;
    return UiPage(
      title: 'Đồng bộ ranking',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const UiSection('Backend'),
          _field(_base, 'Địa chỉ backend', 'https://caulongdata.app.huynhhanh.com'),
          const SizedBox(height: 12),
          _field(_token, 'API_TOKEN', 'dán token từ .env.deploy', obscure: true),
          const SizedBox(height: 20),
          const UiSection('Hành động'),
          Obx(() => Column(
                children: [
                  _btn(
                    icon: Icons.download_rounded,
                    label: 'Kéo danh bạ (id gốc sổ tiền)',
                    onTap: s.busy.value ? null : () => _run(s.pullRoster),
                  ),
                  const SizedBox(height: 10),
                  _btn(
                    icon: Icons.upload_rounded,
                    label: 'Đẩy trận đã xong lên',
                    onTap: s.busy.value ? null : () => _run(s.pushMatches),
                  ),
                ],
              )),
          const SizedBox(height: 20),
          Obx(() => s.busy.value
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : (s.lastResult.value == null
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(Ui.radius),
                        border: Border.all(color: Ui.line),
                      ),
                      child: Text(s.lastResult.value!,
                          style: const TextStyle(fontSize: 13.5, height: 1.4)),
                    ))),
          const SizedBox(height: 16),
          const Text(
            'Chỉ đẩy trận đã kết thúc và đủ 2v2 có tên. Đẩy lại không tạo trùng (idempotent theo id trận).',
            style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Ui.radius),
              borderSide: BorderSide(color: Ui.line),
            ),
          ),
        ),
      ],
    );
  }

  Widget _btn({required IconData icon, required String label, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
