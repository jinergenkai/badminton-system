import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// The phone's own media volume (not the app's Master).
///
/// The phone should sit at max and the band's Master does the turning down;
/// a phone left low makes Master 100% sound quiet for no visible reason. So
/// the board shows a warning while it is below max, and tapping it sets max.
///
/// Polled: Android has no public callback for volume changes, and one
/// getStreamVolume every 2 s costs nothing.
class PhoneVolumeService extends GetxService {
  static const _channel = MethodChannel('com.voice_counter/volume');

  final RxInt cur = 0.obs;
  final RxInt max = 0.obs;
  Timer? _poll;

  static PhoneVolumeService? get maybe =>
      Get.isRegistered<PhoneVolumeService>() ? Get.find<PhoneVolumeService>() : null;

  /// Unknown (max 0, e.g. not Android) counts as fine: no warning.
  bool get atMax => max.value == 0 || cur.value >= max.value;

  @override
  void onInit() {
    super.onInit();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> refresh() => _apply(_channel.invokeMethod('get'));

  Future<void> setMax() => _apply(_channel.invokeMethod('setMax'));

  Future<void> _apply(Future<dynamic> call) async {
    try {
      final m = await call;
      if (m is Map) {
        cur.value = (m['cur'] as num?)?.toInt() ?? 0;
        max.value = (m['max'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      max.value = 0;
    }
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }
}
