import 'package:hive_flutter/hive_flutter.dart';
import '../models/match.dart';
import '../models/team_config.dart';

class DatabaseService {
  static const String matchesBoxName = 'matches';
  static const String configBoxName = 'config';

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
      // Team profiles are gone, but old installs have one stored in the
      // config box: the adapter stays so that box still opens.
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

  /// Band records are revised after undo, so an id must be updated in place
  /// instead of appended again on every reconnect/win.
  static Future<void> upsertMatch(Match match) async {
    if (_matchesBox == null) throw Exception('Database not initialized. Call initialize() first.');
    dynamic existingKey;
    for (final key in _matchesBox!.keys) {
      if (_matchesBox!.get(key)?.id == match.id) { existingKey = key; break; }
    }
    if (existingKey == null) await _matchesBox!.add(match);
    else await _matchesBox!.put(existingKey, match);
  }

  /// A band set that was undone out of its winning point is open again, so
  /// the record saved for it no longer describes a finished set.
  static Future<void> deleteMatchById(String id) async {
    if (_matchesBox == null) return;
    for (final key in _matchesBox!.keys.toList()) {
      if (_matchesBox!.get(key)?.id == id) {
        await _matchesBox!.delete(key);
        print('💾 [Database] Reopened band set removed: $id');
        return;
      }
    }
  }

  /// Get all matches (newest first)
  static List<Match> getAllMatches() {
    if (_matchesBox == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }

    // Newest start first. Not box order: band sets synced after an offline
    // session are inserted late, and an upsert keeps its original slot.
    final list = _matchesBox!.values.toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
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
