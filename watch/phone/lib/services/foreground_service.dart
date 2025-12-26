import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class ForegroundService {
  static bool _isInitialized = false;

  // Initialize foreground task
  static Future<void> initialize() async {
    if (_isInitialized) return;

    print('🔔 [Foreground] Initializing foreground task...');

    // Initialize foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'voice_counter_channel',
        channelName: 'Voice Counter Service',
        channelDescription: 'Wake word detection and score tracking',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _isInitialized = true;
    print('🔔 [Foreground] ✅ Initialized');
  }

  // Start foreground service with initial scores
  static Future<ServiceRequestResult> start({
    required int teamAScore,
    required int teamBScore,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    print('🔔 [Foreground] Requesting notification permission...');

    // Request notification permission (required for Android 13+)
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();

    if (notificationPermission != NotificationPermission.granted) {
      final NotificationPermission requestResult =
          await FlutterForegroundTask.requestNotificationPermission();

      if (requestResult != NotificationPermission.granted) {
        print('🔔 [Foreground] ❌ Notification permission denied!');
        print(
          '🔔 [Foreground] ℹ️  Please enable notifications in system settings',
        );
        // Continue anyway - notification won't show but service will try to start
      }
    }

    print('🔔 [Foreground] ✅ Notification permission granted');
    print('🔔 [Foreground] Starting service...');

    // Start foreground service
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '🏸 Voice Counter',
      notificationText: _getScoreText(teamAScore, teamBScore),
      callback: startCallback,
    );

    print('🔔 [Foreground] Service start result: $result');

    return result;
  }

  // Update notification with new scores
  static Future<void> updateScores({
    required int teamAScore,
    required int teamBScore,
  }) async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) {
      return;
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: '🏸 Voice Counter',
      notificationText: _getScoreText(teamAScore, teamBScore),
    );

    print('🔔 [Foreground] Updated scores: $teamAScore - $teamBScore');
  }

  // Stop foreground service
  static Future<void> stop() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.stopService();
      print('🔔 [Foreground] ⏹️  Service stopped');
    }
  }

  // Helper to format score text
  static String _getScoreText(int teamAScore, int teamBScore) {
    return 'G: $teamAScore  |  Meow Meow: $teamBScore';
  }
}

// Callback for foreground task
@pragma('vm:entry-point')
void startCallback() {
  // This callback runs in a separate isolate
  FlutterForegroundTask.setTaskHandler(VoiceCounterTaskHandler());
}

// Task handler for foreground service
class VoiceCounterTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🔔 [Foreground] Task handler started');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // This is called periodically (every 5 seconds as configured)
    // We don't need to do anything here since we update manually
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('🔔 [Foreground] Task handler destroyed');
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button presses
  }

  @override
  void onNotificationPressed() {
    // Bring app to foreground when notification is tapped
    FlutterForegroundTask.launchApp('/');
  }
}
