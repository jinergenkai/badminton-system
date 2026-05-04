import 'dart:async';
import 'package:flutter/services.dart';
import '../models/game_state.dart';

/// Service for communicating with Xiaomi Wearable SDK watch
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
      final success = await platform.invokeMethod('initialize');
      if (success == true) {
        _isInitialized = true;
        print('⌚ [WatchService] Initialized successfully');

        // Listen for commands from watch
        _eventSubscription = eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is Map) {
              final command = Map<String, dynamic>.from(event);
              _commandController.add(command);
              print('⌚ [WatchService] Received from watch: $command');
            }
          },
          onError: (error) {
            print('⌚ [WatchService] Event stream error: $error');
          },
        );
      } else {
        print('⌚ [WatchService] Initialization failed (no watch found or auth denied)');
      }
    } catch (e) {
      print('⌚ [WatchService] Initialization error: $e');
    }
  }

  /// Send score update to connected watch
  Future<void> sendScoreUpdate(GameState gameState, {String action = 'sync'}) async {
    if (!_isInitialized) {
      print('⌚ [WatchService] Not initialized, skipping score update');
      return;
    }

    try {
      await platform.invokeMethod('sendMessage', {
        'data': {
          'action': action,
          'scoreA': gameState.teamAScore,
          'scoreB': gameState.teamBScore,
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
        'data': {
          'action': 'sync',
          'scoreA': 0,
          'scoreB': 0,
        },
      });
      print('⌚ [WatchService] Game reset notification sent');
    } catch (e) {
      print('⌚ [WatchService] Error sending reset: $e');
    }
  }

  /// Send winner announcement to watch (Optional since watch handles winning logic, but we can sync)
  Future<void> sendWinnerUpdate(String winner, int teamAScore, int teamBScore) async {
    if (!_isInitialized) return;
    try {
      await platform.invokeMethod('sendMessage', {
        'data': {
          'action': 'sync',
          'scoreA': teamAScore,
          'scoreB': teamBScore,
        },
      });
    } catch (e) {}
  }

  /// Send raw command (Not really used in the new Xiaomi logic)
  Future<void> sendCommand(String command) async { }

  /// Check if watch is connected
  Future<bool> isWatchConnected() async {
    if (!_isInitialized) return false;
    try {
      final result = await platform.invokeMethod('isWatchConnected');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Get list of connected nodes
  Future<List<String>> getConnectedNodes() async {
    if (!_isInitialized) return [];
    try {
      final result = await platform.invokeMethod('getConnectedNodes');
      if (result is List) {
        return result.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _commandController.close();
    _isInitialized = false;
  }
}
