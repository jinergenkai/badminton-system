import 'dart:math' as math;
import 'dart:typed_data';

/// Loudness for TTS output, in pure Dart.
///
/// Android TTS writes 16-bit PCM WAV. PCM is just numbers, so "louder than
/// 100%" is a multiply — with a soft limiter above the knee so the boosted
/// peaks round off instead of clipping hard. Leading/trailing silence is
/// trimmed too: it only delays the words.
///
/// Both entry points return null for anything that is not 16-bit PCM WAV;
/// the caller then plays the file as it is.

/// Plain gain + soft limit.
Uint8List? boostWav(Uint8List bytes, double gain, {double knee = 0.7, double silence = 0.01}) {
  final pcm = _Pcm.parse(bytes);
  if (pcm == null) return null;
  final x = pcm.trimmed(silence);
  if (x == null) return null;
  for (var i = 0; i < x.length; i++) {
    x[i] *= gain;
  }
  _softLimit(x, knee);
  return pcm.write(x);
}

/// The same treatment the bundled MP3s get from tools/normalize_voice.py, so
/// a TTS line sits at the level of the recorded ones:
///   trim → compress (-20 dB, 3:1) → gain to [targetDb] mean → × [boost]
///   → soft limit.
/// At [boost] 1.0 a line matches the score clips; above it is extra, and
/// far above it the limiter saturates — audible crackle, allowed on purpose.
Uint8List? processSpeech(Uint8List bytes,
    {double boost = 1.0, double targetDb = -10, double knee = 0.7, double silence = 0.01}) {
  final pcm = _Pcm.parse(bytes);
  if (pcm == null) return null;
  final x = pcm.trimmed(silence);
  if (x == null) return null;
  _compress(x, pcm.channels, pcm.rate);
  final rms = rmsOf(x);
  if (rms > 0) {
    // Capped: a near-silent render would otherwise be pushed into noise.
    final makeup = math.min(math.pow(10, targetDb / 20) / rms, 30.0);
    for (var i = 0; i < x.length; i++) {
      x[i] *= makeup * boost;
    }
  }
  _softLimit(x, knee);
  return pcm.write(x);
}

/// Root mean square of samples in -1..1; 20·log10 of it is what ffmpeg's
/// volumedetect calls mean_volume.
double rmsOf(List<double> x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

/// Feed-forward compressor on the frame peak, like ffmpeg's acompressor
/// (threshold -20 dB, ratio 3, attack 5 ms, release 60 ms).
void _compress(Float64List x, int ch, int sr,
    {double thresholdDb = -20, double ratio = 3, double attackMs = 5, double releaseMs = 60}) {
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

/// tanh bend above [knee]: continuous at the knee, approaches 1.0, never
/// exceeds it.
void _softLimit(Float64List x, double knee) {
  final range = 1.0 - knee;
  for (var i = 0; i < x.length; i++) {
    final v = x[i];
    final a = v.abs();
    if (a <= knee) continue;
    final bent = knee + range * _tanh((a - knee) / range);
    x[i] = v.isNegative ? -bent : bent;
  }
}

double _tanh(double x) {
  if (x > 20) return 1.0;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
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
