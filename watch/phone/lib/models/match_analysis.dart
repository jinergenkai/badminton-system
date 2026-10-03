import 'lineup.dart';

/// Per-player numbers for one set. "Serve" rallies are the ones this player
/// served; "receive" rallies are the ones they received.
class PlayerLine {
  final String id;
  final String team; // 'A' red | 'B' blue
  int serves = 0;
  int servesWon = 0;
  int receives = 0;
  int receivesWon = 0;
  PlayerLine(this.id, this.team);
}

/// Everything the history detail shows, derived from what a record stores:
/// the rally log, its timings and (for named sets) the lineup.
class MatchAnalysis {
  /// Score after each rally, starting with the score the log began from
  /// (0-0, or the seed for a set joined mid-way).
  final List<List<int>> progression;
  final int longestStreakA;
  final int longestStreakB;

  /// Seconds each rally took; empty when timings were not recorded.
  final List<int> rallySeconds;

  /// Named sets with a known first server only (older records), in lineup
  /// order: red1, red2, blue1, blue2.
  final List<PlayerLine> players;

  MatchAnalysis._(this.progression, this.longestStreakA, this.longestStreakB,
      this.rallySeconds, this.players);

  double? get avgRallySeconds => rallySeconds.isEmpty
      ? null
      : rallySeconds.reduce((a, b) => a + b) / rallySeconds.length;

  int? get longestRallySeconds =>
      rallySeconds.isEmpty ? null : rallySeconds.reduce((a, b) => a > b ? a : b);

  static MatchAnalysis of({
    required String rallies,
    required String rallyTimes,
    required int finalA,
    required int finalB,
    Lineup? lineup,
  }) {
    final log = rallies.split('').where((c) => c == 'A' || c == 'B').toList();

    // Where the log starts: the final score minus the points it contains.
    var a = finalA - log.where((c) => c == 'A').length;
    var b = finalB - log.where((c) => c == 'B').length;
    if (a < 0) a = 0;
    if (b < 0) b = 0;
    final progression = <List<int>>[
      [a, b]
    ];

    var bestA = 0, bestB = 0, run = 0;
    String? last;
    for (final w in log) {
      if (w == 'A') {
        a++;
      } else {
        b++;
      }
      progression.add([a, b]);
      run = (w == last) ? run + 1 : 1;
      last = w;
      if (w == 'A' && run > bestA) bestA = run;
      if (w == 'B' && run > bestB) bestB = run;
    }

    // Timings are cumulative seconds from the start: rally i took t[i]-t[i-1].
    final secs = <int>[];
    final times = rallyTimes
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    if (times.length == log.length) {
      for (var i = 0; i < times.length; i++) {
        final d = times[i] - (i == 0 ? 0 : times[i - 1]);
        secs.add(d < 0 ? 0 : d);
      }
    }

    final players = <PlayerLine>[];
    if (lineup != null && lineup.hasServe) {
      final byId = <String, PlayerLine>{};
      for (final id in [...lineup.red, ...lineup.blue]) {
        final p = PlayerLine(id, lineup.teamOf(id));
        byId[id] = p;
        players.add(p);
      }
      // timeline[i] is who served / received rally i.
      final timeline = ServeEngine.timeline(lineup, log.join());
      for (var i = 0; i < log.length; i++) {
        final st = timeline[i];
        final s = byId[st.srv];
        final r = byId[st.rcv];
        if (s != null) {
          s.serves++;
          if (log[i] == s.team) s.servesWon++;
        }
        if (r != null) {
          r.receives++;
          if (log[i] == r.team) r.receivesWon++;
        }
      }
    }

    return MatchAnalysis._(progression, bestA, bestB, secs, players);
  }
}
