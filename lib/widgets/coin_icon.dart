import 'package:flutter/material.dart';

/// A customizable, reusable icon for Coins/Currency across the app.
/// Replace this internal implementation with a custom SVG or Image asset 
/// when a proprietary company logo is ready.
class CoinIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const CoinIcon({
    super.key,
    this.size = 24.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // For now, using a stylized stack to represent a custom coin.
    // Replace the `Stack` with `Image.asset('assets/images/coin.png')`
    // when a graphic is provided by the design team.
    final iconColor = color ?? const Color(0xFFFFD700); // Default gold

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.hexagon,
            size: size,
            color: iconColor.withValues(alpha: 0.2),
          ),
          Icon(
            Icons.generating_tokens,
            size: size * 0.8,
            color: iconColor,
          ),
        ],
      ),
    );
  }
}
