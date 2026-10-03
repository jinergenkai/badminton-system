import 'package:get/get.dart';

import 'camera_rig.dart';
import 'camera_settings.dart';

/// The board recording with its own camera, behind the scoreboard
/// (docs/camera-recording-requirements.md §6). Its preview is shown only in
/// Utility, and fed only then: the board keeps the whole screen. Match events come straight from ScoreController, on
/// this device's clock, so there is no link and no offset.
///
/// Off by default: it adds a video encoder to the tablet that also runs the
/// band link, the voice and the music.
class BoardRecorder extends GetxService {
  CameraRig? rig;
  final RxBool on = false.obs;

  /// Called after recording starts, to learn the set in progress.
  void Function()? onStarted;

  static BoardRecorder? get maybe =>
      Get.isRegistered<BoardRecorder>() ? Get.find<BoardRecorder>() : null;

  bool get recording => rig?.recording.value ?? false;

  Future<BoardRecorder> init() async {
    if (CameraSettings.boardRec) await enable(true);
    return this;
  }

  Future<void> enable(bool v) async {
    await CameraSettings.setBoardRec(v);
    on.value = v;
    if (v) {
      final r = rig ??
          CameraRig(
            role: 'front',
            lens: CameraSettings.boardLens,
            overlay: CameraSettings.boardOverlay,
            // Bound but dark: fed only while Utility shows it.
            preview: true,
            previewActive: false,
          );
      rig = r;
      if (!r.opened.value && !await r.open()) return;
      await r.start();
      onStarted?.call();
    } else {
      await rig?.close();
      rig = null;
    }
  }

  /// Lens / overlay changed: restart with the new settings.
  Future<void> reconfigure() async {
    if (!on.value) return;
    await enable(false);
    await enable(true);
  }

  /// A match event from the band, as sent to the corner camera.
  void feed(String type, Map<String, dynamic> fields) {
    final r = rig;
    if (r == null) return;
    final m = {'type': type, ...fields};
    r.live(m);
    if (!r.recording.value) return;
    r.session.handle(m, DateTime.now().millisecondsSinceEpoch).catchError((_) {});
  }
}
