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
///   out/<key>_<proc>.wav   raw → processSpeech: the same loudness as the
///                   MP3s. Cheap to redo, so a change in the processing only
///                   bumps [_proc] and leaves the raw renders.
///
/// A line that is not rendered yet is spoken live by the caller this time,
/// and rendered in the background for the next.
class VoiceClipService extends GetxService {
  /// Bump when synthesis changes: raw renders are keyed by it.
  static const _version = 'v2';

  /// Bump when processSpeech changes: only out/ is redone.
  /// p3 (2026-10-03): LUFS target + clean limiter; Name boost removed — it
  /// was what made TTS crackle on court.
  static const _proc = 'p3';

  /// Evict least-recently-used files above this.
  static const _maxBytes = 40 * 1024 * 1024;

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
    await prefs.remove('tts_boost');
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
      // Processed with an older chain.
      for (final f in _out!.listSync().whereType<File>()) {
        if (!f.path.endsWith('_$_proc.wav')) f.deleteSync();
      }
    } catch (_) {}
    unawaited(_evict());
    return this;
  }

  String _lang() => _tts.currentLanguage.toLowerCase();

  String _key(String text) =>
      md5.convert(utf8.encode('$_version|${_lang()}|${text.trim()}')).toString();

  File? _outFile(String key) => _out == null ? null : File('${_out!.path}/${key}_$_proc.wav');
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
      final processed = processSpeech(bytes);
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
