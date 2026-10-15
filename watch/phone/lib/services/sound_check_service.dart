import 'dart:async';

import 'package:get/get.dart';

import '../features/hype_voice/services/hype_voice_controller.dart';
import 'music_service.dart';
import 'player_service.dart';
import 'score_announcer_service.dart';
import 'tts_service.dart';
import 'voice_clip_service.dart';

/// One thing the sound check plays. [run] starts it; the check then waits
/// [hold] before moving on, so each sound is heard on its own.
class SoundCheckStep {
  final String label;
  final Future<void> Function() run;
  final Duration hold;
  const SoundCheckStep(this.label, this.run, this.hold);
}

/// Plays every kind of sound the app makes, one after another, so volumes can
/// be set side by side instead of waiting for them to happen in a match.
///
/// While it runs, [active] is true and the score controller does not chain
/// hype / tension / win music off these sounds.
///
/// New kinds of sound: add them to [extraSteps] (or to [_steps]) — the check
/// must always cover everything the app can play.
class SoundCheckService extends GetxService {
  static bool active = false;

  /// Registration point for sound styles added later (e.g. funny moments).
  static final List<SoundCheckStep> extraSteps = [];

  final RxBool running = false.obs;
  final RxString current = ''.obs;
  final RxInt index = 0.obs;
  final RxInt total = 0.obs;

  /// Average ms to synthesize + boost one phrase on this device, measured by
  /// the first step. Shown in Settings: it says whether the tablet keeps up.
  final RxInt prepareMs = 0.obs;

  int _run = 0;

  ScoreAnnouncerService get _announcer => Get.find<ScoreAnnouncerService>();
  TtsService get _tts => Get.find<TtsService>();
  HypeVoiceController get _hype => Get.find<HypeVoiceController>();
  MusicService get _music => Get.find<MusicService>();

  bool get _vi => _tts.currentLanguageRx.value.toLowerCase().startsWith('vi');

  /// Real names when today's list has them, so the check sounds like a match.
  List<String> _names() {
    final today = PlayerService.maybe?.todayPlayers ?? const [];
    final n = today.map((p) => p.name).toList();
    while (n.length < 2) {
      n.add(n.isEmpty ? 'Hùng' : 'Quỳnh');
    }
    return n;
  }

  List<SoundCheckStep> _steps() {
    final names = _names();
    final pair = _vi ? 'Đội đỏ, ${names[0]} và ${names[1]}' : 'Red: ${names[0]} and ${names[1]}';
    final lang = _tts.currentLanguage;
    final phrases = [ScoreAnnouncerService.winnerLine(pair, lang)];
    return [
      // Rendered first so the steps below play the boosted clips, and timed:
      // this is the real cost of a phrase on this device.
      SoundCheckStep('Preparing TTS lines', () async {
        final clips = VoiceClipService.maybe;
        if (clips == null) return;
        clips.lastPrepareMs.value = 0;
        await clips.prepareAll(phrases);
        // Only a real synthesis says anything about the device; lines that
        // came from the cache leave the last measured value shown.
        if (clips.lastPrepareMs.value > 0) prepareMs.value = clips.lastPrepareMs.value;
      }, Duration.zero),
      SoundCheckStep('Score (15 – 13)', () => _announcer.announceScore(15, 13, 'A'),
          const Duration(milliseconds: 2800)),
      SoundCheckStep('Winner', () => _announcer.announceWinner(pair, 21, 18),
          const Duration(milliseconds: 5000)),
      SoundCheckStep('Hype voice', () => _hype.preview(), const Duration(milliseconds: 3500)),
      SoundCheckStep('Hype TTS line', () => _hype.previewTtsLine(), const Duration(milliseconds: 3500)),
      SoundCheckStep('Tension music', () => _music.previewTension(), const Duration(seconds: 6)),
      SoundCheckStep('Voice over music (ducking)', () async {
        _music.duck();
        await _announcer.announceScore(7, 6, 'B');
      }, const Duration(milliseconds: 2800)),
      SoundCheckStep('Music comes back', () async => _music.unduck(), const Duration(milliseconds: 2500)),
      SoundCheckStep('Win / playlist music', () => _music.previewWin(), const Duration(seconds: 6)),
      ...extraSteps,
    ];
  }

  Future<void> start() async {
    if (running.value) return;
    final myRun = ++_run;
    final steps = _steps();
    running.value = true;
    active = true;
    total.value = steps.length;
    try {
      for (var i = 0; i < steps.length; i++) {
        if (myRun != _run) return;
        index.value = i + 1;
        current.value = steps[i].label;
        try {
          await steps[i].run();
        } catch (e) {
          print('🔈 [SoundCheck] ${steps[i].label} failed: $e');
        }
        await Future.delayed(steps[i].hold);
      }
    } finally {
      if (myRun == _run) await _finish();
    }
  }

  Future<void> stop() async {
    _run++;
    await _announcer.stop();
    await _hype.stopAudio();
    await _finish();
  }

  Future<void> _finish() async {
    _music.unduck();
    await _music.stopMusic(fadeOut: true);
    running.value = false;
    current.value = '';
    index.value = 0;
    active = false;
  }
}
