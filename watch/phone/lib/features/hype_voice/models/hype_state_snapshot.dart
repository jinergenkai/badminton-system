class HypeStateSnapshot {
  final String? currentStreakTeam;
  final int streakCount;
  final int lastOpponentStreak;
  final int maxDeficitTeamA;
  final int maxDeficitTeamB;
  final List<String> recentVoiceIds;

  HypeStateSnapshot({
    required this.currentStreakTeam,
    required this.streakCount,
    required this.lastOpponentStreak,
    required this.maxDeficitTeamA,
    required this.maxDeficitTeamB,
    required this.recentVoiceIds,
  });

  factory HypeStateSnapshot.copy(HypeStateSnapshot other) {
    return HypeStateSnapshot(
      currentStreakTeam: other.currentStreakTeam,
      streakCount: other.streakCount,
      lastOpponentStreak: other.lastOpponentStreak,
      maxDeficitTeamA: other.maxDeficitTeamA,
      maxDeficitTeamB: other.maxDeficitTeamB,
      recentVoiceIds: List.from(other.recentVoiceIds),
    );
  }
}
