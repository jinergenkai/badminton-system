import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/team_config.dart';
import '../services/database_service.dart';
import '../controllers/score_controller.dart';

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

    // Update controller if it exists
    try {
      final controller = Get.find<ScoreController>();
      await controller.updateTeamConfig(newConfig);
    } catch (e) {
      // Controller not found, that's okay
    }

    Get.snackbar(
      'Settings Saved',
      'Team configuration updated successfully',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: const Text(
            'This will reset team names and colors to default values.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
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

      // Update controller
      try {
        final controller = Get.find<ScoreController>();
        await controller.updateTeamConfig(_teamConfig);
      } catch (e) {
        // Ignore
      }

      Get.snackbar(
        'Reset Complete',
        'Team configuration reset to defaults',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetToDefaults,
            tooltip: 'Reset to Defaults',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTeamConfig,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Team Configuration'),
          const SizedBox(height: 12),
          _buildTeamASettings(),
          const SizedBox(height: 20),
          _buildTeamBSettings(),
          const SizedBox(height: 32),
          _buildSectionHeader('Game Information'),
          const SizedBox(height: 12),
          _buildGameInfo(),
          const SizedBox(height: 32),
          _buildSectionHeader('About'),
          const SizedBox(height: 12),
          _buildAboutSection(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildTeamASettings() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: _teamConfig.teamAColor),
                const SizedBox(width: 12),
                const Text(
                  'Team A',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _teamAController,
              decoration: InputDecoration(
                labelText: 'Team A Name',
                hintText: 'Enter team name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.edit),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            const Text(
              'Team Color',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickColorForTeamA(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _teamConfig.teamAColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.palette, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to change color',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamBSettings() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: _teamConfig.teamBColor),
                const SizedBox(width: 12),
                const Text(
                  'Team B',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _teamBController,
              decoration: InputDecoration(
                labelText: 'Team B Name',
                hintText: 'Enter team name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.edit),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            const Text(
              'Team Color',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickColorForTeamB(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _teamConfig.teamBColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.palette, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to change color',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInfoRow(Icons.sports_tennis, 'Sport', 'Badminton'),
            const Divider(height: 24),
            _buildInfoRow(Icons.emoji_events, 'Score to Win', '21 points'),
            const Divider(height: 24),
            _buildInfoRow(Icons.trending_up, 'Win Margin', 'Lead by 2 points'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.blue),
            const SizedBox(height: 12),
            const Text(
              'Voice Counter',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              'A badminton score counter with voice recognition powered by Porcupine.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickColorForTeamA() async {
    Color? pickedColor = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Team A Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: _teamConfig.teamAColor,
            onColorChanged: (color) {},
            pickersEnabled: const {
              ColorPickerType.both: false,
              ColorPickerType.primary: true,
              ColorPickerType.accent: true,
              ColorPickerType.wheel: true,
            },
            heading: const Text('Select color'),
            subheading: const Text('Select color shade'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, _teamConfig.teamAColor);
            },
            child: const Text('Select'),
          ),
        ],
      ),
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
      builder: (context) => AlertDialog(
        title: const Text('Pick Team B Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: _teamConfig.teamBColor,
            onColorChanged: (color) {},
            pickersEnabled: const {
              ColorPickerType.both: false,
              ColorPickerType.primary: true,
              ColorPickerType.accent: true,
              ColorPickerType.wheel: true,
            },
            heading: const Text('Select color'),
            subheading: const Text('Select color shade'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, _teamConfig.teamBColor);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );

    if (pickedColor != null) {
      setState(() {
        _teamConfig = _teamConfig.copyWith(
          teamBColorHex: TeamConfig.colorToHex(pickedColor),
        );
      });
    }
  }
}
