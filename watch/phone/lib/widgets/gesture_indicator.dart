import 'package:flutter/material.dart';
import '../services/gesture_detection/gesture_camera_widget.dart';
import '../services/gesture_detection/gesture_detection_service.dart';

class GestureIndicator extends StatelessWidget {
  final bool isActive;
  final bool isDebugMode;
  final GestureDetectionService service;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const GestureIndicator({
    super.key,
    required this.isActive,
    required this.isDebugMode,
    required this.service,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? Colors.cyanAccent.withOpacity(0.4)
              : Colors.white.withOpacity(0.15),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Camera toggle button
          GestureDetector(
            onTap: onToggle,
            onLongPress: onLongPress,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isActive
                      ? [Colors.cyanAccent, Colors.cyan.shade700]
                      : [Colors.grey[700]!, Colors.grey[850]!],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isActive ? Colors.cyanAccent : Colors.grey)
                        .withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: isActive ? 3 : 0,
                  ),
                ],
              ),
              child: Icon(
                isActive ? Icons.videocam : Icons.videocam_off,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isActive
                      ? (isDebugMode ? 'DEBUG MODE' : 'GESTURE ON')
                      : 'HOLD TO DEBUG',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.cyanAccent : Colors.grey[400],
                    letterSpacing: 1.2,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(height: 4),
                  GestureStatusIndicator(service: service),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap to enable hand gestures',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
