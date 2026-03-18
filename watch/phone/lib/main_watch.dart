import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'views/watch/watch_score_screen.dart';
import 'services/database_service.dart';

/// Main entry point for WearOS watch app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive database
  await DatabaseService.initialize();

  runApp(const WatchApp());
}

class WatchApp extends StatelessWidget {
  const WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Voice Counter Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WatchScoreScreen(),
    );
  }
}
