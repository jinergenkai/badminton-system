import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

class MusicService extends GetxController {
  final AudioPlayer _player = AudioPlayer();

  // Reactive state
  final RxList<String> playlist = <String>[].obs;
  final RxBool isPlaying = false.obs;
  final RxBool isTensionMode = false.obs;

  // Settings
  final RxBool winMusicEnabled = true.obs;
  final RxBool tensionMusicEnabled = true.obs;
  final RxDouble winVolume = 0.7.obs;
  final RxDouble tensionVolume = 0.45.obs;
  final RxInt tensionThreshold = 20.obs;
  final RxString playMode = 'random'.obs; // 'random' | 'sequential'

  int _sequentialIndex = 0;
  double _currentVolume = 0.0;
  Timer? _fadeTimer;
  String? _musicFolderPath;

  static const String _pref = 'music_';

  @override
  void onInit() {
    super.onInit();
    _loadPreferences();
    _player.onPlayerStateChanged.listen((state) {
      isPlaying.value = state == PlayerState.playing;
    });
    _player.onPlayerComplete.listen((_) {
      isPlaying.value = false;
      isTensionMode.value = false;
    });
  }

  Future<void> initialize() async {
    await _ensureMusicFolder();
    await _seedDefaultTracks();
    await scanMusicFolder();
  }

