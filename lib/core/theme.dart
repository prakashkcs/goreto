import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GalacticTheme {
  // Colors
  static const Color deepNebulaPurple = Color(0xFF2E1A47);
  static const Color voidBlack = Color(0xFF05030A);
  static const Color laserPink = Color(0xFFFF0055);
  static const Color cyberBlue = Color(0xFF00F0FF);
  static const Color liveRed = Color(0xFFFF3B30);
  static const Color activeGreen = Color(
    0xFF00FF00,
  ); // Assuming standard green for "Active" dot

  // Glass Style
  static Color glassColor = Colors.white.withValues(alpha: 0.08);
  static LinearGradient glassBorderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: 0.2),
      Colors.white.withValues(alpha: 0.0)
    ],
  );

  // Background Gradient
  static const RadialGradient backgroundGradient = RadialGradient(
    center: Alignment.center,
    radius: 1.5,
    colors: [deepNebulaPurple, voidBlack],
    stops: [0.0, 1.0],
  );

  // Neon Gradients
  static const LinearGradient liveRingGradient = LinearGradient(
    colors: [laserPink, Colors.orange],
  );

  static const LinearGradient connectButtonGradient = LinearGradient(
    colors: [laserPink, Color(0xFFFF5588)],
  );

  // Text Styles
  static TextStyle get titleStyle => GoogleFonts.orbitron(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        shadows: [const Shadow(color: laserPink, blurRadius: 10)],
      );

  static TextStyle get bodyStyle => GoogleFonts.exo2(
      fontSize: 16, color: Colors.white.withValues(alpha: 0.9));

  static ThemeData get themeData => ThemeData(
        scaffoldBackgroundColor: voidBlack,
        primaryColor: laserPink,
        brightness: Brightness.dark,
        textTheme: TextTheme(displayLarge: titleStyle, bodyLarge: bodyStyle),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            // Disable route snapshotting — Flutter re-rasterizes the entering screen
            // every frame by default, which causes jank on complex widget trees.
            TargetPlatform.android: ZoomPageTransitionsBuilder(
              allowEnterRouteSnapshotting: false,
            ),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      );
}
