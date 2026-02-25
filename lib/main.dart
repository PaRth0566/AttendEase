import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/root/root_screen.dart';
import 'screens/setup/attendance_criteria_screen.dart';
import 'screens/setup/basic_info_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ☁️ INITIALIZE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔔 INITIALIZE NOTIFICATIONS
  await NotificationService().init();
  await NotificationService().scheduleSmartNotifications();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const AttendEaseApp());
  });
}

class AttendEaseApp extends StatelessWidget {
  const AttendEaseApp({super.key});

  // ✅ NEW: The Master Routing Logic
  Future<Widget> _getInitialScreen() async {
    // 1. Check if user is logged into Firebase FIRST
    if (FirebaseAuth.instance.currentUser == null) {
      return const LoginScreen();
    }

    // 2. If they are logged in, check if they finished setting up their profile
    final prefs = await SharedPreferences.getInstance();
    final isSetupComplete = prefs.getBool('is_setup_complete') ?? false;

    if (isSetupComplete) {
      return const RootScreen();
    } else {
      return const BasicInfoScreen(isEditMode: false);
    }
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
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          // Show a clean loading spinner while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              ),
            );
          }

          // Return the correct screen based on the logic above
          if (snapshot.hasData) {
            return snapshot.data!;
          }

          // Safe fallback
          return const LoginScreen();
        },
      ),
      routes: {'/attendance-criteria': (_) => const AttendanceCriteriaScreen()},
    );
  }
}
