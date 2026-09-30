import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_clip_service.dart';

/// One hype sound: what it says, what the overlay shows, how it glows.
class SoundDef {
  final String id;

  /// Spoken by TTS when there is no MP3 for it.
  final String text;

  /// Overlay text; `\n` breaks the line.
  final String display;

  /// legendary | fire | danger | null (default cyan).
  final String? glow;

  /// Made on the phone (Sound Library), not bundled.
  final bool custom;

  const SoundDef({
    required this.id,
    required this.text,
    required this.display,
    this.glow,
    this.custom = false,
  });

  factory SoundDef.fromJson(Map<String, dynamic> j, {bool custom = false}) => SoundDef(
    id: j['id'].toString(),
    text: (j['text'] ?? j['id']).toString(),
    display: (j['display'] ?? j['text'] ?? j['id']).toString(),
    glow: j['glow']?.toString(),
    custom: custom,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'display': display,
    'text': text,
    if (glow != null) 'glow': glow,
  };

  /// A sound known only from an MP3 file: its name is all there is.
  factory SoundDef.fromFileId(String id) {
    final words = id.split('/').last.replaceAll(RegExp(r'_\d+$'), '').replaceAll('_', ' ');
    return SoundDef(id: id, text: words, display: words.toUpperCase(), custom: true);
  }
}

class TriggerDef {
  final String id;
  final int priority;
  final List<String> pool;
  const TriggerDef(this.id, this.priority, this.pool);
}

enum SoundKind { userFile, asset, ttsClip, ttsLive }

/// Where one play of a sound comes from.
class SoundSource {
  final SoundKind kind;

  /// Asset path (without `assets/`) or device file path; the text for ttsLive.
  final String value;
  const SoundSource(this.kind, this.value);
}

/// The one catalog of hype sounds and trigger pools.
///
/// Two layers:
///   • defaults — assets/config/sound_library.json, shipped with the app
///   • the phone's own edits — <files>/sounds/library_user.json: custom TTS
///     lines, per-trigger additions/removals, sounds switched off. Kept
///     outside the APK so no rebuild is needed, and on external app storage
///     so `adb pull` can read it (tools/pull_sound_library.py merges it back
///     into the defaults).
///
/// A sound plays from the first of: an MP3 dropped at <files>/sounds/<id>.mp3,
/// the bundled assets/audio/hype/<id>.mp3, its text as a cached TTS clip, or
/// its text spoken live (and rendered for next time).
///
/// When a trigger fires stays in code (HypeVoiceController); only what it
/// plays is data.
class SoundLibraryService extends GetxService {
  static const _assetPath = 'assets/config/sound_library.json';
  static const _userName = 'library_user.json';

  /// Bumped on every change, for the UI.
  final RxInt revision = 0.obs;

  final Map<String, SoundDef> _base = {};
  final List<String> _baseOrder = [];
  final List<TriggerDef> _triggers = [];
  final Set<String> _bundled = {};

  final Map<String, SoundDef> _custom = {};
  final Map<String, Set<String>> _add = {};
  final Map<String, Set<String>> _remove = {};
  final Set<String> _off = {};
  final Set<String> _userFiles = {};

  Directory? _userDir;

  static SoundLibraryService? get maybe =>
      Get.isRegistered<SoundLibraryService>() ? Get.find<SoundLibraryService>() : null;

  String get userDirPath => _userDir?.path ?? '(unavailable)';

  Future<SoundLibraryService> init() async {
    await _loadDefaults();
    await _loadBundled();
    try {
      final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      _userDir = Directory('${base.path}/sounds')..createSync(recursive: true);
    } catch (e) {
      print('🔔 [Library] no user folder: $e');
    }
    _loadUser();
    rescanFiles();
    _validate();
    return this;
  }

  // ── Loading ────────────────────────────────────────────────────────────

  Future<void> _loadDefaults() async {
    try {
      applyDefaults(json.decode(await rootBundle.loadString(_assetPath)) as Map<String, dynamic>);
    } catch (e) {
      print('🔔 [Library] defaults failed to load: $e');
    }
  }

  /// Parsed defaults; also the entry point for tests.
  @visibleForTesting
  void applyDefaults(Map<String, dynamic> j, {Set<String> bundled = const {}}) {
    _bundled.addAll(bundled);
    for (final s in (j['sounds'] as List? ?? const [])) {
      final d = SoundDef.fromJson(Map<String, dynamic>.from(s));
      if (_base.containsKey(d.id)) continue;
      _base[d.id] = d;
      _baseOrder.add(d.id);
    }
    for (final t in (j['triggers'] as List? ?? const [])) {
      _triggers.add(
        TriggerDef(t['id'].toString(), (t['priority'] as num?)?.toInt() ?? 0, [
          for (final p in (t['pool'] as List? ?? const [])) p.toString(),
        ]),
      );
    }
  }

