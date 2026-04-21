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
import 'screens/setup/setup_choice_screen.dart';
import 'screens/web/web_dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'database/db_helper.dart';
import 'services/cloud_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ☁️ INITIALIZE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Read the saved theme mode BEFORE the app starts!
  // Defaults to 'system' if the user has never changed it.
  final prefs = await SharedPreferences.getInstance();
  final savedMode = prefs.getString('themeMode');
  themeProvider.initializeTheme(savedMode);

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

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Hide scrollbars globally, especially useful for Web aesthetics
    return child;
  }
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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Check if user has ANY data before allowing them to bypass setup
      bool hasData = false;
      try {
        final db = await DBHelper.instance.database;
        final subjects = await db.query('subjects', limit: 1);
        if (subjects.isNotEmpty) {
          hasData = true;
        } else {
          // No local data, check cloud
          hasData = await CloudSyncService().restoreDataFromCloud();
        }
      } catch (e) {
        debugPrint('Init data check error: $e');
      }

      if (!hasData) {
        return const SetupChoiceScreen();
      }

      return const RootScreen();
    }

    // Web: always start on the marketing/AI landing page
    if (kIsWeb) {
      return const WebDashboardScreen();
    }
    
    // Android: Always start on the Auth screen
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'AttendEase',
          scrollBehavior: AppScrollBehavior(),

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


