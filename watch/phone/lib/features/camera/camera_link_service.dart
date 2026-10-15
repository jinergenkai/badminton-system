import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera_beacon.dart';
import 'camera_platform.dart';
import 'camera_server.dart';

/// Tablet side of the corner-camera link: sends match events to the phone's
/// [CameraServer] and shows its REC status on the board.
///
/// Never in the way of the band → board path: every send only queues, and
/// the socket lives on its own timers. Not connected = events wait in the
/// queue (with their original time) and go out on reconnect; the phone acks
/// each one and drops repeats by seq.
class CameraLinkService extends GetxService {
  static const _prefHost = 'camera_host';

  /// Manual address; empty = automatic: the camera that announces itself on
  /// the network (hotspot or shared Wi-Fi), else the Wi-Fi gateway (on the
  /// phone's hotspot, that is the phone).
  final RxString hostOverride = ''.obs;
  final RxBool connected = false.obs;
  final RxString host = ''.obs;

  /// How [host] was found: 'manual' | 'found' | 'gateway'.
  final RxString via = ''.obs;
  final _beacon = BeaconListener();

  /// Last status from the phone: recording, file, freeGB, battery, tempC.
  final RxMap<String, dynamic> remote = <String, dynamic>{}.obs;

  bool get recording => connected.value && remote['recording'] == true;

  /// The camera asks for the set in progress (set by ScoreController).
  void Function()? onResync;

  final _queue = <Map<String, dynamic>>[];
  final String _cid = Random().nextInt(1 << 32).toRadixString(36);
  int _seq = 0;
  WebSocket? _ws;
  Timer? _retry;
  bool _connecting = false;

  static CameraLinkService? get maybe =>
      Get.isRegistered<CameraLinkService>() ? Get.find<CameraLinkService>() : null;

  Future<CameraLinkService> init() async {
    final prefs = await SharedPreferences.getInstance();
    hostOverride.value = prefs.getString(_prefHost) ?? '';
    await _beacon.start();
    _retry = Timer.periodic(const Duration(seconds: 2), (_) => _connect());
    return this;
  }

  Future<void> setHostOverride(String v) async {
    hostOverride.value = v.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHost, hostOverride.value);
    await _ws?.close();
  }

  /// Queue a match event; [t] defaults to now on this device's clock.
  void send(String type, Map<String, dynamic> fields) {
    final m = <String, dynamic>{
      'type': type,
      'cid': _cid,
      'seq': ++_seq,
      't': DateTime.now().millisecondsSinceEpoch,
      ...fields,
    };
    _queue.add(m);
    while (_queue.length > 500) {
      _queue.removeAt(0);
    }
    _write(m);
  }

  void _write(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  Future<void> _connect() async {
    if (_ws != null || _connecting) return;
    _connecting = true;
    try {
      var h = hostOverride.value;
      via.value = 'manual';
      if (h.isEmpty) {
        final found = _beacon.fresh;
        if (found != null) {
          h = found;
          via.value = 'found';
        } else {
          h = await CameraPlatform.gateway() ?? '';
          via.value = 'gateway';
        }
      }
      host.value = h;
      if (h.isEmpty) return;
      final ws = await WebSocket.connect('ws://$h:${CameraServer.port}')
          .timeout(const Duration(seconds: 2));
      _ws = ws;
      connected.value = true;
      ws.pingInterval = const Duration(seconds: 5);
      ws.add(jsonEncode({'type': 'hello', 'device': Platform.localHostname, 'appVersion': 1}));
      // Everything not yet acked, in order.
      for (final m in List.of(_queue)) {
        _write(m);
      }
      ws.listen(_onMessage, onDone: _lost, onError: (_) => _lost());
    } catch (_) {
      // Not on the hotspot, or the camera screen is not open: try again later.
    } finally {
      _connecting = false;
    }
  }

  void _lost() {
    _ws = null;
    connected.value = false;
    remote.clear();
  }

  void _onMessage(dynamic data) {
    final Map m;
    try {
      m = jsonDecode(data as String) as Map;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'ping':
        final t1 = DateTime.now().millisecondsSinceEpoch;
        _write({'type': 'pong', 't0': m['t0'], 't1': t1, 't2': DateTime.now().millisecondsSinceEpoch});
        break;
      case 'ack':
        _queue.removeWhere((e) => e['seq'] == m['seq']);
        break;
      case 'status':
        remote.assignAll(m.map((k, v) => MapEntry('$k', v)));
        break;
      case 'resync':
        onResync?.call();
        break;
    }
  }

  @override
  void onClose() {
    _retry?.cancel();
    _beacon.stop();
    _ws?.close();
    super.onClose();
  }
}
