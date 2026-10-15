/// Named players of one set, as picked on the band at 0-0.
///
/// Team 'A' is always red, 'B' always blue — the same mapping as the score
/// cards, the band buttons and the rally log (`AABBA…`).
class Lineup {
  final List<String> red; // [red1, red2]
  final List<String> blue; // [blue1, blue2]
  /// First server / receiver at 0-0. '' since the band stopped asking
  /// (2026-10): a wrong pick spoiled every serve stat after it. Older
  /// records still carry them.
  final String srv;
  final String rcv;
  final Map<String, String> short; // id -> band name
  final Map<String, String> full; // id -> full name (read aloud)
  final String mode; // 'new' | 'same'

  const Lineup({
    required this.red,
    required this.blue,
    this.srv = '',
    this.rcv = '',
    required this.short,
    required this.full,
    this.mode = 'new',
  });

  /// From the band's `lu` object; null when absent or malformed.
  static Lineup? fromBand(dynamic lu) {
    if (lu is! Map) return null;
    final red = lu['red'];
    final blue = lu['blue'];
    final srv = lu['srv'];
    final rcv = lu['rcv'];
    if (red is! List || blue is! List || red.length != 2 || blue.length != 2) return null;
    final short = <String, String>{};
    final full = <String, String>{};
    final names = lu['names'];
    if (names is Map) {
      names.forEach((k, v) {
        if (v is Map) {
          short['$k'] = (v['s'] ?? k).toString();
          full['$k'] = (v['n'] ?? v['s'] ?? k).toString();
        }
      });
    }
    return Lineup(
      red: red.map((e) => '$e').toList(),
      blue: blue.map((e) => '$e').toList(),
      srv: srv is String ? srv : '',
      rcv: rcv is String ? rcv : '',
      short: short,
      full: full,
      mode: (lu['mode'] ?? 'new').toString(),
    );
  }

  /// Who served first is known: serve order and serve stats can be derived.
  bool get hasServe => srv.isNotEmpty && rcv.isNotEmpty;

  List<String> pair(String team) => team == 'A' ? red : blue;
  String teamOf(String id) => red.contains(id) ? 'A' : 'B';
  String shortOf(String id) => short[id] ?? id;
  String fullOf(String id) => full[id] ?? short[id] ?? id;
}

/// Who serves and receives, from which court.
class ServeState {
  final String team; // serving team, 'A' | 'B'
  final String court; // 'R' | 'L' — the server's court
  final String srv;
  final String rcv;
  const ServeState(this.team, this.court, this.srv, this.rcv);
}

/// Doubles service order, derived purely from the lineup at 0-0 and the rally
/// log. Mirrors computeServe() in the band's index.ux — keep them in step.
///
///  - The serving side wins the rally: its two players swap courts and the
///    same player serves again.
///  - The receiving side wins: it gains the serve and nobody moves; its
///    server is whoever stands in the court matching its own score
///    (even = right, odd = left).
///  - The receiver stands in the same-named court, diagonally opposite.
class ServeEngine {
  /// State before each rally, plus the state after the last one:
  /// `result[i]` is who served rally i, `result.last` is who serves next.
  static List<ServeState> timeline(Lineup lu, String rallies) {
    String partner(String team, String id) {
      final p = lu.pair(team);
      return p[0] == id ? p[1] : p[0];
    }

    final s0 = lu.teamOf(lu.srv);
    final r0 = s0 == 'A' ? 'B' : 'A';
    final right = <String, String>{s0: lu.srv, r0: lu.rcv};
    final left = <String, String>{s0: partner(s0, lu.srv), r0: partner(r0, lu.rcv)};

    var serving = s0;
    var a = 0, b = 0;

    ServeState snapshot() {
      final own = serving == 'A' ? a : b;
      final court = own.isEven ? 'R' : 'L';
      final other = serving == 'A' ? 'B' : 'A';
      return ServeState(
        serving,
        court,
        court == 'R' ? right[serving]! : left[serving]!,
        court == 'R' ? right[other]! : left[other]!,
      );
    }

    final out = <ServeState>[snapshot()];
    for (final w in rallies.split('')) {
      if (w != 'A' && w != 'B') continue;
      if (w == 'A') {
        a++;
      } else {
        b++;
      }
      if (w == serving) {
        final t = right[w]!;
        right[w] = left[w]!;
        left[w] = t;
      } else {
        serving = w;
      }
      out.add(snapshot());
    }
    return out;
  }

  static ServeState current(Lineup lu, String rallies) => timeline(lu, rallies).last;
}
