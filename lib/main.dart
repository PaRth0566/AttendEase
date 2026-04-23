import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_web_plugins/url_strategy.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable Path URL strategy to remove '#' from web routing
  usePathUrlStrategy();

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

class _AttendEaseAppState extends State<AttendEaseApp>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    // Listen for OS-level brightness changes so ThemeMode.system reacts live
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called by Flutter whenever the platform brightness changes (e.g. the user
  /// switches between light and dark mode in their OS settings).
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // Delegates to ThemeProvider which only fires if we're in system mode.
    themeProvider.onPlatformBrightnessChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'AttendEase',
          scrollBehavior: AppScrollBehavior(),

          // DYNAMIC THEME IMPLEMENTATION
          themeMode: themeProvider.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,

          routerConfig: AppRouter.router,
        );
      },
    );
  }
}


