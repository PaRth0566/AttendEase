import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/root/root_screen.dart';
import 'screens/setup/attendance_criteria_screen.dart';
import 'screens/setup/basic_info_screen.dart';
import 'screens/web/web_dashboard_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ☁️ INITIALIZE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ NEW: SILENT GUEST LOGIN
  // This ensures the user instantly gets a secure Guest ID if they aren't logged in.
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      print("Silent Guest Login Failed: $e");
    }
  }

  // 🔔 INITIALIZE NOTIFICATIONS (skip on web as it causes MissingPlugin errors)
  if (!kIsWeb) {
    await NotificationService().init();
    await NotificationService().scheduleSmartNotifications();
  }

  // Read the saved theme from memory BEFORE the app starts!
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeProvider.initializeTheme(isDark);

  // Disable orientation limitations on web to prevent startup crashes
  if (kIsWeb) {
    runApp(const AttendEaseApp());
  } else {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).then((_) {
      runApp(const AttendEaseApp());
    });
  }
}

class AttendEaseApp extends StatefulWidget {
  const AttendEaseApp({super.key});

  @override
  State<AttendEaseApp> createState() => _AttendEaseAppState();
}

class _AttendEaseAppState extends State<AttendEaseApp> {
  // CACHE THE FUTURE: This stops the app from redirecting when the theme changes!
  late Future<Widget> _initialScreen;

  @override
  void initState() {
    super.initState();
    _initialScreen = _getInitialScreen();
  }

  Future<Widget> _getInitialScreen() async {
    // If on the web platform, show the specific Dashboard screen directly, skipping auth.
    if (kIsWeb) {
      return const WebDashboardScreen();
    }

    // 1. Check if user is logged into Firebase FIRST
    if (FirebaseAuth.instance.currentUser == null) {
      return const LoginScreen();
    }

    // 2. If they are logged in (even as a Guest), check if they finished setting up their profile
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
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'AttendEase',

          // DYNAMIC THEME IMPLEMENTATION
          themeMode: themeProvider.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,

          home: FutureBuilder<Widget>(
            future: _initialScreen, // Uses the cached future
            builder: (context, snapshot) {
              // Show a clean loading spinner while checking auth state
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
          routes: {
            '/attendance-criteria': (_) => const AttendanceCriteriaScreen(),
          },
        );
      },
    );
  }
}