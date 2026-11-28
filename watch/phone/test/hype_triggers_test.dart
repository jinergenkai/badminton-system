import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/features/hype_voice/services/hype_voice_controller.dart';

void main() {
  test('deuce: tied at 20-all and later only', () {
    expect(HypeVoiceController.isDeuce(20, 20), isTrue);
    expect(HypeVoiceController.isDeuce(29, 29), isTrue);
    expect(HypeVoiceController.isDeuce(19, 19), isFalse);
    expect(HypeVoiceController.isDeuce(21, 20), isFalse);
  });

  test('set point: the leader is one point from the set', () {
    expect(HypeVoiceController.isSetPoint(20, 18), isTrue);
    expect(HypeVoiceController.isSetPoint(17, 20), isTrue);
    expect(HypeVoiceController.isSetPoint(22, 21), isTrue);
    expect(HypeVoiceController.isSetPoint(29, 28), isTrue);
    expect(HypeVoiceController.isSetPoint(20, 20), isFalse); // that is deuce
    expect(HypeVoiceController.isSetPoint(19, 10), isFalse);
    expect(HypeVoiceController.isSetPoint(21, 18), isFalse); // set already won
  });
}
