import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = ThemeProvider();

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // ✅ NEW: Instantly sets the theme before the app even starts drawing
  void initializeTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  void toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isOn);
  }
}
