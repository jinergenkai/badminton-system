import 'package:hive/hive.dart';
import 'package:flutter/material.dart';

part 'team_config.g.dart';

@HiveType(typeId: 1)
class TeamConfig extends HiveObject {
  @HiveField(0)
  final String teamAName;

  @HiveField(1)
  final String teamBName;

  @HiveField(2)
  final String teamAColorHex; // Store as hex string

  @HiveField(3)
  final String teamBColorHex; // Store as hex string

  TeamConfig({
    this.teamAName = 'GAU GAU',
    this.teamBName = 'MEO MEO',
    this.teamAColorHex = '#0066CC', // Blue
    this.teamBColorHex = '#FF6600', // Orange
  });

  Color get teamAColor => _hexToColor(teamAColorHex);
  Color get teamBColor => _hexToColor(teamBColorHex);

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  TeamConfig copyWith({
    String? teamAName,
    String? teamBName,
    String? teamAColorHex,
    String? teamBColorHex,
  }) {
    return TeamConfig(
      teamAName: teamAName ?? this.teamAName,
      teamBName: teamBName ?? this.teamBName,
      teamAColorHex: teamAColorHex ?? this.teamAColorHex,
      teamBColorHex: teamBColorHex ?? this.teamBColorHex,
    );
  }

  static String colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }
}
