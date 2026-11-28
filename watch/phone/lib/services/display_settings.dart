import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much the board animates. One switch for every effect, K.O included,
/// so the same build suits a cheap tablet and a strong phone.
///
///   high  every effect: serve strobe with glow, fire and balloons on a
///         streak, pulsing score, the full K.O overlay (rays, speed lines,
///         particles, shaking mascot). Long-running effects capped at 30 fps.
///   low   serve side = the dividing line, the other half dimmed, a slow
///         blink at 10 fps, no glow. No fire / balloons / pulse. K.O is the
///         mascot and the text popping in, nothing looping.
class DisplaySettings extends GetxService {
  static const high = 'high';
  static const low = 'low';
  static const _pref = 'graphics_level';

  final RxString level = low.obs;

  /// The dog/cat K.O picture over the board on a hype line. Off on a court
  /// where people only look at the score: the line still plays.
  final RxBool hypeOverlay = true.obs;
  static const _overlayPref = 'hype_overlay';

  bool get isHigh => level.value == high;

  /// Frame rate of the long-running effects.
  int get fps => isHigh ? 30 : 10;

  static DisplaySettings? get maybe =>
      Get.isRegistered<DisplaySettings>() ? Get.find<DisplaySettings>() : null;

  /// Default low: the court tablet is a cheap one.
  Future<DisplaySettings> init() async {
    final prefs = await SharedPreferences.getInstance();
    level.value = prefs.getString(_pref) ?? low;
    hypeOverlay.value = prefs.getBool(_overlayPref) ?? true;
    return this;
  }

  Future<void> setHypeOverlay(bool v) async {
    hypeOverlay.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_overlayPref, v);
  }

  Future<void> setLevel(String v) async {
    if (v != high && v != low) return;
    level.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pref, v);
  }
}
