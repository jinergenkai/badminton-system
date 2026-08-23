import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:voice_counter/controllers/score_controller.dart';
import '../models/game_state.dart';
import 'music_service.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';

/// Service for communicating with Xiaomi Wearable SDK watch
class WatchConnectivityService extends GetxService {
  static const platform = MethodChannel('com.voice_counter/watch');
  static const eventChannel = EventChannel('com.voice_counter/watch_events');

  final StreamController<Map<String, dynamic>> _commandController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get watchCommandStream =>
      _commandController.stream;

  bool _isInitialized = false;
  StreamSubscription? _eventSubscription;

  /// Whether the phone -> watch direction is usable (we have a node id).
  final RxBool sendPathUp = false.obs;

  /// Whether `addListener` actually succeeded, i.e. whether watch -> phone
  /// can work. Tracked apart from [sendPathUp] because the bug being chased
  /// is precisely the case where the first is up and this one is not.
  final RxBool listenerRegistered = false.obs;

  /// Human-readable dump of the last handshake, surfaced in the UI so the
  /// handshake can be inspected on the court without adb.
  final RxString diagnostics = 'not initialized'.obs;

  /// Initialize watch connectivity service.
  ///
  /// [force] re-runs the handshake even when already initialized — without it
  /// the guard below makes every retry a no-op, so a listener lost to an
  /// Activity restart could never be re-registered.
  Future<void> initialize({bool force = false}) async {
    if (_isInitialized && !force) return;

    try {
      final raw = await platform.invokeMethod('initialize');

      // Native now answers with a report map. Tolerate the old bare `true`
      // in case a stale APK is installed against a newer Dart side.
      final Map<String, dynamic> report = raw is Map
          ? Map<String, dynamic>.from(raw)
          : {'ok': raw == true, 'listenerRegistered': raw == true};

      final bool ok = report['ok'] == true;
      final bool listenerOk = report['listenerRegistered'] == true;

      sendPathUp.value = ok;
      listenerRegistered.value = listenerOk;

      print('⌚ [WatchService] ===== handshake report =====');
      report.forEach((k, v) => print('⌚ [WatchService]   $k = $v'));

      if (ok && !listenerOk) {
        print('⌚ [WatchService] !! ONE-WAY: phone -> watch will work, '
            'watch -> phone will NOT. listenerError=${report['listenerError']}');
      }

      diagnostics.value = [
        'node: ${report['nodeName'] ?? '-'} (${report['nodeId'] ?? 'none'})',
        'permissions: ${report['granted'] ?? '-'}',
        'DEVICE_MANAGER: ${report['hasDeviceManager'] ?? '-'}',
        'wear app installed: ${report['wearAppInstalled'] ?? '-'}',
        'listener registered: $listenerOk',
        if (report['listenerError'] != null) 'listener error: ${report['listenerError']}',
        if (report['error'] != null) 'error: ${report['error']}',
      ].join('\n');

      // Deliberately keyed on `ok`, not on the listener: losing the receive
      // path must not also disable the send path we still have.
      if (ok) {
        _isInitialized = true;

        // Listen for commands from watch
        _eventSubscription?.cancel();
        _eventSubscription = eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is Map) {
              final command = Map<String, dynamic>.from(event);
              _handleWatchCommand(command);
              _commandController.add(command);
              print('⌚ [WatchService] Received from watch: $command');
            }
          },
          onError: (error) {
            print('⌚ [WatchService] Event stream error: $error');
          },
        );
      } else {
        print('⌚ [WatchService] Initialization failed: ${report['error']}');
      }
    } catch (e) {
      diagnostics.value = 'initialize threw: $e';
      print('⌚ [WatchService] Initialization error: $e');
    }
  }

  void _handleWatchCommand(Map<String, dynamic> command) {
    final action = command['action'];
    if (action == 'request_media_list') {
      sendMediaList();
    } else if (action == 'play_music') {
      final path = command['id'];
      if (path != null) Get.find<MusicService>().playTrackByPath(path);
    } else if (action == 'play_hype') {
      final id = command['id'];
      if (id != null) {
        Get.find<HypeVoiceController>().playManualHype(id);
      }
    } else if (action == 'stop_all_media') {
      Get.find<MusicService>().stopMusic();
      Get.find<HypeVoiceController>().stopAudio();
      try {
        final scoreController = Get.find<ScoreController>();
        scoreController.ttsService.stop();
      } catch (e) {}
    }
  }

  /// Asks the phone to start the wear app over the SDK.
  ///
  /// Testing whether the watch's outbound channel only opens on a session the
  /// phone starts — the 2026-08-23 run had the watch unable to send at all
  /// (readyState 2, onopen never fired) while inbound worked fine.
  Future<String> launchWearApp() async {
    try {
      final raw = await platform.invokeMethod('launchWearApp');
      final map = raw is Map ? Map<String, dynamic>.from(raw) : {'ok': false};
      final detail = 'launchWearApp: ${map['ok'] == true ? 'ok' : map['detail']}';
      print('⌚ [WatchService] $detail');
      diagnostics.value = '${diagnostics.value}\n$detail';
      return detail;
    } catch (e) {
      print('⌚ [WatchService] launchWearApp error: $e');
      return 'launchWearApp error: $e';
    }
  }

  /// Send media list to connected watch.
  /// Hype is intentionally sent as empty for now — UI on watch is music-only
  /// until reactivity/payload issues are sorted out. Protocol shape preserved.
  Future<void> sendMediaList() async {
    if (!_isInitialized) return;

    final musicList = Get.find<MusicService>().getMusicList();

    final payload = {
      'action': 'media_list',
      'music': musicList,
      'hype': [],
    };

    // Sized before sending: ids are full device paths, so this is around 2KB
    // for 15 tracks and is the prime suspect for the list never arriving.
    final approxBytes = jsonEncode(payload).length;
    print('⌚ [WatchService] media_list: ${musicList.length} tracks, ~$approxBytes bytes');

    try {
      await platform.invokeMethod('sendMessage', {'data': payload});
      print('⌚ [WatchService] Media list sent OK (~$approxBytes bytes)');
    } catch (e) {
      print('⌚ [WatchService] Error sending media list (~$approxBytes bytes): $e');
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
