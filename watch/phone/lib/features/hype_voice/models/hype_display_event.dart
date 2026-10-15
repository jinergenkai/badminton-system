import 'package:flutter/material.dart';

class HypeDisplayEvent {
  final String voiceId;
  final String displayText;
  final String team; // 'A' | 'B'
  final Color glowColor;

  const HypeDisplayEvent({
    required this.voiceId,
    required this.displayText,
    required this.team,
    required this.glowColor,
  });
}
