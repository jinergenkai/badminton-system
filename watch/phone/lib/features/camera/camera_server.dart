import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'recording_session.dart';

/// WebSocket server on the corner phone (port 8765). The tablet connects as
/// the only client and sends match events; the server answers each with an
/// ack, keeps the clock offset, and pushes a status every 5 s.
///
/// Clock: the server pings (its own t0), the tablet answers with its t1/t2,
/// the reply lands at t3. offset (tablet - phone) = ((t1-t0)+(t2-t3))/2,
/// median of the last 5. Every tablet `t` becomes phone time as t - offset.
class CameraServer {
  static const port = 8765;

  final RecordingSession session;
  final Future<Map<String, dynamic>> Function() status;

  CameraServer(this.session, this.status);

  HttpServer? _http;
  WebSocket? _ws;
  Timer? _ping;
  Timer? _status;
  final _offsets = <int>[];
  final _rtts = <int>[];
  final _seen = <String>{};

  /// Shown on the camera screen.
  String? clientName;
  bool get connected => _ws != null;
  void Function()? onChange;

  ClockInfo get clock {
    if (_offsets.isEmpty) return const ClockInfo(0, 0, 0);
    final o = [..._offsets]..sort();
    final r = [..._rtts]..sort();
    return ClockInfo(o[o.length ~/ 2], o.length, r[r.length ~/ 2]);
  }

  Future<void> start() async {
    if (_http != null) return;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _http!.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('godminton camera')
          ..close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      _attach(ws);
    });
    _status = Timer.periodic(const Duration(seconds: 5), (_) => _sendStatus());
  }

  Future<void> stop() async {
    _ping?.cancel();
    _status?.cancel();
    await _ws?.close();
    _ws = null;
    await _http?.close(force: true);
    _http = null;
  }

  void _attach(WebSocket ws) {
    // One tablet: a new connection replaces the old one.
    _ws?.close();
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 5);
    session.linkUp();
    onChange?.call();
    // Five quick pings for a first offset, then one every 10 s.
    var quick = 0;
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(milliseconds: 400), (t) {
      _sendPing();
      if (++quick >= 5) {
        t.cancel();
        _ping = Timer.periodic(const Duration(seconds: 10), (_) => _sendPing());
      }
    });
    ws.listen((data) => _onMessage(data), onDone: () {
      if (_ws == ws) {
        _ws = null;
        _ping?.cancel();
        session.linkDown();
        onChange?.call();
      }
    }, onError: (_) {});
    _sendStatus();
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  void _sendPing() => _send({'type': 'ping', 't0': DateTime.now().millisecondsSinceEpoch});

  Future<void> _sendStatus() async {
    if (_ws == null) return;
    final s = await status();
    _send({'type': 'status', ...s});
  }

  Future<void> _onMessage(dynamic data) async {
    final t3 = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(data as String) as Map).map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'hello':
        clientName = '${m['device'] ?? 'tablet'}';
        onChange?.call();
        return;
      case 'pong':
        final t0 = (m['t0'] as num).toInt();
        final t1 = (m['t1'] as num).toInt();
        final t2 = (m['t2'] as num).toInt();
        _offsets.add(((t1 - t0) + (t2 - t3)) ~/ 2);
        _rtts.add((t3 - t0) - (t2 - t1));
        while (_offsets.length > 5) {
          _offsets.removeAt(0);
          _rtts.removeAt(0);
        }
        return;
    }
    // A match event: ack it, drop repeats, convert its time.
    final key = '${m['cid']}:${m['seq']}';
    _send({'type': 'ack', 'seq': m['seq']});
    if (!_seen.add(key)) return;
    if (_seen.length > 2000) _seen.remove(_seen.first);
    final t = (m['t'] as num?)?.toInt() ?? t3;
    await session.handle(m, t - clock.offsetMs);
  }
}
