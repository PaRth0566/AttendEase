import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/root/root_screen.dart';
import 'screens/setup/attendance_criteria_screen.dart';
import 'screens/setup/basic_info_screen.dart';

void main() {
  runApp(const AttendEaseApp());
}

class AttendEaseApp extends StatelessWidget {
  const AttendEaseApp({super.key});

  // 🔑 CHECK IF USER HAS COMPLETED SETUP
  Future<bool> _isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_setup_complete') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AttendEase',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF2563EB),
        // ✅ FIX: Overrides the default purple outlines/buttons across the whole app
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // 🔥 DECIDE HOME SCREEN DYNAMICALLY
      home: FutureBuilder<bool>(
        future: _isSetupComplete(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // ✅ IF SETUP DONE → DASHBOARD
          if (snapshot.data!) {
            return const RootScreen();
          }

          // ❌ NEW USER → BASIC INFO
          return const BasicInfoScreen(isEditMode: false);
        },
      ),

      // KEEP ROUTES (USED INTERNALLY)
      routes: {'/attendance-criteria': (_) => const AttendanceCriteriaScreen()},
    );
  }
}
