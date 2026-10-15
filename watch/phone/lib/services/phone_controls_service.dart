import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone's media volume and this screen's brightness, shown as two
/// chips on the board.
///
/// Volume: the phone should sit at max and the band's Master does the turning
/// down; a phone left low makes Master 100% sound quiet for no visible
/// reason. Tap = max. Polled every 2 s — Android has no public callback for
/// volume changes, and one read costs nothing.
///
/// Brightness: max for this app's window only (no permission, the phone's
/// own setting is untouched), for courts in daylight. Tap toggles; kept
/// across launches.
class PhoneControlsService extends GetxService {
  static const _channel = MethodChannel('com.voice_counter/device');
  static const _prefBright = 'screen_bright_max';

  final RxInt vol = 0.obs;
  final RxInt volMax = 0.obs;
  final RxBool brightMax = false.obs;
  Timer? _poll;

  static PhoneControlsService? get maybe =>
      Get.isRegistered<PhoneControlsService>() ? Get.find<PhoneControlsService>() : null;

  /// Unknown (volMax 0, e.g. not Android) counts as fine.
  bool get volumeAtMax => volMax.value == 0 || vol.value >= volMax.value;

  @override
  void onInit() {
    super.onInit();
    _restore();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefBright) ?? true) {
      await _apply(_channel.invokeMethod('setBrightnessMax', {'on': true}));
    } else {
      await refresh();
    }
  }

  Future<void> refresh() => _apply(_channel.invokeMethod('state'));

  Future<void> setVolumeMax() => _apply(_channel.invokeMethod('setVolumeMax'));

  Future<void> toggleBrightness() async {
    final on = !brightMax.value;
    await _apply(_channel.invokeMethod('setBrightnessMax', {'on': on}));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBright, on);
  }

  Future<void> _apply(Future<dynamic> call) async {
    try {
      final m = await call;
      if (m is Map) {
        vol.value = (m['vol'] as num?)?.toInt() ?? 0;
        volMax.value = (m['volMax'] as num?)?.toInt() ?? 0;
        brightMax.value = m['brightMax'] == true;
      }
    } catch (_) {
      volMax.value = 0;
    }
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }
}
