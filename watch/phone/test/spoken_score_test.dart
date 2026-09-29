import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:voice_counter/services/audio_settings.dart';

void main() {
  late AudioSettings audio;

  setUp(() {
    Get.reset();
    audio = Get.put(AudioSettings());
  });

  test('Vietnamese short reading: last digit from 11 up', () {
    int say(int n) => AudioSettings.spokenScore(n, 'vi-VN');
    expect([0, 5, 9].map(say), [0, 5, 9]);
    expect([11, 15, 19, 21, 25, 29].map(say), [1, 5, 9, 1, 5, 9]);
    // Round tens keep their full name: "không" would say nothing.
    expect([10, 20, 30].map(say), [10, 20, 30]);
  });

  test('English is never shortened', () {
    expect(AudioSettings.spokenScore(15, 'en-US'), 15);
  });

  test('switch off = full numbers', () {
    audio.shortScore.value = false;
    expect(AudioSettings.spokenScore(15, 'vi-VN'), 15);
  });
}
