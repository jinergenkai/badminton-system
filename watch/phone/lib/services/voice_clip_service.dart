import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_service.dart';
import 'wav_gain.dart';

/// TTS phrases rendered to WAV, boosted past 100% in Dart, and cached.
///
/// Plain TTS tops out at the system volume and is thin next to music. Here
/// a phrase is synthesized to a file once, multiplied by [boost] with a soft
/// limiter (wav_gain.dart), and then played like any bundled clip — so it
/// joins the same ducking/hype chain and costs nothing at play time.
///
/// Known phrases ("<name> giao cầu", the winner lines) are prepared as soon
/// as a lineup is set. A phrase that is not ready is spoken live instead,
/// and prepared for next time.
class VoiceClipService extends GetxService {
  static const _prefBoost = 'voice_boost';

  /// 1.0 = as synthesized, 2.0 = +6 dB. Soft-limited: it never clips hard,
  /// but far up the bend is saturation, audible as crackle. Allowed anyway.
  final RxDouble boost = 1.6.obs;
  static const double maxBoost = 4.0;

  /// How long the last phrase took to synthesize + boost, for the sound
  /// check readout: this is the number that says whether the tablet keeps up.
  final RxInt lastPrepareMs = 0.obs;

  final Map<String, String> _ready = {};
  Future<void> _queue = Future.value();
  Directory? _dir;
  int _seq = 0;

  static VoiceClipService? get maybe =>
      Get.isRegistered<VoiceClipService>() ? Get.find<VoiceClipService>() : null;

  Future<VoiceClipService> init() async {
    final prefs = await SharedPreferences.getInstance();
    boost.value = prefs.getDouble(_prefBoost) ?? 1.6;
    final base = await getTemporaryDirectory();
    _dir = Directory('${base.path}/voice_clips');
    // A fresh start every run: cheap to rebuild, never stale.
    if (_dir!.existsSync()) _dir!.deleteSync(recursive: true);
    _dir!.createSync(recursive: true);
    return this;
  }

  Future<void> setBoost(double v) async {
    boost.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefBoost, v);
    // Every cached clip was made at the old level.
    final texts = _ready.keys.map((k) => k.substring(k.indexOf('|') + 1)).toSet().toList();
    _ready.clear();
    prepareAll(texts);
  }

  String _key(String text) => '${boost.value.toStringAsFixed(2)}|$text';

  /// Path of a ready clip for [text], or null.
  String? ready(String text) {
    final p = _ready[_key(text)];
    return (p != null && File(p).existsSync()) ? p : null;
  }

  /// Render [text] unless it is ready. Calls are queued: the TTS plugin keeps
  /// a single pending synthesis, so two at once would clobber each other.
  Future<String?> prepare(String text) {
    final done = Completer<String?>();
    _queue = _queue.then((_) async {
      if (ready(text) != null) {
        done.complete(ready(text));
        return;
      }
      done.complete(await _render(text));
    });
    return done.future;
  }

  Future<void> prepareAll(List<String> texts) async {
    for (final t in texts) {
      await prepare(t);
    }
  }

  Future<String?> _render(String text) async {
    final dir = _dir;
    if (dir == null) return null;
    final sw = Stopwatch()..start();
    final id = _seq++;
    final raw = '${dir.path}/raw_$id.wav';
    final out = '${dir.path}/clip_$id.wav';
    try {
      final ok = await Get.find<TtsService>().synthesizeTo(text, raw);
      if (!ok || !File(raw).existsSync()) return null;
      final bytes = await File(raw).readAsBytes();
      final boosted = boostWav(bytes, boost.value);
      await File(out).writeAsBytes(boosted ?? bytes);
      File(raw).deleteSync();
      _ready[_key(text)] = out;
      lastPrepareMs.value = sw.elapsedMilliseconds;
      print('🗣️ [VoiceClip] "${text}" ready in ${sw.elapsedMilliseconds} ms'
          '${boosted == null ? ' (not PCM16, unboosted)' : ''}');
      return out;
    } catch (e) {
      print('🗣️ [VoiceClip] "${text}" failed: $e');
      return null;
    }
  }
}
