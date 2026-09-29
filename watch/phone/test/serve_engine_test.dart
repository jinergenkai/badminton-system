import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/models/lineup.dart';

void main() {
  // Red R1,R2 (A) vs Blue B1,B2 (B). R1 serves to B1 at 0-0.
  const lu = Lineup(
    red: ['R1', 'R2'],
    blue: ['B1', 'B2'],
    srv: 'R1',
    rcv: 'B1',
    short: {},
    full: {},
  );

  void expectState(ServeState s, String team, String court, String srv, String rcv) {
    expect([s.team, s.court, s.srv, s.rcv], [team, court, srv, rcv]);
  }

  test('0-0: first server from the right, to the first receiver', () {
    expectState(ServeEngine.current(lu, ''), 'A', 'R', 'R1', 'B1');
  });

  test('BWF doubles sequence', () {
    final t = ServeEngine.timeline(lu, 'ABBA');
    // 1-0: serving side won -> R1 and R2 swap, R1 serves again from the left.
    expectState(t[1], 'A', 'L', 'R1', 'B2');
    // 1-1: receiving side won -> nobody moves; Blue has 1 (odd), so the
    // player in Blue's left court serves.
    expectState(t[2], 'B', 'L', 'B2', 'R1');
    // 1-2: serving side won -> Blue swaps, B2 again, now from the right.
    expectState(t[3], 'B', 'R', 'B2', 'R2');
    // 2-2: Red regains serve; 2 is even -> Red's right court, where R2 stands.
    expectState(t[4], 'A', 'R', 'R2', 'B2');
  });

  test('undo is just a shorter rally log', () {
    expect(ServeEngine.current(lu, 'ABB').srv, ServeEngine.timeline(lu, 'ABBA')[3].srv);
  });

  test('fromBand parses the band lineup and names', () {
    final parsed = Lineup.fromBand({
      'red': ['p1', 'p2'],
      'blue': ['p3', 'p4'],
      'srv': 'p3',
      'rcv': 'p2',
      'names': {
        'p1': {'s': 'Tuan', 'n': 'Nguyen Tuan'},
        'p3': {'s': 'Hung', 'n': 'Nguyen Van Hung'},
      },
      'mode': 'same',
    })!;
    expect(parsed.teamOf('p3'), 'B');
    expect(parsed.fullOf('p3'), 'Nguyen Van Hung');
    expect(parsed.shortOf('p1'), 'Tuan');
    expectState(ServeEngine.current(parsed, ''), 'B', 'R', 'p3', 'p2');
  });

  test('fromBand rejects incomplete data', () {
    expect(Lineup.fromBand(null), isNull);
    expect(Lineup.fromBand({'red': ['p1'], 'blue': ['p3', 'p4'], 'srv': 'p1', 'rcv': 'p3'}), isNull);
  });
}
