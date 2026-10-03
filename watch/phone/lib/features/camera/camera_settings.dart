import 'package:shared_preferences/shared_preferences.dart';

/// Per-device camera choices, read once at launch.
///
///   role        'board' (scoreboard; may also record itself) or 'camera'
///               (corner camera only: nothing else of the app is started)
///   cornerLens  lens in camera mode: 'back' | 'front'
///   boardRec    the board records with its own camera
///   boardLens   lens the board records with
///   overlay     score + clock burned into the video, camera mode
///   boardOverlay the same on the board's own recording. Off by default:
///               measured +22 % CPU on the court tablet (29 → 51 %)
class CameraSettings {
  static const board = 'board';
  static const camera = 'camera';

  static late SharedPreferences _p;

  static Future<void> load() async => _p = await SharedPreferences.getInstance();

  static String get role => _p.getString('device_role') ?? board;
  static Future<void> setRole(String v) => _p.setString('device_role', v);

  static String get cornerLens => _p.getString('camera_corner_lens') ?? 'back';
  static Future<void> setCornerLens(String v) => _p.setString('camera_corner_lens', v);

  static bool get boardRec => _p.getBool('camera_board_rec') ?? false;
  static Future<void> setBoardRec(bool v) => _p.setBool('camera_board_rec', v);

  static String get boardLens => _p.getString('camera_board_lens') ?? 'front';
  static Future<void> setBoardLens(String v) => _p.setString('camera_board_lens', v);

  static bool get overlay => _p.getBool('camera_overlay') ?? true;
  static Future<void> setOverlay(bool v) => _p.setBool('camera_overlay', v);

  /// Lock focus and exposure 2 s after recording starts.
  static bool get lock => _p.getBool('camera_lock') ?? true;
  static Future<void> setLock(bool v) => _p.setBool('camera_lock', v);

  static bool get boardOverlay => _p.getBool('camera_board_overlay') ?? false;
  static Future<void> setBoardOverlay(bool v) => _p.setBool('camera_board_overlay', v);
}
