import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playback mode. The two are mutually exclusive on purpose.
///
/// Music and speech share the room, not the mixer: talking over a song that is
/// already playing is what kills the mood, so a session is either commentary or
/// music, never a fight between them.
class PlayMode {
  /// Score announcements and hype voice. Music only at the moments where
  /// nothing is being said — tension and win.
  static const commentary = 'commentary';

  /// Music runs continuously and nothing interrupts it. Announcements and hype
  /// are suppressed for the whole session.
  static const music = 'music';
}

/// Volumes and mode, in one place, shared by every player.
///
/// Before this there was no master volume at all: four sound sources each with
/// their own scale and no single knob. Every player now multiplies its own
/// level by [masterVolume] through [scale], so one control moves all of them
/// while their relative balance is preserved.
class AudioSettings extends GetxService {
  static const _pref = 'audio_';

  /// Multiplies every other volume. 0 mutes everything.
  final RxDouble masterVolume = 1.0.obs;

  final RxString mode = PlayMode.commentary.obs;

  /// Casual Vietnamese reading: from 11 up only the last digit is said,
  /// "mười lăm – mười ba" becomes "năm – ba". Round tens (10, 20, 30) keep
  /// their full name — "không" would say nothing useful.
  final RxBool shortScore = true.obs;

  /// The number to say for [n]. Only Vietnamese is shortened: English has no
  /// such habit ("five three" for 15-13 would just be wrong).
  static int spokenScore(int n, String lang) {
    final s = maybe;
    if (s == null || !s.shortScore.value) return n;
    if (!lang.toLowerCase().startsWith('vi')) return n;
    if (n < 10 || n % 10 == 0) return n;
    return n % 10;
  }

  bool get isMusicMode => mode.value == PlayMode.music;

  /// A player's own level, scaled by the master and clamped to a valid range.
  double scale(double own) {
    final v = own * masterVolume.value;
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
  }

  Future<AudioSettings> init() async {
    final prefs = await SharedPreferences.getInstance();
    masterVolume.value = prefs.getDouble('${_pref}master') ?? 1.0;
    mode.value = prefs.getString('${_pref}mode') ?? PlayMode.commentary;
    shortScore.value = prefs.getBool('${_pref}short_score') ?? true;
    return this;
  }

  Future<void> setMaster(double v) async {
    masterVolume.value = v.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_pref}master', masterVolume.value);
  }

  Future<void> setShortScore(bool v) async {
    shortScore.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_pref}short_score', v);
  }

  Future<void> setMode(String m) async {
    if (m != PlayMode.commentary && m != PlayMode.music) return;
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_pref}mode', m);
  }

  /// Convenience for callers that only have a Get context.
  static AudioSettings get i => Get.find<AudioSettings>();

  /// Safe lookup for services that may start before this is registered.
  static AudioSettings? get maybe =>
      Get.isRegistered<AudioSettings>() ? Get.find<AudioSettings>() : null;
}
