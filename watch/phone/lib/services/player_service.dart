import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watch_connectivity_service.dart';

/// One person in the club roster.
///
/// [id] is short and permanent (`p12`): it is what match records store, so
/// renaming someone never rewrites history, and it keeps band payloads small.
/// [externalId] is reserved for the badminton-payments app import.
class Player {
  final String id;
  String name;
  String short;
  String? externalId;

  Player({required this.id, required this.name, required this.short, this.externalId});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'short': short, if (externalId != null) 'ext': externalId};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        short: j['short'] as String,
        externalId: j['ext'] as String?,
      );
}

/// Someone in the web roster (sổ tiền): [id] is the id GỐC.
class WebPerson {
  final String id;
  final String name;
  const WebPerson(this.id, this.name);
}

/// The full roster lives on the phone. Only today's picks (8-10 people)
/// go to the band, which is all its picker needs and all its screen can show.
class PlayerService extends GetxService {
  static const _prefRoster = 'players_roster';
  static const _prefToday = 'players_today';
  static const _prefNext = 'players_next_id';
  static const _prefVersion = 'players_version';
  static const _prefWeb = 'players_web';
  static const _prefRetired = 'players_retired_ext';

  /// Max characters of a band label.
  static const shortMax = 8;

  final RxList<Player> roster = <Player>[].obs;
  final RxSet<String> today = <String>{}.obs;

  /// The web roster as last pulled (id GỐC sổ tiền + name), so a phone-made
  /// player can be linked to the right web person by hand. Empty until the
  /// first "Kéo danh bạ".
  final RxList<WebPerson> web = <WebPerson>[].obs;

  /// externalId of players removed from the roster: their old matches still
  /// carry the phone id, and pushing them must still send the web id.
  final Map<String, String> _retiredExt = {};

  /// Identifies the list the band should hold. Changes whenever anything the
  /// band shows changes; the band reports the one it has in every state
  /// message, so a mismatch means "resend".
  final RxInt version = 0.obs;

  /// When the band last got the list from this phone (this app run).
  final Rxn<DateTime> lastSent = Rxn<DateTime>();

  int _nextId = 1;
  Timer? _sendDebounce;
  DateTime? _lastAutoSend;

  static PlayerService? get maybe =>
      Get.isRegistered<PlayerService>() ? Get.find<PlayerService>() : null;

  static PlayerService get to => Get.find<PlayerService>();

  /// Nhập danh bạ từ backend (id GỐC sổ tiền). Khớp theo externalId trước, rồi
  /// theo tên (người chưa nối); tạo mới nếu chưa có. Luôn set externalId = id gốc.
  /// Trả số người được tạo/cập nhật. Không đụng today/band.
  Future<int> importBackend(List<Map<String, dynamic>> players) async {
    int n = 0;
    web.assignAll(players
        .map((bp) => WebPerson((bp['id'] ?? '').toString(), (bp['name'] ?? '?').toString().trim()))
        .where((w) => w.id.isNotEmpty));
    for (final bp in players) {
      final extId = (bp['id'] ?? '').toString();
      if (extId.isEmpty) continue;
      final name = (bp['name'] ?? '?').toString().trim();
      final short = (bp['short'] ?? '').toString().trim();
      Player? p = roster.firstWhereOrNull((x) => x.externalId == extId);
      p ??= roster.firstWhereOrNull(
          (x) => x.externalId == null && x.name.trim().toLowerCase() == name.toLowerCase());
      if (p == null) {
        roster.add(Player(
          id: 'p${_nextId++}',
          name: name.isEmpty ? '?' : name,
          short: short.isEmpty ? defaultShort(name) : clampShort(short),
          externalId: extId,
        ));
        n++;
      } else {
        if (name.isNotEmpty) p.name = name;
        if (short.isNotEmpty) p.short = clampShort(short);
        p.externalId = extId;
        n++;
      }
    }
    roster.refresh();
    await _save(bandVisible: false);
    return n;
  }

