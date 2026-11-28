import 'dart:convert';

/// What the corner phone's QR code says: "I am a camera, reach me at one of
/// these addresses". The board scans it instead of anyone typing an IP.
///
///   {"godminton":"camera","hosts":["192.168.43.1"],"port":8765}
class CameraQr {
  static String encode(List<String> hosts, int port) =>
      jsonEncode({'godminton': 'camera', 'hosts': hosts, 'port': port});

  /// The camera's addresses from a scanned code; null when it is not ours.
  static List<String>? hosts(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['godminton'] != 'camera') return null;
      final list = [
        for (final h in (m['hosts'] as List? ?? const []))
          if (h is String && _ipv4.hasMatch(h)) h
      ];
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }

  /// The address to use: one on the same /24 as this device (same hotspot or
  /// Wi-Fi), else the first one listed.
  static String pick(List<String> hosts, List<String> mine) {
    String net(String a) => a.substring(0, a.lastIndexOf('.'));
    final nets = {for (final a in mine) net(a)};
    return hosts.firstWhere((h) => nets.contains(net(h)), orElse: () => hosts.first);
  }

  static final _ipv4 = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
}
