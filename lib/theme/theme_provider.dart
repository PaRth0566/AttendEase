import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = ThemeProvider();

class ThemeProvider extends ChangeNotifier {
  // Default to system — the app follows the OS setting out of the box
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Returns true when the effective appearance is dark.
  /// Takes the platform brightness into account when in `system` mode.
  bool get isDarkMode {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    // ThemeMode.system — check the OS setting
    return SchedulerBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  /// Called once before runApp() to restore the user's saved preference.
  /// If no preference was saved yet, stays on [ThemeMode.system].
  void initializeTheme(String? savedMode) {
    _themeMode = _modeFromString(savedMode);
  }

  /// Switch between system / light / dark and persist the choice.
  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _modeToString(mode));
  }

  /// Legacy toggle (keeps the Dark Mode switch in profile working)
  void toggleTheme(bool isOn) {
    setThemeMode(isOn ? ThemeMode.dark : ThemeMode.light);
  }

  /// Called when the OS-level brightness changes so that ThemeMode.system
  /// widgets rebuild immediately without needing a restart.
  void onPlatformBrightnessChanged() {
    if (_themeMode == ThemeMode.system) {
      notifyListeners();
    }
  }

  // ── helpers ──────────────────────────────────────────────

  static ThemeMode _modeFromString(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