  Future<PlayerService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefRoster);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        roster.assignAll(list.map(Player.fromJson));
      } catch (e) {
        print('👥 [Players] roster parse failed: $e');
      }
    }
    today.addAll(prefs.getStringList(_prefToday) ?? const []);
    today.removeWhere((id) => !roster.any((p) => p.id == id));
    _nextId = prefs.getInt(_prefNext) ?? 1;
    version.value = prefs.getInt(_prefVersion) ?? 0;
    try {
      final w = prefs.getString(_prefWeb);
      if (w != null) {
        web.assignAll((jsonDecode(w) as List)
            .cast<Map<String, dynamic>>()
            .map((j) => WebPerson(j['id'] as String, j['name'] as String)));
      }
      final r = prefs.getString(_prefRetired);
      if (r != null) _retiredExt.addAll((jsonDecode(r) as Map).cast<String, String>());
    } catch (e) {
      print('👥 [Players] web/retired parse failed: $e');
    }
    return this;
  }

  /// Vietnamese names end with the given name: "Nguyễn Văn Hùng" -> "Hùng".
  static String defaultShort(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    return last.length > shortMax ? last.substring(0, shortMax) : last;
  }

  static String clampShort(String s) {
    final t = s.trim();
    return t.length > shortMax ? t.substring(0, shortMax) : t;
  }

  /// Today's players, sorted by band label.
  List<Player> get todayPlayers {
    final list = roster.where((p) => today.contains(p.id)).toList();
    list.sort((a, b) => a.short.toLowerCase().compareTo(b.short.toLowerCase()));
    return list;
  }

  /// Band labels used by more than one of today's players — they would be
  /// indistinguishable in the band picker.
  Set<String> get duplicateShorts {
    final seen = <String>{};
    final dup = <String>{};
    for (final p in todayPlayers) {
      final k = p.short.toLowerCase();
      if (!seen.add(k)) dup.add(k);
    }
    return dup;
  }

  Player? byId(String id) => roster.firstWhereOrNull((p) => p.id == id);

  /// The id to send to the web for a phone id in a match record: the linked
  /// web id, also for someone since removed; else the phone id itself (the
  /// server then reports it as unknown).
  String webIdOf(String phoneId) => byId(phoneId)?.externalId ?? _retiredExt[phoneId] ?? phoneId;

  WebPerson? webPerson(String? extId) =>
      extId == null ? null : web.firstWhereOrNull((w) => w.id == extId);

  /// Phone players linked to [extId], [except] one.
  List<Player> linkedTo(String extId, {String? except}) =>
      roster.where((p) => p.externalId == extId && p.id != except).toList();

  /// Link (or with null, unlink) a phone player to a web person by hand.
  /// Two phone players may end up on the same web id — typically the one
  /// typed on court and the copy "Kéo danh bạ" created; both push correctly,
  /// and the spare one can be removed without losing its matches.
  Future<void> link(String id, String? extId) async {
    final p = byId(id);
    if (p == null) return;
    p.externalId = (extId == null || extId.isEmpty) ? null : extId;
    roster.refresh();
    await _save(bandVisible: false);
  }

  Future<Player> add(String name, {String? short}) async {
    final n = name.trim();
    final s = (short == null || short.trim().isEmpty) ? defaultShort(n) : clampShort(short);
    final p = Player(id: 'p${_nextId++}', name: n, short: s);
    roster.add(p);
    await _save(bandVisible: false);
    return p;
  }

  Future<void> edit(String id, {required String name, required String short}) async {
    final p = byId(id);
    if (p == null) return;
    p.name = name.trim();
    p.short = short.trim().isEmpty ? defaultShort(p.name) : clampShort(short);
    roster.refresh();
    await _save(bandVisible: today.contains(id));
  }

  /// Removing someone never touches past matches: records keep a name
  /// snapshot of everyone who played.
  Future<void> remove(String id) async {
    final wasToday = today.remove(id);
    final ext = byId(id)?.externalId;
    if (ext != null) _retiredExt[id] = ext;
    roster.removeWhere((p) => p.id == id);
    await _save(bandVisible: wasToday);
  }

  Future<void> toggleToday(String id) async {
    if (!today.remove(id)) today.add(id);
    await _save(bandVisible: true);
  }

  Future<void> clearToday() async {
    if (today.isEmpty) return;
    today.clear();
    await _save(bandVisible: true);
  }

  Future<void> _save({required bool bandVisible}) async {
    if (bandVisible) {
      // Seconds since epoch: unique across reinstalls, fits a JS number.
      version.value = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRoster, jsonEncode(roster.map((p) => p.toJson()).toList()));
    await prefs.setStringList(_prefToday, today.toList());
    await prefs.setInt(_prefNext, _nextId);
    await prefs.setInt(_prefVersion, version.value);
    await prefs.setString(_prefWeb, jsonEncode(web.map((w) => {'id': w.id, 'name': w.name}).toList()));
    await prefs.setString(_prefRetired, jsonEncode(_retiredExt));
    if (bandVisible) {
      // Ticking five names in a row should be one send, not five.
      _sendDebounce?.cancel();
      _sendDebounce = Timer(const Duration(milliseconds: 1500), sendToBand);
    }
  }

  /// Compact on purpose: ~50 bytes a player.
  Map<String, dynamic> bandPayload() => {
        'v': version.value,
        'list': todayPlayers.map((p) => {'i': p.id, 's': p.short, 'n': p.name}).toList(),
      };

  Future<void> sendToBand() async {
    final watch = Get.isRegistered<WatchConnectivityService>()
        ? Get.find<WatchConnectivityService>()
        : null;
    if (watch == null) return;
    await watch.sendScoreCommand('players', extra: bandPayload());
    lastSent.value = DateTime.now();
    print('👥 [Players] sent ${today.length} players v${version.value}');
  }

  /// Called with the version the band reports in its state messages. Resends
  /// when they differ, at most every 30s so a band that keeps failing to
  /// store it does not get the list on every point.
  void onBandVersion(int bandVersion) {
    if (bandVersion == version.value) return;
    final now = DateTime.now();
    if (_lastAutoSend != null && now.difference(_lastAutoSend!) < const Duration(seconds: 30)) return;
    _lastAutoSend = now;
    print('👥 [Players] band has v$bandVersion, phone v${version.value} -> resend');
    sendToBand();
  }
}
