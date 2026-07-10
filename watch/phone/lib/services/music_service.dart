import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemEntity;
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MusicService extends GetxController {
  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  // Reactive state
  final RxList<String> playlist = <String>[].obs;
  final RxBool isPlaying = false.obs;
  final RxBool isTensionMode = false.obs;
  final RxBool isNonStop = false.obs;
  final RxString currentTrackName = ''.obs;

  // Settings
  final RxBool winMusicEnabled = true.obs;
  final RxBool tensionMusicEnabled = true.obs;
  final RxDouble winVolume = 1.0.obs;
  final RxDouble tensionVolume = 0.45.obs;
  final RxInt tensionThreshold = 15.obs;
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
      if (isNonStop.value) {
        next();
      }
    });
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      await scanMusicFolder();
      return;
    }
    await _ensureMusicFolder();
    await _syncBundledTracks();
    await scanMusicFolder();
  }

  /// Mirrors assets/audio/music/ into the device folder on every launch: the
  /// folder always ends up containing exactly the currently bundled tracks.
  ///   - bundled tracks missing on disk (or whose bytes changed — size
  ///     mismatch) are (re)copied
  ///   - any file on disk that isn't a currently bundled track gets deleted,
  ///     including tracks left over from a previous asset set
  /// This folder is asset-managed only — manually dropped files are not
  /// preserved. Edit assets/audio/music/, then `flutter run` (or tap
  /// "Resync Tracks" in Settings), and the on-device list matches exactly.
  Future<void> _syncBundledTracks() async {
    if (kIsWeb || _musicFolderPath == null) return;
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final bundled = manifest.keys
          .where((k) => k.startsWith('assets/audio/music/') &&
              (k.endsWith('.mp3') || k.endsWith('.m4a') || k.endsWith('.aac')))
          .map((k) => Uri.decodeFull(k))
          .toList();

      final bundledFilenames = <String>{};
      for (final assetPath in bundled) {
        final filename = assetPath.split('/').last;
        bundledFilenames.add(filename);
        final target = File('$_musicFolderPath/$filename');
        final data = await rootBundle.load(assetPath);
        final assetBytes = data.buffer.asUint8List();
        final needsWrite = !await target.exists() ||
            await target.length() != assetBytes.length;
        if (needsWrite) {
          await target.writeAsBytes(assetBytes, flush: true);
          print('🎵 [Music] Seeded: $filename');
        }
      }

      final dir = Directory(_musicFolderPath!);
      if (await dir.exists()) {
        for (final entity in dir.listSync().whereType<File>()) {
          final name = entity.path.split('/').last;
          final ext = name.toLowerCase();
          final isAudio = ext.endsWith('.mp3') || ext.endsWith('.m4a') || ext.endsWith('.aac');
          if (isAudio && !bundledFilenames.contains(name)) {
            await entity.delete();
            print('🎵 [Music] Removed stale track: $name');
          }
        }
      }
    } catch (e) {
      print('🎵 [Music] Seed sync error: $e');
    }
  }

  Future<void> _ensureMusicFolder() async {
    if (kIsWeb) return;
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

  /// Re-runs the asset mirror sync (add/update/delete) then rescans, without
  /// requiring an app restart. Used by the "Resync Tracks" button in Settings.
  Future<void> resyncFromAssets() async {
    if (kIsWeb) {
      await scanMusicFolder();
      return;
    }
    await _syncBundledTracks();
    await scanMusicFolder();
  }

  Future<void> scanMusicFolder() async {
    if (kIsWeb) {
      await _scanAssetsOnly();
      return;
    }

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

  Future<void> _scanAssetsOnly() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final bundled = manifest.keys
          .where((k) => k.startsWith('assets/audio/music/') &&
              (k.endsWith('.mp3') || k.endsWith('.m4a') || k.endsWith('.aac')))
          .map((k) => Uri.decodeFull(k))
          .toList();
      playlist.value = bundled;
      print('🎵 [Music] Assets scanned: ${bundled.length} tracks');
    } catch (e) {
      print('🎵 [Music] Assets scan error: $e');
    }
  }

  String get musicFolderPath => _musicFolderPath ?? (kIsWeb ? '(assets)' : '(unavailable)');

  List<Map<String, String>> getMusicList() {
    return playlist.map((path) {
      return {
        'id': path,
        'name': path.split('/').last.replaceAll('.mp3', '').replaceAll('.m4a', '').replaceAll('.aac', '').replaceAll('_', ' ').toUpperCase(),
      };
    }).toList();
  }

  Future<void> playTrackByPath(String path) async {
    if (!playlist.contains(path)) {
      // If not in playlist, check if it's an asset path
      if (!path.startsWith('assets/')) return;
    }
    
    await stopMusic(fadeOut: isPlaying.value);
    await _playTrack(path, volume: winVolume.value);
  }

  String _getNextTrackPath() {
    if (playlist.isEmpty) return '';
    if (playMode.value == 'sequential') {
      final path = playlist[_sequentialIndex % playlist.length];
      _sequentialIndex = (_sequentialIndex + 1) % playlist.length;
      return path;
    }
    return playlist[_random.nextInt(playlist.length)];
  }

  Future<void> playWinMusic() async {
    if (!winMusicEnabled.value || playlist.isEmpty) return;
    final track = _getNextTrackPath();
    if (track.isEmpty) return;

    await stopMusic(fadeOut: isTensionMode.value);
    isTensionMode.value = false;

    await _playTrack(track, volume: winVolume.value, fadeDurationMs: 2500);
    print('🎵 [Music] Win: ${track.split('/').last}');
  }

  Future<void> playTensionMusic() async {
    if (!tensionMusicEnabled.value || playlist.isEmpty) {
      print('🎵 [Music] Tension skipped: enabled=${tensionMusicEnabled.value}, empty=${playlist.isEmpty}');
      return;
    }
    
    if (isTensionMode.value && isPlaying.value) {
      print('🎵 [Music] Already in Tension mode');
      return;
    }

    // Stop current normal music to transition to tension
    if (isPlaying.value) {
      print('🎵 [Music] Interrupting normal music for Tension');
      await stopMusic(fadeOut: true);
    }

    // Filter tracks containing "tension"
    final tensionTracks = playlist.where(
      (p) => p.toLowerCase().contains('tension')
    ).toList();

    String track;
    if (tensionTracks.isNotEmpty) {
      if (playMode.value == 'random') {
        track = tensionTracks[_random.nextInt(tensionTracks.length)];
      } else {
        track = tensionTracks[0];
      }
    } else {
      track = _getNextTrackPath();
    }

    print('🎵 [Music] Starting Tension: ${track.split('/').last} at volume ${tensionVolume.value}');
    await _playTrack(track, volume: tensionVolume.value, fadeDurationMs: 3000);
    isTensionMode.value = true;
  }


  Future<void> _playTrack(String track, {required double volume, int fadeDurationMs = 2000}) async {
    try {
      _currentVolume = 0.0;
      await _player.setVolume(0.0);
      
      if (track.startsWith('assets/')) {
        final assetPath = track.replaceFirst('assets/', '');
        await _player.play(AssetSource(assetPath));
      } else {
        await _player.play(DeviceFileSource(track));
      }
      
      currentTrackName.value = track.split('/').last;
      print('🎵 [Music] Playing track: ${currentTrackName.value} (target vol: $volume)');
      _fadeIn(volume > 0 ? volume : 0.5, durationMs: fadeDurationMs);
    } catch (e) {
      print('🎵 [Music] Play error: $e');
    }
  }

  Future<void> pause() async {
    if (isPlaying.value) {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    if (!isPlaying.value && currentTrackName.isNotEmpty) {
      await _player.resume();
    } else if (!isPlaying.value && playlist.isNotEmpty) {
      await next();
    }
  }

  Future<void> next() async {
    final track = _getNextTrackPath();
    if (track.isNotEmpty) {
      await stopMusic(fadeOut: false);
      await _playTrack(track, volume: isTensionMode.value ? tensionVolume.value : winVolume.value);
    }
  }

  Future<void> toggleNonStop() async {
    isNonStop.value = !isNonStop.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_pref}non_stop', isNonStop.value);
  }

  Future<void> stopMusic({bool fadeOut = true}) async {
    _fadeTimer?.cancel();
    if (!isPlaying.value && _player.state != PlayerState.paused) {
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
    currentTrackName.value = '';
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
    winVolume.value = prefs.getDouble('${_pref}win_volume') ?? 1.0;
    tensionVolume.value = prefs.getDouble('${_pref}tension_volume') ?? 0.45;
    tensionThreshold.value = prefs.getInt('${_pref}tension_threshold') ?? 15;
    playMode.value = prefs.getString('${_pref}play_mode') ?? 'random';
    isNonStop.value = prefs.getBool('${_pref}non_stop') ?? false;
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
