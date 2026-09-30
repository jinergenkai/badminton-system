import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_service.dart';
import 'wav_gain.dart';

/// Every TTS line the app plays (names, winner, custom hype), rendered to a
/// file once and kept across launches.
///
/// Two layers on disk, under the app's support directory (not the OS cache,
/// which Android may clear):
///   raw/<key>.wav   what the TTS engine produced — the slow part (0.5–2 s
///                   on a weak tablet), so it is made once per line+language
///   out/<key>_<boost>.wav   raw → processSpeech (level-matched to the MP3s)
///                   × Name boost. Cheap to redo, so a boost change only
///                   clears this layer.
///
/// A line that is not rendered yet is spoken live by the caller this time,
/// and rendered in the background for the next.
class VoiceClipService extends GetxService {
  static const _prefBoost = 'tts_boost';

  /// Bump when the processing changes, so old renders are not reused.
  static const _version = 'v2';

  /// Evict least-recently-used files above this.
  static const _maxBytes = 40 * 1024 * 1024;

  /// Extra gain after level-matching. 1.0 = as loud as the score MP3s.
  final RxDouble boost = 1.0.obs;
  static const double maxBoost = 4.0;

  /// ms the last real synthesis took (0 while everything came from disk):
  /// the number that says whether the tablet keeps up.
  final RxInt lastPrepareMs = 0.obs;

  Directory? _raw;
  Directory? _out;
  Future<void> _queue = Future.value();

  static VoiceClipService? get maybe =>
      Get.isRegistered<VoiceClipService>() ? Get.find<VoiceClipService>() : null;

  TtsService get _tts => Get.find<TtsService>();

  Future<VoiceClipService> init() async {
    final prefs = await SharedPreferences.getInstance();
    boost.value = (((prefs.getDouble(_prefBoost) ?? 1.0) * 10).round() / 10).clamp(0.0, maxBoost);
    final base = await getApplicationSupportDirectory();
    _raw = Directory('${base.path}/tts_cache/raw')..createSync(recursive: true);
    _out = Directory('${base.path}/tts_cache/out')..createSync(recursive: true);
    // The old per-run cache lived in the temp dir; nothing there is reused.
    try {
      final old = Directory('${(await getTemporaryDirectory()).path}/voice_clips');
      if (old.existsSync()) old.deleteSync(recursive: true);
      // Left by a short-lived build that boosted MP3s at play time.
      final gain = Directory('${base.path}/gain_cache');
      if (gain.existsSync()) gain.deleteSync(recursive: true);
    } catch (_) {}
    unawaited(_evict());
    return this;
  }

  Future<void> setBoost(double v) async {
    boost.value = ((v * 10).round() / 10).clamp(0.0, maxBoost);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefBoost, boost.value);
    // Every processed file was made at the old level; raw renders stay.
    final out = _out;
    if (out != null) {
      for (final f in out.listSync().whereType<File>()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  String _lang() => _tts.currentLanguage.toLowerCase();

  String _key(String text) =>
      md5.convert(utf8.encode('$_version|${_lang()}|${text.trim()}')).toString();

  String _boostTag() => (boost.value * 100).round().toString();

  File? _outFile(String key) => _out == null ? null : File('${_out!.path}/${key}_${_boostTag()}.wav');
  File? _rawFile(String key) => _raw == null ? null : File('${_raw!.path}/$key.wav');

  /// Path of a playable file for [text] right now, or null. Uses the raw
  /// render when there is one (processing it takes milliseconds); only a
  /// line never synthesized returns null — and is queued for next time.
  Future<String?> resolve(String text) async {
    final key = _key(text);
    final out = _outFile(key);
    if (out == null) return null;
    if (out.existsSync()) {
      _touch(out);
      return out.path;
    }
    final raw = _rawFile(key)!;
    if (raw.existsSync()) {
      _touch(raw);
      return _process(raw, out);
    }
    unawaited(prepare(text));
    return null;
  }

  /// "TTS ✓" in the library: the line has been synthesized at least once.
  bool isRendered(String text) => _rawFile(_key(text))?.existsSync() ?? false;

  /// Synthesize (if needed) and process [text]. Queued: the TTS plugin keeps
  /// a single pending synthesis, so two at once would clobber each other.
  Future<String?> prepare(String text) {
    final done = Completer<String?>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _prepare(text));
      } catch (e) {
        print('🗣️ [VoiceClip] "$text" failed: $e');
        done.complete(null);
      }
    });
    return done.future;
  }

  Future<void> prepareAll(List<String> texts) async {
    for (final t in texts) {
      await prepare(t);
    }
  }

  Future<String?> _prepare(String text) async {
    if (text.trim().isEmpty) return null;
    final key = _key(text);
    final out = _outFile(key);
    final raw = _rawFile(key);
    if (out == null || raw == null) return null;
    if (out.existsSync()) return out.path;
    if (!raw.existsSync()) {
      final sw = Stopwatch()..start();
      final tmp = File('${raw.path}.part');
      final ok = await _tts.synthesizeTo(text, tmp.path);
      if (!ok || !tmp.existsSync() || tmp.lengthSync() < 64) {
        if (tmp.existsSync()) tmp.deleteSync();
        return null;
      }
      // Renamed only when complete: a killed app never leaves half a file
      // that looks like a finished render.
      tmp.renameSync(raw.path);
      lastPrepareMs.value = sw.elapsedMilliseconds;
      print('🗣️ [VoiceClip] "$text" synthesized in ${sw.elapsedMilliseconds} ms');
      unawaited(_evict());
    }
    return _process(raw, out);
  }

  Future<String?> _process(File raw, File out) async {
    try {
      final bytes = await raw.readAsBytes();
      final processed = processSpeech(bytes, boost: boost.value);
      final tmp = File('${out.path}.part');
      await tmp.writeAsBytes(processed ?? bytes, flush: true);
      await tmp.rename(out.path);
      return out.path;
    } catch (e) {
      print('🗣️ [VoiceClip] processing failed: $e');
      return raw.path; // unprocessed beats silent
    }
  }

  void _touch(File f) {
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  /// Least recently used first, until under the cap. Unfinished `.part`
  /// files left by a killed render are removed too.
  Future<void> _evict() async {
    final files = <File>[
      for (final d in [_raw, _out])
        if (d != null && d.existsSync()) ...d.listSync().whereType<File>(),
    ];
    var total = 0;
    final alive = <File>[];
    for (final f in files) {
      if (f.path.endsWith('.part')) {
        // Old ones only: a young one may be a render in progress.
        try {
          if (DateTime.now().difference(f.lastModifiedSync()).inMinutes >= 1) f.deleteSync();
        } catch (_) {}
        continue;
      }
      total += f.lengthSync();
      alive.add(f);
    }
    if (total <= _maxBytes) return;
    alive.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final f in alive) {
      if (total <= _maxBytes * 3 ~/ 4) break;
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {}
    }
    print('🗣️ [VoiceClip] cache trimmed to ${total ~/ 1024} KB');
  }
}
