import 'dart:math' as math;
import 'dart:typed_data';

/// Loudness for TTS output, in pure Dart.
///
/// Android TTS writes 16-bit PCM WAV. The chain is the one
/// tools/normalize_voice.py runs on the bundled MP3s, with the same numbers,
/// so a TTS line spliced between two recorded clips sounds as loud as they
/// do:
///   trim → compress (-28 dB, 6:1) → gain to [kTargetLufs] → peak limiter
///   at -0.5 dBFS (look-ahead, so it turns the gain down instead of bending
///   the wave: no crackle).
///
/// Every entry point returns null for anything that is not 16-bit PCM WAV;
/// the caller then plays the file as it is.

/// Loudness of every voice clip, integrated LUFS (EBU R128). Kept in step
/// with TARGET_LUFS in tools/normalize_voice.py.
const double kTargetLufs = -10.0;

/// Peak ceiling: -0.5 dBFS, as the MP3s' limiter.
const double kCeiling = 0.944;

/// Plain gain, peaks held under [kCeiling] by the limiter.
Uint8List? boostWav(Uint8List bytes, double gain, {double silence = 0.01}) {
  final pcm = _Pcm.parse(bytes);
  if (pcm == null) return null;
  final x = pcm.trimmed(silence);
  if (x == null) return null;
  for (var i = 0; i < x.length; i++) {
    x[i] *= gain;
  }
  _limit(x, pcm.channels, pcm.rate);
  return pcm.write(x);
}

/// The bundled clips' treatment, landing on [targetLufs]. [boost] is extra
/// gain on top (1.0 = as loud as the clips); the limiter keeps it clean.
Uint8List? processSpeech(Uint8List bytes,
    {double boost = 1.0, double targetLufs = kTargetLufs, double silence = 0.01}) {
  final pcm = _Pcm.parse(bytes);
  if (pcm == null) return null;
  final x = pcm.trimmed(silence);
  if (x == null) return null;
  final ch = pcm.channels, sr = pcm.rate;
  _compress(x, ch, sr);
  final target = targetLufs + 20 * math.log(boost <= 0 ? 1e-6 : boost) / math.ln10;
  // A few rounds: the limiter takes a little back from the loudest lines
  // (measured: 1 dB short after one round on a peaky one).
  for (var round = 0; round < 5; round++) {
    final l = lufsOf(x, ch, sr);
    if (l == null) break;
    if (round > 0 && (target - l).abs() <= 0.3) break;
    // Capped: a near-silent render would otherwise be pushed into noise.
    final g = math.min(math.pow(10, (target - l) / 20).toDouble(), 100.0);
    for (var i = 0; i < x.length; i++) {
      x[i] *= g;
    }
    _limit(x, ch, sr);
  }
  return pcm.write(x);
}