  /// Copy bundled default tracks from assets → device folder.
  /// Runs every launch but only copies files not already present — safe to re-run.
  Future<void> _seedDefaultTracks() async {
    if (_musicFolderPath == null) return;
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final bundled = manifest.keys
          .where((k) => k.startsWith('assets/audio/music/') &&
              (k.endsWith('.mp3') || k.endsWith('.m4a') || k.endsWith('.aac')))
          .toList();

      if (bundled.isEmpty) {
        print('🎵 [Music] No bundled tracks in assets/audio/music/');
        return;
      }

      for (final assetPath in bundled) {
        final filename = assetPath.split('/').last;
        final target = File('$_musicFolderPath/$filename');
        if (await target.exists()) continue; // never overwrite user files
        final data = await rootBundle.load(assetPath);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
        print('🎵 [Music] Seeded: $filename');
      }
    } catch (e) {
      print('🎵 [Music] Seed error: $e');
    }
  }

  Future<void> _ensureMusicFolder() async {
    try {
      // Try external app-specific storage first (no permission needed, user-visible)
      Directory? base = await getExternalStorageDirectory();
      // Fallback to internal documents if external unavailable (emulator / some devices)
      base ??= await getApplicationDocumentsDirectory();
      final musicDir = Directory('${base.path}/music');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);
      _musicFolderPath = musicDir.path;
      print('🎵 [Music] Folder: $_musicFolderPath');
    } catch (e) {
      print('🎵 [Music] Folder init error: $e');
    }
  }

  Future<void> scanMusicFolder() async {
    if (_musicFolderPath == null) await _ensureMusicFolder();
    if (_musicFolderPath == null) {
      print('🎵 [Music] Cannot scan: folder path is null');
      return;
    }
    try {
      final dir = Directory(_musicFolderPath!);
      if (!await dir.exists()) {
        print('🎵 [Music] Directory does not exist: $_musicFolderPath');
        return;
      }
      final all = dir.listSync();
      print('🎵 [Music] Raw entries in folder (${all.length}): ${all.map((e) => e.path.split('/').last).join(', ')}');
      final files = all
          .whereType<File>()
          .where((f) {
            final ext = f.path.toLowerCase();
            return ext.endsWith('.mp3') || ext.endsWith('.m4a') || ext.endsWith('.aac');
          })
          .map((f) => f.path)
          .toList()
        ..sort();
      playlist.value = files;
      print('🎵 [Music] Scanned: ${files.length} tracks');
    } catch (e) {
      print('🎵 [Music] Scan error: $e');
    }
  }

  String get musicFolderPath => _musicFolderPath ?? '(unavailable)';

  String _getNextTrack() {
    if (playlist.isEmpty) return '';
    if (playMode.value == 'sequential') {
      final path = playlist[_sequentialIndex % playlist.length];
      _sequentialIndex = (_sequentialIndex + 1) % playlist.length;
      return path;
    }
    return playlist[Random().nextInt(playlist.length)];
  }

  Future<void> playWinMusic() async {
    if (!winMusicEnabled.value || playlist.isEmpty) return;
    final track = _getNextTrack();
    if (track.isEmpty) return;

    await stopMusic(fadeOut: isTensionMode.value);
    isTensionMode.value = false;

    try {
      _currentVolume = 0.0;
      await _player.setVolume(0.0);
      await _player.play(DeviceFileSource(track));
      _fadeIn(winVolume.value, durationMs: 2500);
      print('🎵 [Music] Win: ${track.split('/').last}');
    } catch (e) {
      print('🎵 [Music] Win play error: $e');
    }
  }

  Future<void> playTensionMusic() async {
    if (!tensionMusicEnabled.value || isPlaying.value || playlist.isEmpty) return;

    // Prefer a file named "tension" if exists, else random
    final track = playlist.firstWhere(
      (p) => p.toLowerCase().contains('tension'),
      orElse: () => playlist[Random().nextInt(playlist.length)],
    );

    try {
      _currentVolume = 0.0;
      await _player.setVolume(0.0);
      await _player.play(DeviceFileSource(track));
      isTensionMode.value = true;
      _fadeIn(tensionVolume.value, durationMs: 3000);
      print('🎵 [Music] Tension: ${track.split('/').last}');
    } catch (e) {
      print('🎵 [Music] Tension play error: $e');
    }
  }

  Future<void> stopMusic({bool fadeOut = true}) async {
    _fadeTimer?.cancel();
    if (!isPlaying.value) {
      isTensionMode.value = false;
      return;
    }
    if (fadeOut && _currentVolume > 0) {
      await _fadeOut(durationMs: 1200);
    }
    await _player.stop();
    _currentVolume = 0.0;
    isPlaying.value = false;
    isTensionMode.value = false;
  }

  void _fadeIn(double target, {int durationMs = 2000}) {
    _fadeTimer?.cancel();
    const steps = 25;
    final stepDelay = durationMs ~/ steps;
    final stepSize = target / steps;

    _fadeTimer = Timer.periodic(Duration(milliseconds: stepDelay), (timer) {
      _currentVolume = (_currentVolume + stepSize).clamp(0.0, target);
      _player.setVolume(_currentVolume);
      if (_currentVolume >= target) timer.cancel();
    });
  }

  Future<void> _fadeOut({int durationMs = 1200}) async {
    _fadeTimer?.cancel();
    if (_currentVolume <= 0) return;
    const steps = 20;
    final stepDelay = durationMs ~/ steps;
    final stepSize = _currentVolume / steps;

    final completer = Completer<void>();
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepDelay), (timer) {
      _currentVolume = (_currentVolume - stepSize).clamp(0.0, 1.0);
      _player.setVolume(_currentVolume);
      if (_currentVolume <= 0.01) {
        _currentVolume = 0.0;
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    winMusicEnabled.value = prefs.getBool('${_pref}win_enabled') ?? true;
    tensionMusicEnabled.value = prefs.getBool('${_pref}tension_enabled') ?? true;
    winVolume.value = prefs.getDouble('${_pref}win_volume') ?? 0.7;
    tensionVolume.value = prefs.getDouble('${_pref}tension_volume') ?? 0.45;
    tensionThreshold.value = prefs.getInt('${_pref}tension_threshold') ?? 20;
    playMode.value = prefs.getString('${_pref}play_mode') ?? 'random';
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_pref}win_enabled', winMusicEnabled.value);
    await prefs.setBool('${_pref}tension_enabled', tensionMusicEnabled.value);
    await prefs.setDouble('${_pref}win_volume', winVolume.value);
    await prefs.setDouble('${_pref}tension_volume', tensionVolume.value);
    await prefs.setInt('${_pref}tension_threshold', tensionThreshold.value);
    await prefs.setString('${_pref}play_mode', playMode.value);
  }

  @override
  void onClose() {
    _fadeTimer?.cancel();
    _player.dispose();
    super.onClose();
  }
}
