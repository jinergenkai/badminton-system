import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'player_service.dart';

/// Đồng bộ với backend/api (SQLite) của badminton-system:
///  - Kéo danh bạ (id GỐC sổ tiền) về, gắn vào externalId của player trên phone.
///  - Đẩy các trận ĐÃ XONG + CÓ TÊN (đủ 2v2) lên để tính ranking.
///
/// Không thêm thư viện: dùng dart:io HttpClient. Cấu hình (base URL + token)
/// lưu ở SharedPreferences, nhập trong SyncScreen.
class SyncService extends GetxService {
  static const _kBase = 'sync_base';
  static const _kToken = 'sync_token';

  final RxString baseUrl = ''.obs;
  final RxString token = ''.obs;
  final RxnString lastResult = RxnString();
  final RxBool busy = false.obs;

  static SyncService get to => Get.find<SyncService>();

  static const _defaultBase = 'https://caulongdata.app.huynhhanh.com';

  Future<SyncService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kBase);
    baseUrl.value = (saved == null || saved.isEmpty) ? _defaultBase : saved;
    token.value = prefs.getString(_kToken) ?? '';
    return this;
  }

  Future<void> saveConfig(String base, String tok) async {
    baseUrl.value = base.trim().replaceAll(RegExp(r'/+$'), '');
    token.value = tok.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBase, baseUrl.value);
    await prefs.setString(_kToken, token.value);
  }

  Uri _u(String path) => Uri.parse('${baseUrl.value}$path');

  Future<Map<String, dynamic>> _getJson(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(_u(path));
      req.headers.set('accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 25));
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw 'HTTP ${resp.statusCode}: $text';
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(String path, Object body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(_u(path));
      req.headers.set('content-type', 'application/json');
      if (token.value.isNotEmpty) req.headers.set('authorization', 'Bearer ${token.value}');
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw 'HTTP ${resp.statusCode}: $text';
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Kéo danh bạ về -> gắn externalId cho player. Trả số người cập nhật/tạo.
  Future<int> pullRoster() async {
    if (baseUrl.value.isEmpty) throw 'Chưa đặt địa chỉ backend';
    busy.value = true;
    try {
      final j = await _getJson('/api/roster');
      final players = (j['players'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final n = await PlayerService.to.importBackend(players);
      lastResult.value = 'Kéo roster: ${players.length} người từ backend, cập nhật $n.';
      return n;
    } finally {
      busy.value = false;
    }
  }

  /// Đẩy mọi trận đã xong + có tên. team_a = đội Đỏ, team_b = đội Xanh.
  /// Dùng externalId (id gốc sổ tiền) nếu player đã nối, không thì tạm dùng id phone.
  Future<int> pushMatches() async {
    if (baseUrl.value.isEmpty) throw 'Chưa đặt địa chỉ backend';
    if (token.value.isEmpty) throw 'Chưa đặt token (API_TOKEN)';
    busy.value = true;
    try {
      final ps = PlayerService.to;
      String ext(String phoneId) => ps.byId(phoneId)?.externalId ?? phoneId;

      final matches = DatabaseService.getAllMatches().where((m) =>
          m.status == 'completed' &&
          m.isNamed &&
          (m.winner == 'A' || m.winner == 'B')).toList();

      final payload = matches.map((m) => {
            'id': m.id,
            'played_at': m.startTime.toIso8601String(),
            'ended_at': m.endTime.toIso8601String(),
            'team_a': m.redIds.map(ext).toList(),
            'team_b': m.blueIds.map(ext).toList(),
            'team_a_score': m.teamAScore,
            'team_b_score': m.teamBScore,
            'winner': m.winner,
            'rally_sequence': m.rallySequence,
            'duration_seconds': m.durationSeconds,
            'source': 'phone',
          }).toList();

      if (payload.isEmpty) {
        lastResult.value = 'Không có trận nào đủ điều kiện (đã xong + đủ 2v2 có tên).';
        return 0;
      }
      final j = await _postJson('/api/sync/matches', {'matches': payload});
      final saved = (j['saved'] as num?)?.toInt() ?? 0;
      lastResult.value = 'Đẩy $saved/${payload.length} trận lên backend.';
      return saved;
    } finally {
      busy.value = false;
    }
  }
}
