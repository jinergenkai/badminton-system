import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class VoiceIndicator extends StatelessWidget {
  final bool isListening;
  final String lastCommand;
  final VoidCallback onToggle;

  const VoiceIndicator({
    super.key,
    required this.isListening,
    required this.lastCommand,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isListening
              ? Colors.greenAccent.withOpacity(0.4)
              : Colors.white.withOpacity(0.15),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Microphone Button
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isListening
                      ? [Colors.greenAccent, Colors.green.shade600]
                      : [Colors.grey[700]!, Colors.grey[850]!],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isListening ? Colors.greenAccent : Colors.grey)
                        .withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: isListening ? 3 : 0,
                  ),
                ],
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Status and Command
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Text
                Text(
                  isListening ? 'LISTENING' : 'TAP TO START',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isListening ? Colors.greenAccent : Colors.grey[400],
                    letterSpacing: 1.2,
                  ),
                ),

                // Last Command
                if (lastCommand.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lastCommand,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).animate().fadeIn(duration: 300.ms),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
