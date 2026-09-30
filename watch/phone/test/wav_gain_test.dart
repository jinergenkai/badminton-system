import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/services/wav_gain.dart';

/// Minimal 16-bit mono WAV around [samples], with an extra chunk before
/// `data` the way some TTS engines write it.
Uint8List wav(List<int> samples, {int rate = 16000}) {
  final data = samples.length * 2;
  const extra = 12; // 'LIST' chunk with 4 bytes of payload
  final b = ByteData(44 + extra + data);
  void put(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }
  put(0, 'RIFF');
  b.setUint32(4, 36 + extra + data, Endian.little);
  put(8, 'WAVE');
  put(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  put(36, 'LIST');
  b.setUint32(40, 4, Endian.little);
  put(44, 'INFO');
  put(48, 'data');
  b.setUint32(52, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(56 + i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

List<int> samplesOf(Uint8List out) {
  final bd = ByteData.sublistView(out);
  final n = bd.getUint32(40, Endian.little) ~/ 2;
  return [for (var i = 0; i < n; i++) bd.getInt16(44 + i * 2, Endian.little)];
}

void main() {
  test('quiet signal is multiplied by the gain', () {
    final out = boostWav(wav(List.filled(100, 1000)), 2.0, silence: 0)!;
    expect(samplesOf(out).every((s) => (s - 2000).abs() <= 1), isTrue);
  });

  test('loud peaks bend below full scale instead of clipping', () {
    final out = boostWav(wav([30000, -30000, 20000]), 2.0, silence: 0)!;
    final s = samplesOf(out);
    expect(s.every((v) => v.abs() < 32767), isTrue);
    expect(s[0] > 0 && s[1] < 0, isTrue);
    expect(s[0] >= s[2], isTrue); // order of loudness kept
  });

  test('leading and trailing silence are trimmed (20 ms kept)', () {
    final samples = [...List.filled(1600, 0), ...List.filled(160, 5000), ...List.filled(1600, 0)];
    final s = samplesOf(boostWav(wav(samples), 1.0)!);
    // 160 loud samples + 20 ms (320 samples at 16 kHz) of air on each side
    expect(s.length, 160 + 320 + 320);
  });

  test('not a 16-bit PCM WAV -> null (play the original)', () {
    expect(boostWav(Uint8List.fromList(List.filled(60, 0)), 2.0), isNull);
  });

  /// 1 s of a 220 Hz tone at [amp], with gaps like speech has.
  List<int> speechLike(double amp) => [
        for (var i = 0; i < 16000; i++)
          (i ~/ 1600).isEven ? (amp * 32767 * math.sin(2 * math.pi * 220 * i / 16000)).round() : 0
      ];

  double dbOf(Uint8List out) =>
      20 * math.log(rmsOf([for (final s in samplesOf(out)) s / 32768.0])) / math.ln10;

  test('processSpeech: quiet and loud renders land at the same level', () {
    final quiet = dbOf(processSpeech(wav(speechLike(0.05)))!);
    final loud = dbOf(processSpeech(wav(speechLike(0.9)))!);
    expect(quiet, closeTo(-10, 1.5));
    expect(loud, closeTo(-10, 1.5));
  });

  test('processSpeech: boost is extra gain on top, never past full scale', () {
    final base = dbOf(processSpeech(wav(speechLike(0.2)))!);
    final boosted = processSpeech(wav(speechLike(0.2)), boost: 4.0)!;
    expect(dbOf(boosted), greaterThan(base + 3));
    expect(samplesOf(boosted).every((v) => v.abs() <= 32767), isTrue);
  });
}
