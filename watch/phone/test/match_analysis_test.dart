import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/models/lineup.dart';
import 'package:voice_counter/models/match_analysis.dart';

void main() {
  const lu = Lineup(
    red: ['R1', 'R2'],
    blue: ['B1', 'B2'],
    srv: 'R1',
    rcv: 'B1',
    short: {},
    full: {},
  );

  test('progression, streaks and rally durations', () {
    final m = MatchAnalysis.of(
      rallies: 'AABBBA',
      rallyTimes: '10,25,31,60,70,90',
      finalA: 3,
      finalB: 3,
    );
    expect(m.progression.first, [0, 0]);
    expect(m.progression.last, [3, 3]);
    expect(m.longestStreakA, 2);
    expect(m.longestStreakB, 3);
    expect(m.rallySeconds, [10, 15, 6, 29, 10, 20]);
    expect(m.longestRallySeconds, 29);
  });

  test('a seeded set starts from the seed, not 0-0', () {
    final m = MatchAnalysis.of(rallies: 'AB', rallyTimes: '', finalA: 13, finalB: 11, lineup: null);
    expect(m.progression.first, [12, 10]);
    expect(m.rallySeconds, isEmpty); // timings missing -> no durations invented
  });

  test('serve / receive counts follow the doubles order', () {
    // ABBA: R1 serves r1 (won), R1 r2 (lost), B2 r3 (won), B2 r4 (lost).
    final m = MatchAnalysis.of(rallies: 'ABBA', rallyTimes: '', finalA: 2, finalB: 2, lineup: lu);
    final by = {for (final p in m.players) p.id: p};
    expect([by['R1']!.serves, by['R1']!.servesWon], [2, 1]);
    expect([by['B2']!.serves, by['B2']!.servesWon], [2, 1]);
    expect(by['R2']!.serves, 0);
    // Receivers: B1 (r1), B2 (r2), R1 (r3), R2 (r4).
    expect([by['B1']!.receives, by['B2']!.receives, by['R1']!.receives, by['R2']!.receives], [1, 1, 1, 1]);
    expect(by['R2']!.receivesWon, 1); // r4 won by red while R2 received
  });
}
