import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../utils/constants.dart';

class AccessibleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color? color;
  final double size;

  const AccessibleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.color,
    this.size = kButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? kPrimaryColor;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: () async {
          final hasVibrator = await Vibration.hasVibrator();
          if (hasVibrator) {
            Vibration.vibrate(duration: 50);
          }
          onTap();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: buttonColor.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: size * 0.4, color: Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MicButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;

  const MicButton({super.key, required this.isListening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isListening ? 'Arrêter l\'écoute' : 'Parler à Kangue',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: isListening ? Colors.red.shade700 : kAccentColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isListening ? Colors.red : kAccentColor)
                    .withValues(alpha: 0.5),
                blurRadius: isListening ? 25 : 15,
                spreadRadius: isListening ? 8 : 2,
              ),
            ],
          ),
          child: Icon(
            isListening ? Icons.stop_rounded : Icons.mic_rounded,
            size: 52,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
