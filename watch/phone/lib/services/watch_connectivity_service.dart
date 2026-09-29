import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:voice_counter/controllers/score_controller.dart';
import '../models/game_state.dart';
import 'music_service.dart';
import 'audio_settings.dart';
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

        // From here on, player state pushes itself whenever it changes.
        _watchPlayerState();

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

  /// One flat map, one name per setting, used in both directions.
  ///
  /// The watch never keeps its own copy of any of this: it asks for the state,
  /// renders whatever comes back, sends a single key when the user changes
  /// something, and re-renders from the echo. So there is exactly one source of
  /// truth — the phone — and no way for the two to disagree.
  Map<String, dynamic> _settingsSnapshot() {
    final audio = AudioSettings.i;
    final music = Get.find<MusicService>();
    final hype = Get.find<HypeVoiceController>();
    final score = Get.find<ScoreController>();
    final tts = score.ttsService;

    return {
      'mode': audio.mode.value,
      'master': (audio.masterVolume.value * 100).round(),
      'announceOn': score.scoreAnnouncementsEnabled.value,
      'announceVol': (tts.volume.value * 100).round(),
      'hypeOn': hype.isEnabled.value,
      'hypeVol': (hype.volume.value * 100).round(),
      'winOn': music.winMusicEnabled.value,
      'winVol': (music.winVolume.value * 100).round(),
      'tensionOn': music.tensionMusicEnabled.value,
      'tensionVol': (music.tensionVolume.value * 100).round(),
      'playMode': music.playMode.value,
    };
  }

  /// Echoes the whole state after any change, so the watch UI is never guessing.
  Future<void> sendSettingsState() async {
    if (!_isInitialized) return;
    try {
      await platform.invokeMethod('sendMessage', {
        'data': {'action': 'settings_state', 's': _settingsSnapshot()},
      });
    } catch (e) {
      print('⌚ [WatchService] Error sending settings: $e');
    }
  }

  /// Applies one key from the watch. Volumes arrive as 0..100 integers, which
  /// keeps the payload small and avoids float formatting over the wire.
  void _applySetting(String key, dynamic value) {
    final audio = AudioSettings.i;
    final music = Get.find<MusicService>();
    final hype = Get.find<HypeVoiceController>();
    final score = Get.find<ScoreController>();

    double pct(dynamic v) => ((v is num ? v.toDouble() : 0) / 100).clamp(0.0, 1.0);
    bool flag(dynamic v) => v == true;

    switch (key) {
      case 'mode':
        audio.setMode(value.toString());
        break;
      case 'master':
        audio.setMaster(pct(value));
        break;
      case 'announceOn':
        score.setScoreAnnouncementsEnabled(flag(value));
        break;
      case 'announceVol':
        score.ttsService.volume.value = pct(value);
        score.ttsService.saveVolumePreference();
        break;
      case 'hypeOn':
        hype.isEnabled.value = flag(value);
        hype.savePreferences();
        break;
      case 'hypeVol':
        hype.volume.value = pct(value);
        hype.savePreferences();
        break;
      case 'winOn':
        music.winMusicEnabled.value = flag(value);
        music.savePreferences();
        break;
      case 'winVol':
        music.winVolume.value = pct(value);
        music.savePreferences();
        break;
      case 'tensionOn':
        music.tensionMusicEnabled.value = flag(value);
        music.savePreferences();
        break;
      case 'tensionVol':
        music.tensionVolume.value = pct(value);
        music.savePreferences();
        break;
      case 'playMode':
        music.playMode.value = value.toString();
        music.savePreferences();
        break;
      default:
        print('⌚ [WatchService] Unknown setting key: $key');
        return;
    }
    print('⌚ [WatchService] Setting applied: $key = $value');
  }

  /// Transport state for the watch's music page. Kept apart from
  /// settings_state: this changes on its own as tracks end, whereas settings
  /// only change when someone asks.
  Future<void> sendPlayerState() async {
    if (!_isInitialized) return;
    try {
      final music = Get.find<MusicService>();
      await platform.invokeMethod('sendMessage', {
        'data': {
          'action': 'player_state',
          'p': {
            'playing': music.isPlaying.value,
            // Extension stripped: the watch has ~28 characters to show it in.
            'track': music.currentTrackName.value
                .replaceAll(RegExp(r'\.(mp3|m4a|aac)$'), ''),
          },
        },
      });
    } catch (e) {
      print('⌚ [WatchService] Error sending player state: $e');
    }
  }

  Timer? _playerEcho;

  /// Pushes player state whenever it actually changes, instead of echoing
  /// after each command.
  ///
  /// Echoing per command only covers changes the watch asked for. It misses
  /// the ones it did not: a track ending and non-stop moving to the next, or
  /// the phone starting win music. Watching the state itself covers every
  /// case, including picking a track, which is what was stale.
  ///
  /// Debounced because a transport call moves both flags in quick succession
  /// and a fade settles a moment later; without it one action would send
  /// several near-identical messages over BLE.
  void _watchPlayerState() {
    try {
      final music = Get.find<MusicService>();
      void schedule(_) {
        _playerEcho?.cancel();
        _playerEcho = Timer(const Duration(milliseconds: 350), sendPlayerState);
      }
      music.isPlaying.listen(schedule);
      music.currentTrackName.listen(schedule);
    } catch (e) {
      print('⌚ [WatchService] Could not watch player state: $e');
    }
  }

  Timer? _reminderTimer;

  /// Reminder for "pack up, court time is over", handed over by the watch.
  ///
  /// The band was the right place for this — it is on a wrist and rarely flat —
  /// but Mi Band 10 has no alarm service at all: @system.alarm resolves to null
  /// even with the feature declared. So the phone takes it, with the honest
  /// limitation that this only fires while the app is running. It usually is:
  /// the score screen holds a wakelock for the whole session.
  void _scheduleReminder(String at) {
    final parts = at.split(':');
    if (parts.length != 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, h, m);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));

    _reminderTimer?.cancel();
    final delay = target.difference(now);
    _reminderTimer = Timer(delay, _fireReminder);
    print('⌚ [WatchService] Reminder set for $at (in ${delay.inMinutes} min)');
  }

  void _fireReminder() {
    print('⌚ [WatchService] REMINDER: time to pack up');
    try {
      // Spoken at full volume regardless of the master, and repeated: this is
      // the one sound that matters more than the mix.
      final tts = Get.find<ScoreController>().ttsService;
      tts.speak('Het gio danh. Nho lay do.');
      Future.delayed(const Duration(seconds: 4),
          () => tts.speak('Het gio danh. Nho lay do.'));
    } catch (e) {
      print('⌚ [WatchService] Reminder speak failed: $e');
    }
    try {
      Get.find<MusicService>().playWinMusic();
    } catch (_) {}
  }

  void _handleWatchCommand(Map<String, dynamic> command) {
    final action = command['action'];
    if (action == 'request_settings') {
      sendSettingsState();
    } else if (action == 'set_setting') {
      final key = command['key'];
      if (key is String) {
        _applySetting(key, command['value']);
        // Echo back so the watch renders the state the phone actually holds,
        // not the state it assumed it would get.
        sendSettingsState();
      }
    } else if (action == 'request_player') {
      sendPlayerState();
    } else if (action == 'music_resume') {
      Get.find<MusicService>().resume();
    } else if (action == 'music_pause') {
      Get.find<MusicService>().pause();
    } else if (action == 'music_next') {
      Get.find<MusicService>().next();
    } else if (action == 'set_reminder') {
      final at = command['at'];
      if (at is String) _scheduleReminder(at);
    } else if (action == 'request_media_list') {
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

  /// Phone controls are requests, never score snapshots. The Band applies the
  /// operation to its durable match and publishes the authoritative result.
  Future<void> sendScoreCommand(String action, {Map<String, dynamic>? extra}) async {
    if (!_isInitialized) return;
    try {
      await platform.invokeMethod('sendMessage', {
        'data': {'action': action, ...?extra},
      });
    } catch (e) {
      print('⌚ [WatchService] Score command failed: $action: $e');
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
