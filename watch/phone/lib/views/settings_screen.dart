import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/team_config.dart';
import '../services/database_service.dart';
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
            _buildDangerZone().animate().fadeIn(delay: 400.ms),
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
            trailing: const Text('1.0s', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
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
