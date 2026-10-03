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

  /// Binds the back camera; returns the preview's Flutter texture id.
  Future<int> open() async {
    final r = await _ch.invokeMethod<Map>('open');
    return (r!['textureId'] as num).toInt();
  }

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

  Future<void> openHotspotSettings() => _ch.invokeMethod('openHotspot');

  Future<void> setDim(bool on) => _ch.invokeMethod('setDim', {'on': on});
}
