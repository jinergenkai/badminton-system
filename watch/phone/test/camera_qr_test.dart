import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/features/camera/camera_qr.dart';

void main() {
  test('round trip', () {
    final raw = CameraQr.encode(['192.168.43.1', '10.0.0.5'], 8765);
    expect(CameraQr.hosts(raw), ['192.168.43.1', '10.0.0.5']);
  });

  test('not our code: null', () {
    expect(CameraQr.hosts(null), isNull);
    expect(CameraQr.hosts('https://example.com'), isNull);
    expect(CameraQr.hosts('{"godminton":"band","hosts":["1.2.3.4"]}'), isNull);
    expect(CameraQr.hosts('{"godminton":"camera","hosts":["not-an-ip"]}'), isNull);
  });

  test('pick: same network first, else the first address', () {
    expect(CameraQr.pick(['10.0.0.5', '192.168.43.1'], ['192.168.43.120']), '192.168.43.1');
    expect(CameraQr.pick(['10.0.0.5', '192.168.43.1'], ['172.16.0.9']), '10.0.0.5');
  });
}
