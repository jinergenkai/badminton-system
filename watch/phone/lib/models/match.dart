import 'lineup.dart';
import 'package:hive/hive.dart';

part 'match.g.dart';

@HiveType(typeId: 0)
class Match extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String teamAName;

  @HiveField(2)
  final String teamBName;

  @HiveField(3)
  final int teamAScore;

  @HiveField(4)
  final int teamBScore;

  @HiveField(5)
  final String winner;

  @HiveField(6)
  final DateTime startTime;

  @HiveField(7)
  final DateTime endTime;

  @HiveField(8)
  final List<String> actionHistory;

  @HiveField(9)
  final int durationSeconds;

  @HiveField(10)
  final String status;

  @HiveField(11)
  final bool durationEstimated;

  @HiveField(12)
  final String rallySequence;

  /// Seconds from [startTime] at which each rally in [rallySequence] ended,
  /// comma separated. Empty for sets recorded before this existed.
  @HiveField(13)
  final String rallyTimes;

  // ── Named players (band lineup). Empty when the set was played unnamed.
  // Ids are the phone's permanent player ids; the name maps are a snapshot
  // taken when the set was played, so renames never rewrite history.
  @HiveField(14)
  final List<String> redIds;

  @HiveField(15)
  final List<String> blueIds;

  @HiveField(16)
  final Map<String, String> playerNames;

  @HiveField(17)
  final Map<String, String> playerShorts;

  /// First server and first receiver at 0-0: with [rallySequence] these
  /// reconstruct who served and received every rally (ServeEngine).
  @HiveField(18)
  final String server0;

  @HiveField(19)
  final String receiver0;

  /// 'new' | 'same' | '' (unnamed).
  @HiveField(20)
  final String lineupMode;

  Match({
    required this.id,
    required this.teamAName,
    required this.teamBName,
    required this.teamAScore,
    required this.teamBScore,
    required this.winner,
    required this.startTime,
    required this.endTime,
    required this.actionHistory,
    required this.durationSeconds,
    this.status = 'completed',
    this.durationEstimated = false,
    this.rallySequence = '',
    this.rallyTimes = '',
    this.redIds = const [],
    this.blueIds = const [],
    this.playerNames = const {},
    this.playerShorts = const {},
    this.server0 = '',
    this.receiver0 = '',
    this.lineupMode = '',
  });

  bool get isNamed => redIds.length == 2 && blueIds.length == 2 && server0.isNotEmpty;

  Lineup? get lineup => isNamed
      ? Lineup(
          red: redIds,
          blue: blueIds,
          srv: server0,
          rcv: receiver0,
          short: playerShorts,
          full: playerNames,
          mode: lineupMode,
        )
      : null;

  Duration get duration => Duration(seconds: durationSeconds);

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String get winnerDisplay {
    if (winner == 'A') return teamAName;
    if (winner == 'B') return teamBName;
    return 'Draw';
  }
}
