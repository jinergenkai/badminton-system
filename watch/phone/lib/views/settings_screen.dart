import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/team_config.dart';
import '../services/database_service.dart';
import '../services/music_service.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';
import '../controllers/score_controller.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TeamConfig _teamConfig;
  late TextEditingController _teamAController;
  late TextEditingController _teamBController;

  @override
  void initState() {
    super.initState();
    _teamConfig = DatabaseService.getTeamConfig();
    _teamAController = TextEditingController(text: _teamConfig.teamAName);
    _teamBController = TextEditingController(text: _teamConfig.teamBName);
  }

  @override
  void dispose() {
    _teamAController.dispose();
    _teamBController.dispose();
    super.dispose();
  }

  Future<void> _saveTeamConfig() async {
    final newConfig = _teamConfig.copyWith(
      teamAName: _teamAController.text.trim(),
      teamBName: _teamBController.text.trim(),
    );

    await DatabaseService.saveTeamConfig(newConfig);

    try {
      final controller = Get.find<ScoreController>();
      await controller.updateTeamConfig(newConfig);
    } catch (e) {
      // Controller not found
    }

    Get.snackbar(
      'Settings Saved',
      'Team configuration updated successfully',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.greenAccent.withOpacity(0.8),
      colorText: Colors.black,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'SETTINGS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
            onPressed: _saveTeamConfig,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF1E1B4B),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 120, 16, 40),
          children: [
            _buildSectionHeader('TEAM PROFILES'),
            const SizedBox(height: 16),
            _buildTeamSettingsCard(
              title: 'TEAM A',
              controller: _teamAController,
              color: _teamConfig.teamAColor,
              onColorTap: _pickColorForTeamA,
              icon: Icons.shield,
            ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
            const SizedBox(height: 20),
            _buildTeamSettingsCard(
              title: 'TEAM B',
              controller: _teamBController,
              color: _teamConfig.teamBColor,
              onColorTap: _pickColorForTeamB,
              icon: Icons.shield_outlined,
            ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1),
            const SizedBox(height: 32),
            _buildSectionHeader('PREFERENCES'),
            const SizedBox(height: 16),
            _buildPreferencesCard().animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 32),
            _buildSectionHeader('MUSIC'),
            const SizedBox(height: 16),
            _buildMusicCard().animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 32),
            _buildDangerZone().animate().fadeIn(delay: 450.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.amber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTeamSettingsCard({
    required String title,
    required TextEditingController controller,
    required Color color,
    required VoidCallback onColorTap,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onColorTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 2),
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)
                    ],
                  ),
                  child: const Icon(Icons.palette, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Team Name',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color),
              ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              prefixIcon: Icon(Icons.edit, color: Colors.white.withOpacity(0.3)),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard() {
    final controller = Get.find<ScoreController>();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.notifications_active,
            title: 'Score Announcements',
            subtitle: 'Read scores aloud after points',
            trailing: Switch(
              value: true,
              onChanged: (v) {},
              activeColor: Colors.amber,
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          _buildSettingsTile(
            icon: Icons.vibration,
            title: 'Haptic Feedback',
            subtitle: 'Vibrate on score updates',
            trailing: Switch(
              value: true,
              onChanged: (v) {},
              activeColor: Colors.amber,
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          _buildSettingsTile(
            icon: Icons.timer,
            title: 'Cooldown Duration',
            subtitle: 'Prevent accidental double scoring',
            trailing: const Text('1.0s',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          Obx(() {
            final hype = Get.find<HypeVoiceController>();
            return _buildSettingsTile(
              icon: Icons.bolt,
              title: 'K.O Effect',
              subtitle: 'Speed lines on every point',
              trailing: Switch(
                value: hype.koEffectEnabled.value,
                onChanged: (v) => hype.koEffectEnabled.value = v,
                activeColor: Colors.amber,
              ),
            );
          }),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          Obx(() => Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.replay, color: Colors.white70, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Auto-start Next Game',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Text('After win screen',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('${controller.autoResetDelay.value}s',
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ],
                    ),
                    Slider(
                      value: controller.autoResetDelay.value.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 22,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white12,
                      onChanged: (v) => controller.autoResetDelay.value = v.round(),
                      onChangeEnd: (v) => controller.setAutoResetDelay(v.round()),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
      ),
      trailing: trailing,
    );
  }

  Widget _buildMusicCard() {
    final music = Get.find<MusicService>();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Win Music
          Obx(() => _buildSettingsTile(
                icon: Icons.emoji_events,
                title: 'Win Music',
                subtitle: 'KPOP after match ends (fade in)',
                trailing: Switch(
                  value: music.winMusicEnabled.value,
                  onChanged: (v) {
                    music.winMusicEnabled.value = v;
                    music.savePreferences();
                  },
                  activeColor: Colors.pinkAccent,
                ),
              )),
          Obx(() => music.winMusicEnabled.value
              ? _buildVolumeRow('Win Volume', music.winVolume, Colors.pinkAccent,
                  () => music.savePreferences())
              : const SizedBox.shrink()),
          // Play mode chips
          Obx(() => music.winMusicEnabled.value
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Text('Mode  ',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6), fontSize: 13)),
                      _buildModeChip('random', music),
                      const SizedBox(width: 8),
                      _buildModeChip('sequential', music),
                    ],
                  ),
                )
              : const SizedBox.shrink()),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),

          // Tension Music
          Obx(() => _buildSettingsTile(
                icon: Icons.whatshot,
                title: 'Tension Music',
                subtitle: 'Music when both reach ${music.tensionThreshold.value}-${music.tensionThreshold.value}',
                trailing: Switch(
                  value: music.tensionMusicEnabled.value,
                  onChanged: (v) {
                    music.tensionMusicEnabled.value = v;
                    music.savePreferences();
                  },
                  activeColor: Colors.orangeAccent,
                ),
              )),
          Obx(() => music.tensionMusicEnabled.value
              ? _buildVolumeRow('Tension Volume', music.tensionVolume, Colors.orangeAccent,
                  () => music.savePreferences())
              : const SizedBox.shrink()),
          Obx(() => music.tensionMusicEnabled.value
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Threshold',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13)),
                          Text('${music.tensionThreshold.value} pts each',
                              style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                      Slider(
                        value: music.tensionThreshold.value.toDouble(),
                        min: 15,
                        max: 25,
                        divisions: 10,
                        activeColor: Colors.orangeAccent,
                        inactiveColor: Colors.white12,
                        onChanged: (v) => music.tensionThreshold.value = v.round(),
                        onChangeEnd: (_) => music.savePreferences(),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink()),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),

          // Music Folder
          Obx(() {
            final count = music.playlist.length;
            final path = music.musicFolderPath;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_open, color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Text('Music Folder',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const Spacer(),
                      Text('$count tracks',
                          style: TextStyle(
                              color: count > 0 ? Colors.greenAccent : Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: path));
                      Get.snackbar('Copied', 'Folder path copied to clipboard',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.white12,
                          colorText: Colors.white,
                          margin: const EdgeInsets.all(16),
                          borderRadius: 12,
                          duration: const Duration(seconds: 2));
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              path,
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontFamily: 'monospace'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.copy, color: Colors.white38, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  count == 0
                      ? Text(
                          'Copy MP3 files to the folder above, then tap Rescan.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: music.playlist
                              .map((p) => Chip(
                                    label: Text(
                                      p.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|aac)$', caseSensitive: false), ''),
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                    backgroundColor: Colors.white10,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await music.scanMusicFolder();
                        Get.snackbar(
                          'Rescan Complete',
                          '${music.playlist.length} track(s) found',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.white12,
                          colorText: Colors.white,
                          margin: const EdgeInsets.all(16),
                          borderRadius: 12,
                          duration: const Duration(seconds: 2),
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Rescan Folder'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.pinkAccent,
                        side: const BorderSide(color: Colors.pinkAccent, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVolumeRow(String label, RxDouble rxVolume, Color color, VoidCallback? onSave) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Obx(() => Row(
            children: [
              Icon(Icons.volume_up, color: color.withOpacity(0.7), size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              const Spacer(),
              Text('${(rxVolume.value * 100).round()}%',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              Expanded(
                child: Slider(
                  value: rxVolume.value,
                  min: 0.0,
                  max: 1.0,
                  activeColor: color,
                  inactiveColor: Colors.white12,
                  onChanged: (v) => rxVolume.value = v,
                  onChangeEnd: (_) => onSave?.call(),
                ),
              ),
            ],
          )),
    );
  }

  Widget _buildModeChip(String mode, MusicService music) {
    return Obx(() {
      final selected = music.playMode.value == mode;
      return GestureDetector(
        onTap: () {
          music.playMode.value = mode;
          music.savePreferences();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.pinkAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? Colors.pinkAccent : Colors.white24, width: 1),
          ),
          child: Text(
            mode == 'random' ? 'Random' : 'Sequential',
            style: TextStyle(
                color: selected ? Colors.pinkAccent : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          ),
        ),
      );
    });
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('DANGER ZONE'),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _resetToDefaults,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.restore, color: Colors.redAccent),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reset to Defaults',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Factory reset all configurations',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.redAccent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        title: const Text('Reset to Defaults?', style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will reset team names and colors to default values.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESET', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.resetTeamConfig();
      setState(() {
        _teamConfig = TeamConfig();
        _teamAController.text = _teamConfig.teamAName;
        _teamBController.text = _teamConfig.teamBName;
      });

      try {
        final controller = Get.find<ScoreController>();
        await controller.updateTeamConfig(_teamConfig);
      } catch (e) {}

      Get.snackbar(
        'Reset Complete',
        'Configuration reset to defaults',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _pickColorForTeamA() async {
    Color? pickedColor = await showDialog<Color>(
      context: context,
      builder: (context) => _buildColorPickerDialog(_teamConfig.teamAColor),
    );

    if (pickedColor != null) {
      setState(() {
        _teamConfig = _teamConfig.copyWith(
          teamAColorHex: TeamConfig.colorToHex(pickedColor),
        );
      });
    }
  }

  Future<void> _pickColorForTeamB() async {
    Color? pickedColor = await showDialog<Color>(
      context: context,
      builder: (context) => _buildColorPickerDialog(_teamConfig.teamBColor),
    );

    if (pickedColor != null) {
      setState(() {
        _teamConfig = _teamConfig.copyWith(
          teamBColorHex: TeamConfig.colorToHex(pickedColor),
        );
      });
    }
  }

  Widget _buildColorPickerDialog(Color initialColor) {
    Color selectedColor = initialColor;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1B4B),
      title: const Text('Select Team Color', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: ColorPicker(
          color: initialColor,
          onColorChanged: (color) => selectedColor = color,
          pickersEnabled: const {
            ColorPickerType.both: false,
            ColorPickerType.primary: true,
            ColorPickerType.accent: true,
            ColorPickerType.wheel: true,
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, selectedColor),
          child: const Text('SELECT', style: TextStyle(color: Colors.amber)),
        ),
      ],
    );
  }
}
