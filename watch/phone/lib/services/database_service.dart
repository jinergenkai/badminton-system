import 'package:hive_flutter/hive_flutter.dart';
import '../models/match.dart';
import '../models/team_config.dart';

class DatabaseService {
  static const String matchesBoxName = 'matches';
  static const String configBoxName = 'config';
  static const String teamConfigKey = 'team_config';

  static Box<Match>? _matchesBox;
  static Box? _configBox;

  /// Initialize Hive and open boxes
  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MatchAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TeamConfigAdapter());
    }

    // Open boxes
    _matchesBox = await Hive.openBox<Match>(matchesBoxName);
    _configBox = await Hive.openBox(configBoxName);

    print('✅ [Database] Hive initialized successfully');
    print('📊 [Database] Matches in database: ${_matchesBox!.length}');
  }

  // ==================== MATCH OPERATIONS ====================

  /// Save a match to the database
  static Future<void> saveMatch(Match match) async {
    if (_matchesBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    await _matchesBox!.add(match);
    print('💾 [Database] Match saved: ${match.teamAName} vs ${match.teamBName} (${match.teamAScore}-${match.teamBScore})');
  }

  /// Get all matches (newest first)
  static List<Match> getAllMatches() {
    if (_matchesBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    return _matchesBox!.values.toList().reversed.toList();
  }

  /// Get recent matches (limit)
  static List<Match> getRecentMatches(int limit) {
    final allMatches = getAllMatches();
    return allMatches.take(limit).toList();
  }

  /// Get matches filtered by team name
  static List<Match> getMatchesByTeam(String teamName) {
    final allMatches = getAllMatches();
    return allMatches.where((match) {
      return match.teamAName.toLowerCase().contains(teamName.toLowerCase()) ||
          match.teamBName.toLowerCase().contains(teamName.toLowerCase());
    }).toList();
  }

  /// Get matches filtered by winner
  static List<Match> getMatchesByWinner(String winner) {
    final allMatches = getAllMatches();
    return allMatches.where((match) => match.winner == winner).toList();
  }

  /// Delete a match by key
  static Future<void> deleteMatch(int key) async {
    if (_matchesBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    await _matchesBox!.delete(key);
    print('🗑️ [Database] Match deleted at key: $key');
  }

  /// Delete all matches
  static Future<void> deleteAllMatches() async {
    if (_matchesBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    await _matchesBox!.clear();
    print('🗑️ [Database] All matches cleared');
  }

  /// Get match statistics
  static Map<String, dynamic> getMatchStatistics() {
    final allMatches = getAllMatches();

    if (allMatches.isEmpty) {
      return {
        'totalMatches': 0,
        'totalDuration': Duration.zero,
        'averageDuration': Duration.zero,
        'longestMatch': null,
        'shortestMatch': null,
      };
    }

    final totalDuration = allMatches.fold<Duration>(
      Duration.zero,
      (sum, match) => sum + match.duration,
    );

    final sortedByDuration = List<Match>.from(allMatches)
      ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

    return {
      'totalMatches': allMatches.length,
      'totalDuration': totalDuration,
      'averageDuration': Duration(seconds: totalDuration.inSeconds ~/ allMatches.length),
      'longestMatch': sortedByDuration.last,
      'shortestMatch': sortedByDuration.first,
    };
  }

  // ==================== TEAM CONFIG OPERATIONS ====================

  /// Get team configuration (or create default if doesn't exist)
  static TeamConfig getTeamConfig() {
    if (_configBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    final config = _configBox!.get(teamConfigKey);
    if (config == null) {
      final defaultConfig = TeamConfig();
      saveTeamConfig(defaultConfig);
      return defaultConfig;
    }

    return config as TeamConfig;
  }

  /// Save team configuration
  static Future<void> saveTeamConfig(TeamConfig config) async {
    if (_configBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    await _configBox!.put(teamConfigKey, config);
    print('💾 [Database] Team config saved: ${config.teamAName} vs ${config.teamBName}');
  }

  /// Reset team config to defaults
  static Future<void> resetTeamConfig() async {
    await saveTeamConfig(TeamConfig());
    print('🔄 [Database] Team config reset to defaults');
  }

  // ==================== UTILITY OPERATIONS ====================

  /// Close all boxes (call on app close)
  static Future<void> close() async {
    await _matchesBox?.close();
    await _configBox?.close();
    print('🔒 [Database] All boxes closed');
  }

  /// Compact database (optimize storage)
  static Future<void> compact() async {
    await _matchesBox?.compact();
    await _configBox?.compact();
    print('📦 [Database] Database compacted');
  }
}
