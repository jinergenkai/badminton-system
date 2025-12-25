class GameState {
  final int teamAScore;
  final int teamBScore;
  final bool isGameActive;
  final List<String> history;
  final DateTime lastUpdate;

  GameState({
    this.teamAScore = 0,
    this.teamBScore = 0,
    this.isGameActive = true,
    this.history = const [],
    DateTime? lastUpdate,
  }) : lastUpdate = lastUpdate ?? DateTime.now();

  GameState copyWith({
    int? teamAScore,
    int? teamBScore,
    bool? isGameActive,
    List<String>? history,
    DateTime? lastUpdate,
  }) {
    return GameState(
      teamAScore: teamAScore ?? this.teamAScore,
      teamBScore: teamBScore ?? this.teamBScore,
      isGameActive: isGameActive ?? this.isGameActive,
      history: history ?? this.history,
      lastUpdate: lastUpdate ?? DateTime.now(),
    );
  }

  String get winner {
    if (teamAScore >= 21 && teamAScore - teamBScore >= 2) return 'Team A';
    if (teamBScore >= 21 && teamBScore - teamAScore >= 2) return 'Team B';
    return '';
  }

  bool get hasWinner => winner.isNotEmpty;
}
