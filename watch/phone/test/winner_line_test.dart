import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/services/score_announcer_service.dart';

void main() {
  test('Vietnamese winner: team clip, then winner score, then loser score', () {
    expect(ScoreAnnouncerService.winnerFiles('vi', 'A', 21, 18),
        ['audio/score/vi/win_red.mp3', 'audio/score/vi/21.mp3', 'audio/score/vi/18.mp3']);
    expect(ScoreAnnouncerService.winnerFiles('vi', 'B', 27, 29),
        ['audio/score/vi/win_blue.mp3', 'audio/score/vi/29.mp3', 'audio/score/vi/27.mp3']);
  });

  test('no all-clip line for English, an unknown team or a score off the clips', () {
    expect(ScoreAnnouncerService.winnerFiles('en', 'A', 21, 18), isNull);
    expect(ScoreAnnouncerService.winnerFiles('vi', '', 21, 18), isNull);
    expect(ScoreAnnouncerService.winnerFiles('vi', 'A', 31, 29), isNull);
  });

  test('every Vietnamese clip the announcer can ask for is bundled', () {
    final names = [
      for (var n = 0; n <= 30; n++) '$n',
      'all', 'undo', 'win_red', 'win_blue', 'het_gio',
    ];
    for (final n in names) {
      expect(File('assets/audio/score/vi/$n.mp3').existsSync(), isTrue, reason: '$n.mp3 missing');
    }
  });
}
