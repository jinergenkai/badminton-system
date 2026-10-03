import 'dart:async';

import 'package:flutter/services.dart';

import 'recording_session.dart';

/// The CameraX recorder in MainActivity/CameraRecorder.kt.
class CameraPlatform implements VideoSink {
  static const _ch = MethodChannel('com.voice_counter/camera');
  static const _events = EventChannel('com.voice_counter/camera_events');

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => (e as Map).map((k, v) => MapEntry('$k', v)));

  /// {camera: bool, audio: bool}
  Future<Map<String, bool>> requestPermissions() async {
    final r = await _ch.invokeMethod<Map>('requestPermissions');
    return {'camera': r?['camera'] == true, 'audio': r?['audio'] == true};
  }

  /// Binds [lens] ('back' | 'front'); returns the preview's Flutter texture
  /// id, or null without a preview (the board recording behind its UI).
  /// [overlay] burns the score and clock into the video.
  Future<int?> open(
      {String lens = 'back', bool preview = true, bool previewActive = true, bool overlay = true}) async {
    final r = await _ch.invokeMethod<Map>('open',
        {'lens': lens, 'preview': preview, 'previewActive': previewActive, 'overlay': overlay});
    return (r?['textureId'] as num?)?.toInt();
  }

  /// Focus / exposure lock (the camera's own 3A locks). Returns which of
  /// the two this camera actually locked: {focus, exposure}.
  Future<Map<String, bool>> setLock(bool on) async {
    final r = await _ch.invokeMethod<Map>('setLock', {'on': on});
    return {'focus': r?['focus'] == true, 'exposure': r?['exposure'] == true};
  }

  /// Feed the preview (true) or leave it dark (false), without rebinding:
  /// recording goes on either way.
  Future<void> setPreviewActive(bool on) => _ch.invokeMethod('setPreviewActive', {'on': on});

  /// What the overlay shows; [show] false hides the score (between sets).
  Future<void> setOverlay(int a, int b, bool show) =>
      _ch.invokeMethod('setOverlay', {'a': a, 'b': b, 'show': show});

  /// Restarts the app in a fresh process (role switch).
  static Future<void> restartApp() =>
      const MethodChannel('com.voice_counter/device').invokeMethod('restartApp');

  Future<void> close() => _ch.invokeMethod('close');

  @override
  Future<void> start(String dir, String name) => _ch.invokeMethod('start', {'dir': dir, 'name': name});

  @override
  Future<void> stop() => _ch.invokeMethod('stop');

  @override
  Future<bool> rename(String uri, String name) async =>
      await _ch.invokeMethod<bool>('rename', {'uri': uri, 'name': name}) ?? false;

  @override
  Future<String?> writeText(String dir, String name, String text, {String? uri}) =>
      _ch.invokeMethod<String>('writeText', {'dir': dir, 'name': name, 'text': text, 'uri': uri});

  /// {freeBytes, battery, tempC, charging}
  Future<Map<String, dynamic>> deviceStatus() async {
    final r = await _ch.invokeMethod<Map>('deviceStatus');
    return (r ?? {}).map((k, v) => MapEntry('$k', v));
  }

  /// The Wi-Fi gateway (on the phone's hotspot: the phone), or null.
  static Future<String?> gateway() async {
    try {
      return await _ch.invokeMethod<String>('gateway');
    } catch (_) {
      return null;
    }
  }

  /// Saved videos, newest first: {uri, name, size, durationMs, added, dir}.
  static Future<List<Map<String, dynamic>>> listVideos() async {
    final r = await _ch.invokeMethod<List>('listVideos') ?? const [];
    return [for (final e in r) (e as Map).map((k, v) => MapEntry('$k', v))];
  }

  static Future<Uint8List?> thumbnail(String uri, {int width = 320}) =>
      _ch.invokeMethod<Uint8List>('thumbnail', {'uri': uri, 'width': width});

  /// Deletes the videos and their .json files; returns how many went.
  static Future<int> deleteVideos(List<String> uris) async =>
      await _ch.invokeMethod<int>('deleteVideos', {'uris': uris}) ?? 0;

  /// Plays it in the system video player.
  static Future<bool> openVideo(String uri) async =>
      await _ch.invokeMethod<bool>('openVideo', {'uri': uri}) ?? false;

  Future<void> openHotspotSettings() => _ch.invokeMethod('openHotspot');

  Future<void> setDim(bool on) => _ch.invokeMethod('setDim', {'on': on});
}
