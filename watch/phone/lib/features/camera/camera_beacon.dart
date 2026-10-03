import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'camera_server.dart';

/// "A camera is here": the corner phone says so on UDP 8766 every 2 s, and
/// the board connects to whoever said it. Works the same on the phone's
/// hotspot and on a shared Wi-Fi, so nobody types an address.
class CameraBeacon {
  static const port = 8766;

  RawDatagramSocket? _socket;
  Timer? _timer;
  String name = 'camera';

  Future<void> start() async {
    _socket ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      ..broadcastEnabled = true;
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _send());
    _send();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> _send() async {
    final s = _socket;
    if (s == null) return;
    final data = utf8.encode(jsonEncode({'godminton': 'camera', 'port': CameraServer.port, 'name': name}));
    // Each interface's own broadcast (hotspot host has no default route, so
    // 255.255.255.255 may go nowhere), plus the limited broadcast.
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    for (final a in await myAddresses()) {
      final p = a.split('.');
      targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
    }
    for (final t in targets) {
      try {
        s.send(data, t, port);
      } catch (_) {}
    }
  }

  /// This device's IPv4 addresses on Wi-Fi / hotspot, for the screen and
  /// for typing into the board if discovery is blocked.
  static Future<List<String>> myAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in list)
          for (final a in i.addresses)
            if (!a.isLoopback && !i.name.startsWith('rmnet') && !i.name.startsWith('ccmni')) a.address
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Board side: remembers the last camera heard.
class BeaconListener {
  RawDatagramSocket? _socket;
  String? host;
  DateTime? at;

  String? get fresh =>
      at != null && DateTime.now().difference(at!) < const Duration(seconds: 15) ? host : null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, CameraBeacon.port, reuseAddress: true);
      _socket!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = _socket?.receive();
        if (dg == null) return;
        try {
          final m = jsonDecode(utf8.decode(dg.data)) as Map;
          if (m['godminton'] != 'camera') return;
          host = dg.address.address;
          at = DateTime.now();
        } catch (_) {}
      });
    } catch (_) {}
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}