/// Root mean square of samples in -1..1.
double rmsOf(List<double> x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

/// Integrated loudness (ITU-R BS.1770 / EBU R128) of interleaved samples:
/// K-weighting, 400 ms blocks at 75 % overlap, absolute and relative gates.
/// A clip shorter than one block is measured as one block. Null for silence.
double? lufsOf(Float64List x, int ch, int sr) {
  final frames = x.length ~/ ch;
  if (frames == 0) return null;
  // Per-channel K-weighted squares.
  final sq = Float64List(frames);
  for (var c = 0; c < ch; c++) {
    final y = _kWeight(x, ch, c, sr);
    for (var f = 0; f < frames; f++) {
      sq[f] += y[f] * y[f];
    }
  }
  final block = (sr * 0.4).round();
  final hop = block ~/ 4;
  final z = <double>[];
  if (frames <= block) {
    var s = 0.0;
    for (final v in sq) {
      s += v;
    }
    z.add(s / frames);
  } else {
    for (var start = 0; start + block <= frames; start += hop) {
      var s = 0.0;
      for (var f = start; f < start + block; f++) {
        s += sq[f];
      }
      z.add(s / block);
    }
  }
  double loud(double v) => -0.691 + 10 * math.log(v) / math.ln10;
  final abs = [for (final v in z) if (v > 0 && loud(v) > -70) v];
  if (abs.isEmpty) return null;
  final rel = loud(abs.reduce((a, b) => a + b) / abs.length) - 10;
  final gated = [for (final v in abs) if (loud(v) > rel) v];
  return loud(gated.reduce((a, b) => a + b) / gated.length);
}

/// BS.1770 K-weighting of channel [c]: high shelf (+4 dB above ~1.7 kHz)
/// then a high-pass at ~38 Hz, coefficients for any sample rate.
Float64List _kWeight(Float64List x, int ch, int c, int sr) {
  final frames = x.length ~/ ch;
  var k = math.tan(math.pi * 1681.974450955533 / sr);
  const q1 = 0.7071752369554196;
  final vh = math.pow(10, 3.999843853973347 / 20).toDouble();
  final vb = math.pow(vh, 0.4996667741545416).toDouble();
  var a0 = 1 + k / q1 + k * k;
  final b = [(vh + vb * k / q1 + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q1 + k * k) / a0];
  final a = [2 * (k * k - 1) / a0, (1 - k / q1 + k * k) / a0];
  k = math.tan(math.pi * 38.13547087602444 / sr);
  const q2 = 0.5003270373238773;
  a0 = 1 + k / q2 + k * k;
  final a2 = [2 * (k * k - 1) / a0, (1 - k / q2 + k * k) / a0];
  final out = Float64List(frames);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0; // shelf state
  var u1 = 0.0, u2 = 0.0, w1 = 0.0, w2 = 0.0; // high-pass state
  for (var f = 0; f < frames; f++) {
    final v = x[f * ch + c];
    final y = b[0] * v + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
    x2 = x1;
    x1 = v;
    y2 = y1;
    y1 = y;
    final w = y - 2 * u1 + u2 - a2[0] * w1 - a2[1] * w2;
    u2 = u1;
    u1 = y;
    w2 = w1;
    w1 = w;
    out[f] = w;
  }
  return out;
}

/// Feed-forward compressor on the frame peak, like ffmpeg's acompressor
/// with the MP3s' "loud" profile (-28 dB, 6:1, attack 3 ms, release 60 ms).
void _compress(Float64List x, int ch, int sr,
    {double thresholdDb = -28, double ratio = 6, double attackMs = 3, double releaseMs = 60}) {
  final t = math.pow(10, thresholdDb / 20).toDouble();
  final a = math.exp(-1 / (sr * attackMs / 1000));
  final r = math.exp(-1 / (sr * releaseMs / 1000));
  var env = 0.0;
  for (var f = 0; f < x.length ~/ ch; f++) {
    var peak = 0.0;
    for (var c = 0; c < ch; c++) {
      peak = math.max(peak, x[f * ch + c].abs());
    }
    env = peak > env ? a * env + (1 - a) * peak : r * env + (1 - r) * peak;
    if (env <= t) continue;
    final g = t * math.pow(env / t, 1 / ratio) / env;
    for (var c = 0; c < ch; c++) {
      x[f * ch + c] *= g;
    }
  }
}

/// Look-ahead peak limiter, like ffmpeg's alimiter: the gain ramps down over
/// [attackMs] before a peak, is held for [holdMs], then recovers over
/// [releaseMs], so no sample exceeds [ceiling] and the waveform itself is
/// never bent. The hold is longer than one cycle of the lowest voice
/// (~80 Hz = 12.5 ms): recovering between two peaks of the same cycle would
/// wobble the gain inside the wave, which is heard as crackle.
void _limit(Float64List x, int ch, int sr,
    {double ceiling = kCeiling, double attackMs = 5, double holdMs = 20, double releaseMs = 80}) {
  final frames = x.length ~/ ch;
  if (frames == 0) return;
  final need = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var peak = 0.0;
    for (var c = 0; c < ch; c++) {
      peak = math.max(peak, x[f * ch + c].abs());
    }
    need[f] = peak > ceiling ? ceiling / peak : 1.0;
  }
  // Backwards: start turning down attackMs ahead of each peak, linearly.
  final step = 1 / math.max(1, sr * attackMs / 1000);
  for (var f = frames - 2; f >= 0; f--) {
    need[f] = math.min(need[f], need[f + 1] + step);
  }
  // Forwards: hold, then come back up slowly, never above what is needed.
  final r = math.exp(-1 / (sr * releaseMs / 1000));
  final holdFrames = (sr * holdMs / 1000).round();
  var g = need[0];
  var hold = 0;
  for (var f = 0; f < frames; f++) {
    if (need[f] <= g) {
      g = need[f];
      hold = holdFrames;
    } else if (hold > 0) {
      hold--;
    } else {
      g = math.min(need[f], 1 - (1 - g) * r);
    }
    for (var c = 0; c < ch; c++) {
      x[f * ch + c] *= g;
    }
  }
}

