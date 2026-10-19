import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'views/score_screen.dart';
import 'views/ui_kit.dart';
import 'services/database_service.dart';
import 'services/audio_settings.dart';
import 'services/player_service.dart';
import 'services/sync_service.dart';
import 'services/voice_clip_service.dart';
import 'services/sound_library_service.dart';
import 'services/phone_controls_service.dart';
import 'services/display_settings.dart';
import 'features/camera/camera_link_service.dart';
import 'features/camera/camera_settings.dart';
import 'features/camera/camera_screen.dart';
import 'features/camera/board_recorder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CameraSettings.load();

  // Camera mode: only the camera. No database, band link, voice, music or
  // sound library, so the corner phone spends its memory on recording.
  if (CameraSettings.role == CameraSettings.camera) {
    runApp(const CameraApp());
    return;
  }

  // Initialize Hive database
  await DatabaseService.initialize();

  // Registered before any player: every service multiplies its own level by
  // the master volume held here.
  await Get.putAsync(() => AudioSettings().init());
  await Get.putAsync(() => DisplaySettings().init());
  await Get.putAsync(() => PlayerService().init());
  await Get.putAsync(() => SyncService().init());
  await Get.putAsync(() => VoiceClipService().init());
  await Get.putAsync(() => SoundLibraryService().init());
  Get.put(PhoneControlsService());
  await Get.putAsync(() => CameraLinkService().init());

  runApp(const MyApp());
  // The board's own camera, if switched on: after the first frame, as it
  // needs the activity (permissions, camera lifecycle).
  final boardRec = Get.put(BoardRecorder());
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(boardRec.init()));
  unawaited(_dumpSettings());
  // Again whenever the app goes to the background, i.e. after tuning.
  AppLifecycleListener(onHide: () => unawaited(_dumpSettings()));
}

/// Every saved setting, as JSON, where adb can read it on a release build
/// (run-as needs a debug one) — how court-tuned levels become the defaults:
///   adb shell cat /sdcard/Android/data/com.hung.bandcounter/files/settings.json
Future<void> _dumpSettings() async {
  try {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return;
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();
    final map = {for (final k in keys) k: prefs.get(k)};
    await File('${dir.path}/settings.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Godminton',
      debugShowCheckedModeBanner: false,
      theme: Ui.theme().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Poppins'),
      ),
      home: const ScoreScreen(),
    );
  }
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
        title: 'Godminton camera',
        debugShowCheckedModeBanner: false,
        theme: Ui.theme().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Poppins'),
        ),
        home: const CameraScreen(),
      );
}
