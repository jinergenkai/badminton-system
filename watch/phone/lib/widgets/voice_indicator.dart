import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class VoiceIndicator extends StatelessWidget {
  final bool isListening;
  final String lastCommand;
  final VoidCallback onToggle;
  final bool isWatchConnected;

  const VoiceIndicator({
    super.key,
    required this.isListening,
    required this.lastCommand,
    required this.onToggle,
    this.isWatchConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isListening
              ? Colors.greenAccent.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Microphone Button
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isListening
                      ? [Colors.greenAccent, Colors.green.shade700]
                      : [Colors.grey[800]!, Colors.grey[900]!],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  if (isListening)
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Status and Command
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isListening ? 'LISTENING' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: isListening ? Colors.greenAccent : Colors.grey[500],
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    // Watch Status Icon
                    Icon(
                      Icons.watch,
                      size: 14,
                      color: isWatchConnected ? Colors.blueAccent : Colors.white24,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isWatchConnected ? 'WATCH ON' : 'WATCH OFF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isWatchConnected ? Colors.blueAccent : Colors.white24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  lastCommand.isEmpty
                      ? (isListening ? 'Waiting for command...' : 'Tap mic to start voice')
                      : lastCommand,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(lastCommand.isEmpty ? 0.4 : 0.9),
                    fontWeight: lastCommand.isEmpty ? FontWeight.normal : FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
