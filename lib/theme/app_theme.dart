import 'package:flutter/material.dart';

class AppTheme {
  // Your signature brand color stays exactly the same in both modes
  static const Color primaryBlue = Color(0xFF2563EB);

  // ☀️ LIGHT THEME
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: primaryBlue,
      surface: Colors.white,
      onSurface: Color(0xFF1E293B),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.black),
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardColor: const Color(0xFFF2F4FF),
    dividerColor: const Color(0xFFE2E8F0),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF1E293B)),
    ),
  );

  // 🌙 TRUE AMOLED DARK THEME
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: Colors.black, // ✅ TRUE AMOLED BLACK
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: primaryBlue,
      surface: Color(
        0xFF121212,
      ), // Very dark gray for cards so they don't vanish into the background
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black, // ✅ TRUE AMOLED BLACK
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardColor: const Color(0xFF121212), // Matches the surface
    dividerColor: const Color(0xFF2A2A2A), // Subtle dark borders
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
    ),
  );
}
