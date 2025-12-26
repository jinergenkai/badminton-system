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
    // Always reserve fixed space to prevent layout shift
    return SizedBox(
      height: 50, // Fixed height
      child: AnimatedOpacity(
        opacity: (isActive || progress > 0) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cooldown label
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer, size: 16, color: Colors.orange[300]),
                  const SizedBox(width: 6),
                  Text(
                    'Cooldown ${(progress * 2).toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[300],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 8,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      // Animated progress fill
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 50),
                        width:
                            MediaQuery.of(context).size.width * progress * 0.85,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange[400]!,
                              Colors.deepOrange[600]!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