  Future<void> _loadBundled() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const dir = 'assets/audio/hype/';
      for (final p in manifest.listAssets()) {
        if (p.startsWith(dir) && p.endsWith('.mp3')) {
          _bundled.add(p.substring(dir.length, p.length - 4));
        }
      }
    } catch (e) {
      print('🔔 [Library] asset manifest failed: $e');
    }
  }

  File? get _userFile => _userDir == null ? null : File('${_userDir!.path}/$_userName');

  /// A broken file is set aside, never fatal: the defaults still play.
  void _loadUser() {
    final f = _userFile;
    if (f == null || !f.existsSync()) return;
    try {
      applyUser(json.decode(f.readAsStringSync()) as Map<String, dynamic>);
      print('🔔 [Library] user layer: ${_custom.length} custom, ${_off.length} off');
    } catch (e) {
      print('🔔 [Library] user file unreadable, set aside: $e');
      try {
        f.renameSync('${f.path}.bad');
      } catch (_) {}
    }
  }

  /// Parsed user layer; also the entry point for tests.
  @visibleForTesting
  void applyUser(Map<String, dynamic> j) {
    // Everything parsed before anything is kept: a file that fails halfway
    // leaves the layer untouched instead of half applied.
    final custom = [
      for (final s in (j['custom'] as List? ?? const []))
        SoundDef.fromJson(Map<String, dynamic>.from(s), custom: true),
    ];
    Map<String, Set<String>> sets(dynamic m) => {
      if (m is Map)
        for (final e in m.entries) e.key.toString(): {for (final v in (e.value as List)) v.toString()},
    };
    final add = sets(j['add']);
    final remove = sets(j['remove']);
    final off = [for (final v in (j['off'] as List? ?? const [])) v.toString()];
    for (final d in custom) {
      _custom[d.id] = d;
    }
    _add.addAll(add);
    _remove.addAll(remove);
    _off.addAll(off);
  }

  /// MP3s dropped into the user folder (adb push), by id = path without .mp3.
  void rescanFiles() {
    _userFiles.clear();
    final d = _userDir;
    if (d == null || !d.existsSync()) return;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.toLowerCase().endsWith('.mp3')) continue;
      _userFiles.add(p.substring(d.path.length + 1, p.length - 4));
    }
    revision.value++;
  }

  void _validate() {
    final known = {..._base.keys, ..._custom.keys, ..._userFiles};
    for (final t in _triggers) {
      final missing = t.pool.where((id) => !known.contains(id)).toList();
      if (missing.isNotEmpty) print('🔔 [Library] ⚠️ ${t.id}: unknown sounds $missing');
    }
    final unlisted = _bundled.difference(_base.keys.toSet());
    if (unlisted.isNotEmpty) {
      print('🔔 [Library] ⚠️ bundled MP3s missing from sound_library.json: $unlisted');
    }
    print(
      '🔔 [Library] ${_base.length} sounds, ${_triggers.length} triggers, '
      '${_bundled.length} bundled MP3s, ${_userFiles.length} on-phone MP3s',
    );
  }

  // ── Reading ────────────────────────────────────────────────────────────

  /// Defaults in file order, then custom lines, then MP3-only drops.
  List<SoundDef> get sounds => [
    for (final id in _baseOrder) _custom[id] ?? _base[id]!,
    for (final d in _custom.values)
      if (!_base.containsKey(d.id)) d,
    for (final id in _userFiles)
      if (!_base.containsKey(id) && !_custom.containsKey(id)) SoundDef.fromFileId(id),
  ];

  SoundDef? sound(String id) =>
      _custom[id] ?? _base[id] ?? (_userFiles.contains(id) ? SoundDef.fromFileId(id) : null);

  /// Highest priority first.
  List<TriggerDef> get triggers => [..._triggers]..sort((a, b) => b.priority.compareTo(a.priority));

  TriggerDef? trigger(String id) {
    for (final t in _triggers) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool isOff(String id) => _off.contains(id);

  /// What a trigger can play now: its default pool, plus additions, minus
  /// removals and anything switched off or unknown.
  List<String> pool(String triggerId) {
    final t = trigger(triggerId);
    if (t == null) return const [];
    final removed = _remove[triggerId] ?? const {};
    final out = <String>[];
    for (final id in [...t.pool, ...?_add[triggerId]]) {
      if (removed.contains(id) || _off.contains(id) || out.contains(id)) continue;
      if (sound(id) == null) continue;
      out.add(id);
    }
    return out;
  }

  /// Triggers a sound is in (whether or not it is switched off).
  Set<String> triggersOf(String id) => {
    for (final t in _triggers)
      if ((t.pool.contains(id) || (_add[t.id]?.contains(id) ?? false)) &&
          !(_remove[t.id]?.contains(id) ?? false))
        t.id,
  };

  bool hasUserFile(String id) => _userFiles.contains(id);
  bool isBundled(String id) => _bundled.contains(id);

  /// Short tag for the library list.
  String sourceLabel(String id) {
    if (_userFiles.contains(id)) return 'FILE';
    if (_bundled.contains(id)) return 'MP3';
    final d = sound(id);
    final clips = VoiceClipService.maybe;
    if (d != null && clips != null && clips.isRendered(d.text)) return 'TTS ✓';
    return 'TTS';
  }

  /// Where to play [id] from right now. Null only for an unknown id.
  Future<SoundSource?> source(String id) async {
    final d = _userDir;
    if (d != null && _userFiles.contains(id)) {
      final f = File('${d.path}/$id.mp3');
      if (f.existsSync()) return SoundSource(SoundKind.userFile, f.path);
    }
    if (_bundled.contains(id)) return SoundSource(SoundKind.asset, 'audio/hype/$id.mp3');
    final def = sound(id);
    if (def == null) return null;
    final clip = await VoiceClipService.maybe?.resolve(def.text);
    if (clip != null) return SoundSource(SoundKind.ttsClip, clip);
    return SoundSource(SoundKind.ttsLive, def.text);
  }

  // ── Editing (the phone's own layer) ────────────────────────────────────

  /// A new TTS line, rendered right away so its first play is already a clip.
  Future<String> addCustom({
    required String text,
    String? display,
    String? glow,
    Set<String> triggers = const {},
  }) async {
    var id = 'u_${_slug(text)}';
    if (id == 'u_') id = 'u_line';
    final base = id;
    for (var n = 2; sound(id) != null; n++) {
      id = '${base}_$n';
    }
    _custom[id] = SoundDef(
      id: id,
      text: text.trim(),
      display: _displayOf(text, display),
      glow: glow,
      custom: true,
    );
    for (final t in triggers) {
      (_add[t] ??= {}).add(id);
    }
    await _save();
    VoiceClipService.maybe?.prepare(text.trim());
    return id;
  }

  /// Text and overlay of any sound can be changed; a bundled one gets an
  /// override in the user layer (its MP3 still wins over the text).
  Future<void> edit(String id, {required String text, String? display, String? glow}) async {
    final old = sound(id);
    if (old == null || text.trim().isEmpty) return;
    _custom[id] = SoundDef(
      id: id,
      text: text.trim(),
      display: _displayOf(text, display),
      glow: glow ?? old.glow,
      custom: true,
    );
    await _save();
    VoiceClipService.maybe?.prepare(text.trim());
  }

  /// Custom line: gone. Bundled sound with an override: back to its default.
  Future<void> deleteCustom(String id) async {
    if (_custom.remove(id) == null) return;
    if (!_base.containsKey(id)) {
      for (final s in _add.values) {
        s.remove(id);
      }
      for (final s in _remove.values) {
        s.remove(id);
      }
      _off.remove(id);
    }
    await _save();
  }

  bool isOverridden(String id) => _custom.containsKey(id) && _base.containsKey(id);

  Future<void> setOff(String id, bool off) async {
    off ? _off.add(id) : _off.remove(id);
    await _save();
  }

  Future<void> setInTrigger(String id, String triggerId, bool inIt) async {
    final t = trigger(triggerId);
    if (t == null) return;
    final inBase = t.pool.contains(id);
    final add = _add[triggerId] ??= {};
    final remove = _remove[triggerId] ??= {};
    if (inIt) {
      remove.remove(id);
      if (!inBase) add.add(id);
    } else {
      add.remove(id);
      if (inBase) remove.add(id);
    }
    await _save();
  }

  /// Written to a temp file and renamed, so a crash mid-write never leaves a
  /// half file behind.
  Future<void> _save() async {
    revision.value++;
    final f = _userFile;
    if (f == null) return;
    Map<String, List<String>> clean(Map<String, Set<String>> m) => {
      for (final e in m.entries)
        if (e.value.isNotEmpty) e.key: (e.value.toList()..sort()),
    };
    final j = {
      'version': 1,
      'custom': [for (final d in _custom.values) d.toJson()],
      'add': clean(_add),
      'remove': clean(_remove),
      'off': _off.toList()..sort(),
    };
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(j), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      print('🔔 [Library] save failed: $e');
    }
  }

  static String _displayOf(String text, String? display) {
    final d = display?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return text.trim().replaceAll(RegExp(r'[!?.…]+$'), '').toUpperCase();
  }

  static const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  static const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

  /// "Bá Khí!" -> "ba_khi"
  static String _slug(String text) {
    final b = StringBuffer();
    for (final ch in text.toLowerCase().split('')) {
      final i = _from.indexOf(ch);
      b.write(i >= 0 ? _to[i] : ch);
    }
    final slug = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.length > 28 ? slug.substring(0, 28) : slug;
  }
}
