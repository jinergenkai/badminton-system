import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/music_service.dart';
import '../services/audio_settings.dart';
import '../services/tts_service.dart';
import '../services/sound_check_service.dart';
import '../services/display_settings.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';
import '../controllers/score_controller.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ui_kit.dart';
import 'sync_screen.dart';

/// Phone settings. The band is the remote: anything it can set (mode, the
/// on/off switches, master) is mirrored here, and everything else lives
/// only here. Which sounds exist and when they play is the Sound Library.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return UiPage(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const UiSection('Sound'),
          _buildSoundCard().animate().fadeIn(delay: 50.ms),
          const SizedBox(height: 24),
          const UiSection('Game & display'),
          _buildGameCard().animate().fadeIn(delay: 150.ms),
          const SizedBox(height: 24),
          const UiSection('Đồng bộ'),
          GestureDetector(
            onTap: () => Get.to(() => const SyncScreen()),
            child: _card([
              _tile(
                icon: Icons.leaderboard_rounded,
                title: 'Đồng bộ ranking',
                subtitle: 'Kéo danh bạ · đẩy trận lên backend',
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              ),
            ]),
          ).animate().fadeIn(delay: 250.ms),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(Ui.radius),
        border: Border.all(color: Ui.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _div() => Divider(color: Colors.white.withOpacity(0.05), height: 1);

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
      trailing: trailing,
    );
  }

  // ── SOUND ─────────────────────────────────────────────────────────────

  /// Every volume and switch in one place, under the button that plays them all.
  Widget _buildSoundCard() {
    final audio = Get.find<AudioSettings>();
    final tts = Get.find<TtsService>();
    final hype = Get.find<HypeVoiceController>();
    final music = Get.find<MusicService>();
    final score = Get.find<ScoreController>();
    final check = Get.isRegistered<SoundCheckService>()
        ? Get.find<SoundCheckService>()
        : Get.put(SoundCheckService());

    return _card([
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Obx(() {
          final on = check.running.value;
          return Row(
            children: [
              FilledButton.icon(
                onPressed: on ? check.stop : check.start,
                icon: Icon(on ? Icons.stop : Icons.play_arrow),
                label: Text(on ? 'Stop' : 'Sound check'),
                style: FilledButton.styleFrom(
                  backgroundColor: on ? Colors.redAccent : Colors.amber,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  on
                      ? '${check.index.value}/${check.total.value}  ${check.current.value}'
                      : check.prepareMs.value > 0
                          ? 'TTS line: ${check.prepareMs.value} ms each on this device'
                          : 'Plays every sound once, in turn',
                  style: TextStyle(color: on ? Colors.white : Colors.white54, fontSize: 13),
                ),
              ),
            ],
          );
        }),
      ),
      _div(),
      // Mode first: it decides whether anything below it is audible at all.
      Obx(() {
        final isMusic = audio.isMusicMode;
        return _tile(
          icon: isMusic ? Icons.music_note : Icons.record_voice_over,
          title: isMusic ? 'Music Mode' : 'Commentary Mode',
          subtitle: isMusic
              ? 'Music runs non-stop, nothing talks over it'
              : 'Score + hype; music only on tension and win',
          trailing: Switch(
            value: isMusic,
            onChanged: (v) => audio.setMode(v ? PlayMode.music : PlayMode.commentary),
            activeColor: Colors.amber,
          ),
        );
      }),
      _div(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Obx(() => Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _toggle('Score', score.scoreAnnouncementsEnabled.value, Colors.amber,
                    score.setScoreAnnouncementsEnabled),
                _toggle('Hype', hype.isEnabled.value, Colors.cyanAccent, (v) {
                  hype.isEnabled.value = v;
                  hype.savePreferences();
                }),
                _toggle('Tension', music.tensionMusicEnabled.value, Colors.orangeAccent, (v) {
                  music.tensionMusicEnabled.value = v;
                  music.savePreferences();
                }),
                _toggle('Win music', music.winMusicEnabled.value, Colors.pinkAccent, (v) {
                  music.winMusicEnabled.value = v;
                  music.savePreferences();
                }),
              ],
            )),
      ),
      _div(),
      const SizedBox(height: 8),
      _volume('Master', 'Everything below at once — the big slider on the band',
          audio.masterVolume, Colors.amber, () => audio.setMaster(audio.masterVolume.value)),
      _volume('Voice (all)', 'Every spoken line: score, names, winner',
          tts.volume, Colors.amber, tts.saveVolumePreference),
      _volume('Hype', 'Streak and highlight voices', hype.volume, Colors.cyanAccent,
          hype.savePreferences),
      _volume('Tension music', 'When both teams reach the threshold below',
          music.tensionVolume, Colors.orangeAccent, music.savePreferences),
      _volume('Win / playlist music', 'After a win, and all of Music mode',
          music.winVolume, Colors.pinkAccent, music.savePreferences),
      _volume('Music under voice', 'Music level while anyone talks; back up after',
          music.duckLevel, Colors.white70, music.savePreferences),
      _div(),
      Obx(() => _tile(
            icon: Icons.short_text,
            title: 'Short score reading',
            subtitle: 'Vietnamese: 15 – 13 is read "năm – ba"',
            trailing: Switch(
              value: audio.shortScore.value,
              onChanged: audio.setShortScore,
              activeColor: Colors.amber,
            ),
          )),
      _div(),
      Obx(() => Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text('Tension from', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                const Spacer(),
                Text('${music.tensionThreshold.value} – ${music.tensionThreshold.value}',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          )),
      Obx(() => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Slider(
              value: music.tensionThreshold.value.toDouble(),
              min: 15,
              max: 25,
              divisions: 10,
              activeColor: Colors.orangeAccent,
              inactiveColor: Colors.white12,
              onChanged: (v) => music.tensionThreshold.value = v.round(),
              onChangeEnd: (_) => music.savePreferences(),
            ),
          )),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Text('Playlist order  ', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
            _chip('Random', music.playMode, 'random', music.savePreferences),
            const SizedBox(width: 8),
            _chip('Sequential', music.playMode, 'sequential', music.savePreferences),
          ],
        ),
      ),
      _div(),
      _buildLanguageRow(tts),
    ]);
  }

  Widget _toggle(String label, bool on, Color color, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: on,
      onSelected: onChanged,
      showCheckmark: false,
      avatar: Icon(on ? Icons.volume_up : Icons.volume_off, size: 16, color: on ? color : Colors.white38),
      labelStyle: TextStyle(
          color: on ? color : Colors.white54, fontSize: 12, fontWeight: on ? FontWeight.bold : FontWeight.normal),
      backgroundColor: Colors.white.withOpacity(0.05),
      selectedColor: color.withOpacity(0.18),
      side: BorderSide(color: on ? color : Colors.white24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  /// A level with its name, what it affects, and the value in percent.
  Widget _volume(String label, String desc, RxDouble rx, Color color, VoidCallback? onSave,
      {double max = 1.0, int? divisions}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
      child: Obx(() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.volume_up, color: color.withOpacity(0.7), size: 18),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${(rx.value * 100).round()}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 8),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11)),
              ),
              Slider(
                value: rx.value.clamp(0.0, max),
                min: 0.0,
                max: max,
                divisions: divisions,
                activeColor: color,
                inactiveColor: Colors.white12,
                onChanged: (v) => rx.value = v,
                onChangeEnd: (_) => onSave?.call(),
              ),
            ],
          )),
    );
  }

  Widget _chip(String label, RxString rx, String value, VoidCallback onSave) {
    return Obx(() {
      final selected = rx.value == value;
      return GestureDetector(
        onTap: () {
          rx.value = value;
          onSave();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.pinkAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.pinkAccent : Colors.white24),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.pinkAccent : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      );
    });
  }

  Widget _buildLanguageRow(TtsService tts) {
    return Obx(() {
      final isVi = tts.currentLanguageRx.value.startsWith('vi');
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            const Icon(Icons.language, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Language',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            _langChip('English', !isVi, () => tts.setLanguage('en-US')),
            const SizedBox(width: 8),
            _langChip('Tiếng Việt', isVi, () => tts.setLanguage('vi-VN')),
          ],
        ),
      );
    });
  }

  Widget _langChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.amber.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.amber : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.amber : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // ── GAME ──────────────────────────────────────────────────────────────

  Widget _buildGameCard() {
    final controller = Get.find<ScoreController>();
    final fx = Get.find<DisplaySettings>();
    return _card([
      Obx(() {
        final high = fx.isHigh;
        return _tile(
          icon: Icons.auto_awesome,
          title: 'Graphics',
          subtitle: high
              ? 'High: glow, fire, balloons, full K.O — 30 fps'
              : 'Low: line + dim side + slow blink, light K.O — 10 fps, saves battery',
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Colors.amber.withOpacity(0.25),
              selectedForegroundColor: Colors.amber,
              foregroundColor: Colors.white54,
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(value: DisplaySettings.low, label: Text('Low')),
              ButtonSegment(value: DisplaySettings.high, label: Text('High')),
            ],
            selected: {fx.level.value},
            onSelectionChanged: (v) => fx.setLevel(v.first),
          ),
        );
      }),
      _div(),
      Obx(() => _tile(
            icon: Icons.swap_horiz,
            title: 'Swap Sides',
            subtitle: controller.sidesSwapped.value
                ? 'Blue on the left, red on the right'
                : 'Red on the left, blue on the right',
            trailing: Switch(
              value: controller.sidesSwapped.value,
              onChanged: controller.setSidesSwapped,
              activeColor: Colors.amber,
            ),
          )),
      _div(),
      Obx(() => Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.replay, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-start Next Game',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('Phone only: with the band connected, the band starts the next set',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                Text('${controller.autoResetDelay.value}s',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          )),
      Obx(() => Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Slider(
              value: controller.autoResetDelay.value.toDouble(),
              min: 10,
              max: 120,
              divisions: 22,
              activeColor: Colors.amber,
              inactiveColor: Colors.white12,
              onChanged: (v) => controller.autoResetDelay.value = v.round(),
              onChangeEnd: (v) => controller.setAutoResetDelay(v.round()),
            ),
          )),
    ]);
  }
}
