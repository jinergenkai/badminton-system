import 'package:flutter/material.dart';

class CooldownBar extends StatelessWidget {
  final bool isActive;
  final double progress; // 0.0 to 1.0

  const CooldownBar({
    super.key,
    required this.isActive,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: (isActive || progress > 0) ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        height: 4, // Extremely thin line
        width: double.infinity,
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white.withOpacity(0.05),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
        ),
      ),
    );
  }
}
