import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/root/root_screen.dart';
import 'screens/setup/attendance_criteria_screen.dart';
import 'screens/setup/basic_info_screen.dart';
import 'services/notification_service.dart'; // ✅ IMPORTED NOTIFICATION SERVICE

void main() async {
  // ✅ 1. Ensure Flutter is initialized before interacting with native device settings
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 2. Initialize Notifications and schedule them based on current data
  await NotificationService().init();
  await NotificationService().scheduleSmartNotifications();

  // ✅ 3. Lock the app to Portrait mode only to prevent RenderFlex overflow errors
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    // ✅ 4. Run the app AFTER the orientation is locked
    runApp(const AttendEaseApp());
  });
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
