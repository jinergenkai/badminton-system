class GameState {
  final int teamAScore;
  final int teamBScore;
  final bool isGameActive;
  final List<String> history;
  final DateTime lastUpdate;
  final String teamAName;
  final String teamBName;
  final List<GameState> stateStack; // For undo functionality
  final DateTime? startTime; // Track match start time

  GameState({
    this.teamAScore = 0,
    this.teamBScore = 0,
    this.isGameActive = true,
    this.history = const [],
    this.teamAName = 'GAU GAU',
    this.teamBName = 'MEO MEO',
    this.stateStack = const [],
    this.startTime,
    DateTime? lastUpdate,
  }) : lastUpdate = lastUpdate ?? DateTime.now();

  GameState copyWith({
    int? teamAScore,
    int? teamBScore,
    bool? isGameActive,
    List<String>? history,
    String? teamAName,
    String? teamBName,
    List<GameState>? stateStack,
    DateTime? startTime,
    DateTime? lastUpdate,
  }) {
    return GameState(
      teamAScore: teamAScore ?? this.teamAScore,
      teamBScore: teamBScore ?? this.teamBScore,
      isGameActive: isGameActive ?? this.isGameActive,
      history: history ?? this.history,
      teamAName: teamAName ?? this.teamAName,
      teamBName: teamBName ?? this.teamBName,
      stateStack: stateStack ?? this.stateStack,
      startTime: startTime ?? this.startTime,
      lastUpdate: lastUpdate ?? DateTime.now(),
    );
  }

  String get winner {
    if (teamAScore >= 21 && teamAScore - teamBScore >= 2) return 'Team A';
    if (teamBScore >= 21 && teamBScore - teamAScore >= 2) return 'Team B';
    return '';
  }

  bool get hasWinner => winner.isNotEmpty;

  bool get canUndo => stateStack.isNotEmpty;

  Duration get matchDuration {
    if (startTime == null) return Duration.zero;
    return DateTime.now().difference(startTime!);
  }
}
