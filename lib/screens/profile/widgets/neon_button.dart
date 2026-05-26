import 'package:flutter/material.dart';

/// Neon-styled button widget matching Love Vibe theme
/// Supports outlined and filled styles with glow effects
class NeonButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isFilled;
  final bool isPremium;
  final Color neonColor;
  final double fontSize;
  final double? width;
  final double height;
  final bool isLoading;
  final bool isDisabled;

  const NeonButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isFilled = false,
    this.isPremium = false,
    this.neonColor = const Color(0xFFFF007F),
    this.fontSize = 13,
    this.width,
    this.height = 40,
    this.isLoading = false,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: [neonColor, neonColor.withValues(alpha: 0.7)],
    );

    // Disabled state — grey, no glow, no tap
    if (isDisabled) {
      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white30, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: Colors.white30,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize,
                ),
              ),
              if (isPremium) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'Premium',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: isFilled ? gradient : null,
          color: isFilled ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: neonColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: neonColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: -2,
            ),
            if (isFilled)
              BoxShadow(
                color: neonColor.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isFilled ? Colors.white : neonColor,
                  ),
                )
              else ...[
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: isFilled ? Colors.white : neonColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isFilled ? Colors.white : neonColor,
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                  ),
                ),
                if (isPremium) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber, width: 1),
                    ),
                    child: const Text(
                      'Premium',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
