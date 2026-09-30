import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/score_screen.dart';
import 'views/ui_kit.dart';
import 'services/database_service.dart';
import 'services/audio_settings.dart';
import 'services/player_service.dart';
import 'services/voice_clip_service.dart';
import 'services/sound_library_service.dart';
import 'services/phone_controls_service.dart';
import 'services/display_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive database
  await DatabaseService.initialize();

  // Registered before any player: every service multiplies its own level by
  // the master volume held here.
  await Get.putAsync(() => AudioSettings().init());
  await Get.putAsync(() => DisplaySettings().init());
  await Get.putAsync(() => PlayerService().init());
  await Get.putAsync(() => VoiceClipService().init());
  await Get.putAsync(() => SoundLibraryService().init());
  Get.put(PhoneControlsService());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Badminton Voice Counter',
      debugShowCheckedModeBanner: false,
      theme: Ui.theme().copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      home: const ScoreScreen(),
    );
  }
}