class _Pcm {
  final Uint8List bytes;
  final int channels;
  final int rate;
  final int dataOff;
  final int dataLen;
  _Pcm(this.bytes, this.channels, this.rate, this.dataOff, this.dataLen);

  static _Pcm? parse(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);
    String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
    int? format, channels, rate, bits, dataOff, dataLen;
    var o = 12;
    while (o + 8 <= bytes.length) {
      final id = tag(o);
      final len = bd.getUint32(o + 4, Endian.little);
      final body = o + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = bd.getUint16(body, Endian.little);
        channels = bd.getUint16(body + 2, Endian.little);
        rate = bd.getUint32(body + 4, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataOff = body;
        // Some writers leave the size 0 or oversized when streaming.
        dataLen = (len == 0 || body + len > bytes.length) ? bytes.length - body : len;
        break;
      }
      o = body + len + (len.isOdd ? 1 : 0);
    }
    if (format != 1 || bits != 16 || dataOff == null || channels == null || channels == 0 ||
        rate == null) {
      return null;
    }
    return _Pcm(bytes, channels, rate, dataOff, dataLen!);
  }

  /// Samples as -1..1, cut to the first/last frame above [silence] with
  /// 20 ms of air kept on each side. Null when it is all silence.
  Float64List? trimmed(double silence) {
    final bd = ByteData.sublistView(bytes);
    final ch = channels;
    final frames = dataLen ~/ (2 * ch);
    double s(int f, int c) => bd.getInt16(dataOff + (f * ch + c) * 2, Endian.little) / 32768.0;
    bool loud(int f) {
      for (var c = 0; c < ch; c++) {
        if (s(f, c).abs() > silence) return true;
      }
      return false;
    }
    var first = 0, last = frames - 1;
    while (first < frames && !loud(first)) {
      first++;
    }
    while (last > first && !loud(last)) {
      last--;
    }
    if (first >= frames) return null;
    final pad = rate ~/ 50; // 20 ms
    first = math.max(0, first - pad);
    last = math.min(frames - 1, last + pad);
    final out = Float64List((last - first + 1) * ch);
    for (var f = 0; f <= last - first; f++) {
      for (var c = 0; c < ch; c++) {
        out[f * ch + c] = s(first + f, c);
      }
    }
    return out;
  }

  /// A fresh canonical 44-byte header + [x] as 16-bit samples.
  Uint8List write(Float64List x) {
    final dataBytes = x.length * 2;
    final w = ByteData(44 + dataBytes);
    void put(int off, String s) {
      for (var i = 0; i < 4; i++) {
        w.setUint8(off + i, s.codeUnitAt(i));
      }
    }
    put(0, 'RIFF');
    w.setUint32(4, 36 + dataBytes, Endian.little);
    put(8, 'WAVE');
    put(12, 'fmt ');
    w.setUint32(16, 16, Endian.little);
    w.setUint16(20, 1, Endian.little);
    w.setUint16(22, channels, Endian.little);
    w.setUint32(24, rate, Endian.little);
    w.setUint32(28, rate * channels * 2, Endian.little);
    w.setUint16(32, channels * 2, Endian.little);
    w.setUint16(34, 16, Endian.little);
    put(36, 'data');
    w.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < x.length; i++) {
      w.setInt16(44 + i * 2, (x[i] * 32767).round().clamp(-32768, 32767), Endian.little);
    }
    return w.buffer.asUint8List();
  }
}
