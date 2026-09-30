import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'wav_gain.dart';

/// Levels past 100% for any clip: bundled MP3s, pushed MP3s, TTS renders.
///
/// A player's volume stops at 1.0, so "Voice 180%" cannot be a volume. It is
/// the clip itself, made louder: decoded to PCM once (natively, MediaCodec —
/// Dart has no MP3 decoder), multiplied with the soft limiter, cached per
/// level. The player then plays that file at full volume.
///
/// On disk, under app support:
///   pcm/<key>.wav          decoded clip — made once per clip
///   out/<key>_<pct>.wav    × level — made once per clip and level
/// Everything is dropped when a new APK is installed (the bundled clips may
/// have changed), and least-recently-used files go past [_maxBytes].
class ClipGainService extends GetxService {
  static const _channel = MethodChannel('com.voice_counter/audio');
  static const _maxBytes = 60 * 1024 * 1024;

  /// Highest level the sliders offer. At the top the limiter saturates:
  /// denser and louder, audibly crackly.
  static const double maxLevel = 3.0;

  Directory? _pcm;
  Directory? _out;
  final Map<String, Future<String?>> _inflight = {};

  static ClipGainService? get maybe =>
      Get.isRegistered<ClipGainService>() ? Get.find<ClipGainService>() : null;

  Future<ClipGainService> init() async {
    try {
      final base = Directory('${(await getApplicationSupportDirectory()).path}/gain_cache')
        ..createSync(recursive: true);
      _pcm = Directory('${base.path}/pcm')..createSync();
      _out = Directory('${base.path}/out')..createSync();
      final stampFile = File('${base.path}/app_stamp');
      final stamp = await _channel.invokeMethod<String>('appStamp') ?? '';
      if (!stampFile.existsSync() || stampFile.readAsStringSync() != stamp) {
        _clear(_pcm!);
        _clear(_out!);
        stampFile.writeAsStringSync(stamp);
        print('🎚️ [Gain] new install: cache cleared');
      }
      _evict();
    } catch (e) {
      // Without the cache nothing is boosted; everything still plays.
      print('🎚️ [Gain] unavailable: $e');
      _pcm = _out = null;
    }
    return this;
  }

  /// A file to play [src] at [level], or null to play the original at
  /// volume min(level, 1).
  ///
  /// [src] is an asset path under assets/ ('audio/score/vi/5.mp3') or an
  /// absolute device path. Null also when level ≤ 1 or anything fails —
  /// a clip that cannot be boosted still plays.
  Future<String?> boosted(String src, double level) async {
    final out = _out;
    if (out == null || level <= 1.001) return null;
    final pct = (level * 20).round() * 5; // 5% steps: fewer files, same ear
    final key = _key(src);
    if (key == null) return null;
    final dst = File('${out.path}/${key}_$pct.wav');
    if (dst.existsSync()) {
      _touch(dst);
      return dst.path;
    }
    // Two plays of the same clip at once share one render.
    return _inflight.putIfAbsent(dst.path, () async {
      try {
        return await _make(src, key, pct / 100, dst).timeout(const Duration(seconds: 5));
      } catch (e) {
        print('🎚️ [Gain] $src ×$pct%: $e');
        return null;
      } finally {
        _inflight.remove(dst.path);
      }
    });
  }

  /// Renders ahead of time, one after another, so a slider change does not
  /// make the next point wait. Plays still go straight through meanwhile.
  Future<void> warm(List<String> srcs, double level) async {
    if (level <= 1.001) return;
    for (final s in srcs) {
      await boosted(s, level);
    }
  }

  /// Asset: the path (a new install clears everything). Device file: path,
  /// size and time, so a replaced file is not served stale.
  String? _key(String src) {
    var id = src;
    if (src.startsWith('/')) {
      final f = File(src);
      if (!f.existsSync()) return null;
      id = '$src|${f.lengthSync()}|${f.lastModifiedSync().millisecondsSinceEpoch}';
    }
    return md5.convert(utf8.encode(id)).toString();
  }

  Future<String?> _make(String src, String key, double gain, File dst) async {
    final pcm = await _pcmOf(src, key);
    if (pcm == null) return null;
    final bytes = await File(pcm).readAsBytes();
    // Only true digital silence is trimmed: clips are already cut.
    final boosted = boostWav(bytes, gain, silence: 0.001);
    if (boosted == null) return null;
    final part = File('${dst.path}.part');
    await part.writeAsBytes(boosted, flush: true);
    await part.rename(dst.path);
    _evict();
    return dst.path;
  }

  /// The clip as 16-bit PCM WAV: a WAV source as is, anything else decoded.
  Future<String?> _pcmOf(String src, String key) async {
    if (src.startsWith('/') && src.toLowerCase().endsWith('.wav')) return src;
    final dir = _pcm!;
    final wav = File('${dir.path}/$key.wav');
    if (wav.existsSync()) {
      _touch(wav);
      return wav.path;
    }
    var input = src;
    File? tmp;
    if (!src.startsWith('/')) {
      // Flutter assets are not plain files on Android: copy the bytes out.
      final data = await rootBundle.load('assets/$src');
      tmp = File('${dir.path}/$key.src');
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      input = tmp.path;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('decodeToWav', {'src': input, 'dst': wav.path});
      return ok == true && wav.existsSync() ? wav.path : null;
    } finally {
      if (tmp != null && tmp.existsSync()) tmp.deleteSync();
    }
  }

  void _touch(File f) {
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  void _clear(Directory d) {
    for (final f in d.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  void _evict() {
    final files = <File>[
      for (final d in [_pcm, _out])
        if (d != null && d.existsSync()) ...d.listSync().whereType<File>(),
    ];
    var total = 0;
    for (final f in files) {
      total += f.lengthSync();
    }
    if (total <= _maxBytes) return;
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final f in files) {
      if (total <= _maxBytes * 3 ~/ 4) break;
      // In-progress files are young; the oldest go first, so they are safe.
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}
