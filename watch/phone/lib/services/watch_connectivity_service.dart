import 'dart:async';
import 'package:flutter/services.dart';
import '../models/game_state.dart';

/// Service for communicating with WearOS watch
class WatchConnectivityService {
  static const platform = MethodChannel('com.voice_counter/watch');
  static const eventChannel = EventChannel('com.voice_counter/watch_events');

  final StreamController<Map<String, dynamic>> _commandController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get watchCommandStream =>
      _commandController.stream;

  bool _isInitialized = false;
  StreamSubscription? _eventSubscription;

  /// Initialize watch connectivity service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await platform.invokeMethod('initialize');
      _isInitialized = true;
      print('⌚ [WatchService] Initialized successfully');

      // Listen for commands from watch
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            final command = Map<String, dynamic>.from(event);
            _commandController.add(command);
            print('⌚ [WatchService] Received command from watch: $command');
          }
        },
        onError: (error) {
          print('⌚ [WatchService] Event stream error: $error');
        },
      );
    } catch (e) {
      print('⌚ [WatchService] Initialization error: $e');
      // Not critical if watch isn't available
    }
  }

  /// Send score update to connected watch
  Future<void> sendScoreUpdate(GameState gameState) async {
    if (!_isInitialized) {
      print('⌚ [WatchService] Not initialized, skipping score update');
      return;
    }

    try {
      await platform.invokeMethod('sendMessage', {
        'path': '/game-update',
        'data': {
          'teamAScore': gameState.teamAScore,
          'teamBScore': gameState.teamBScore,
          'teamAName': gameState.teamAName,
          'teamBName': gameState.teamBName,
          'isGameActive': gameState.isGameActive,
          'winner': gameState.winner,
        },
      });
      print('⌚ [WatchService] Score update sent: ${gameState.teamAScore}-${gameState.teamBScore}');
    } catch (e) {
      print('⌚ [WatchService] Error sending score update: $e');
    }
  }

  /// Send game reset notification to watch
  Future<void> sendGameReset() async {
    if (!_isInitialized) return;

    try {
      await platform.invokeMethod('sendMessage', {
        'path': '/game-reset',
        'data': {'reset': true},
      });
      print('⌚ [WatchService] Game reset notification sent');
    } catch (e) {
      print('⌚ [WatchService] Error sending reset: $e');
    }
  }

  /// Send winner announcement to watch
  Future<void> sendWinnerUpdate(String winner, int teamAScore, int teamBScore) async {
    if (!_isInitialized) return;

    try {
      await platform.invokeMethod('sendMessage', {
        'path': '/game-winner',
        'data': {
          'winner': winner,
          'teamAScore': teamAScore,
          'teamBScore': teamBScore,
        },
      });
      print('⌚ [WatchService] Winner update sent: $winner');
    } catch (e) {
      print('⌚ [WatchService] Error sending winner: $e');
    }
  }

  /// Check if watch is connected
  Future<bool> isWatchConnected() async {
    if (!_isInitialized) return false;

    try {
      final result = await platform.invokeMethod('isWatchConnected');
      return result == true;
    } catch (e) {
      print('⌚ [WatchService] Error checking watch connection: $e');
      return false;
    }
  }

  /// Get list of connected nodes (watches)
  Future<List<String>> getConnectedNodes() async {
    if (!_isInitialized) return [];

    try {
      final result = await platform.invokeMethod('getConnectedNodes');
      if (result is List) {
        return result.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      print('⌚ [WatchService] Error getting connected nodes: $e');
      return [];
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _commandController.close();
    _isInitialized = false;
    print('⌚ [WatchService] Disposed');
  }
}
