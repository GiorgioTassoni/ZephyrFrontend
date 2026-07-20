import 'package:flutter/material.dart';

class ZephyrColors {
  static const Color primary = Color(0xFFF59E0B); // Amber Zephyr
  static const Color bgDark = Color(0xFF121212);  // Main background
  static const Color bgCard = Color(0xFF1E1E1E);  // Cards, tiles
  static const Color bgLight = Color(0xFF282828); // Hover, selected, active
  
  static const Color text = Color(0xFFFFFFFF);     // Primary text
  static const Color textDim = Color(0xFFB3B3B3);  // Secondary text, metadata
  static const Color textMuted = Color(0xFF727272); // Small labels, timestamps
  
  static const Color error = Color(0xFFE74C3C);    // Red
  static const Color warning = Color(0xFFF39C12);  // Amber/Orange
  static const Color success = Color(0xFF1DB954);  // Green (e.g. download complete check)

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primary,
        background: bgDark,
        surface: bgCard,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgDark,
        indicatorColor: primary.withOpacity(0.2),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: textDim);
        }),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(color: primary, fontWeight: FontWeight.bold);
          }
          return const TextStyle(color: textDim);
        }),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: text,
        iconColor: textDim,
      ),
    );
  }
}

extension ResponsiveSizing on BuildContext {
  double get scaleFactor {
    final width = MediaQuery.of(this).size.width;
    return (0.95 + (width - 1100) * 0.00034).clamp(0.95, 1.45);
  }

  double scale(double value) {
    return value * scaleFactor;
  }
}
