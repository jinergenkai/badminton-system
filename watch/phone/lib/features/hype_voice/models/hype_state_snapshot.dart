class HypeStateSnapshot {
  final String? currentStreakTeam;
  final int streakCount;
  final int lastOpponentStreak;
  final int maxDeficitTeamA;
  final int maxDeficitTeamB;
  final bool comebackPendingA;
  final bool comebackPendingB;
  // Global per-file play count for the match. Single namespace across all
  // pools so a file selected via one pool can't immediately re-fire from
  // another pool that also contains it.
  final Map<String, int> playCounts;

  HypeStateSnapshot({
    required this.currentStreakTeam,
    required this.streakCount,
    required this.lastOpponentStreak,
    required this.maxDeficitTeamA,
    required this.maxDeficitTeamB,
    required this.comebackPendingA,
    required this.comebackPendingB,
    required this.playCounts,
  });

  factory HypeStateSnapshot.copy(HypeStateSnapshot other) {
    return HypeStateSnapshot(
      currentStreakTeam: other.currentStreakTeam,
      streakCount: other.streakCount,
      lastOpponentStreak: other.lastOpponentStreak,
      maxDeficitTeamA: other.maxDeficitTeamA,
      maxDeficitTeamB: other.maxDeficitTeamB,
      comebackPendingA: other.comebackPendingA,
      comebackPendingB: other.comebackPendingB,
      playCounts: Map<String, int>.from(other.playCounts),
    );
  }
}
