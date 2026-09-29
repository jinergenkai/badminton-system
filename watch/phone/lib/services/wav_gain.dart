import 'dart:math' as math;
import 'dart:typed_data';

/// Loudness for TTS output, in pure Dart.
///
/// Android TTS writes 16-bit PCM WAV. PCM is just numbers, so "louder than
/// 100%" is a multiply — with a soft limiter above [knee] so the boosted
/// peaks round off instead of clipping hard. Leading/trailing silence is
/// trimmed too: it only delays the words.
///
/// Returns null for anything that is not 16-bit PCM WAV; the caller then
/// plays the file as it is.
Uint8List? boostWav(Uint8List bytes, double gain, {double knee = 0.7, double silence = 0.01}) {
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
  if (format != 1 || bits != 16 || dataOff == null || channels == null || rate == null) return null;
  // Non-null locals: closures below would lose the promotion of the fields.
  final int ch = channels;
  final int sr = rate;
  final int start = dataOff;

  final frames = dataLen! ~/ (2 * ch);
  final src = Int16List(frames * ch);
  for (var i = 0; i < src.length; i++) {
    src[i] = bd.getInt16(start + i * 2, Endian.little);
  }

  // Trim: first/last frame above the silence floor, keeping a few ms of air.
  final floor = (silence * 32768).round();
  var first = 0, last = frames - 1;
  bool loud(int f) {
    for (var c = 0; c < ch; c++) {
      if (src[f * ch + c].abs() > floor) return true;
    }
    return false;
  }
  while (first < frames && !loud(first)) {
    first++;
  }
  while (last > first && !loud(last)) {
    last--;
  }
  if (first >= frames) return null; // all silence
  final pad = sr ~/ 50; // 20 ms
  first = math.max(0, first - pad);
  last = math.min(frames - 1, last + pad);

  final outFrames = last - first + 1;
  final out = Int16List(outFrames * ch);
  final range = 1.0 - knee;
  for (var f = 0; f < outFrames; f++) {
    for (var c = 0; c < ch; c++) {
      var v = src[(first + f) * ch + c] / 32768.0 * gain;
      final a = v.abs();
      if (a > knee) {
        // tanh bend: continuous at the knee, approaches 1.0, never exceeds it
        final t = (a - knee) / range;
        final bent = knee + range * _tanh(t);
        v = v.isNegative ? -bent : bent;
      }
      out[f * ch + c] = (v * 32767).round().clamp(-32768, 32767);
    }
  }

  // Fresh canonical header: 44 bytes + samples.
  final dataBytes = out.length * 2;
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
  w.setUint16(22, ch, Endian.little);
  w.setUint32(24, sr, Endian.little);
  w.setUint32(28, sr * ch * 2, Endian.little);
  w.setUint16(32, ch * 2, Endian.little);
  w.setUint16(34, 16, Endian.little);
  put(36, 'data');
  w.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < out.length; i++) {
    w.setInt16(44 + i * 2, out[i], Endian.little);
  }
  return w.buffer.asUint8List();
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
