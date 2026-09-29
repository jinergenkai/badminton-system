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
  });

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
