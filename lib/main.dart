import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable Path URL strategy to remove '#' from web routing
  usePathUrlStrategy();

  // ☁️ INITIALIZE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Pre-warm the liquid-glass shaders used by the bottom nav bar. Without
  // this the bar flashes white the first time it paints. Non-fatal: if the
  // renderer can't compile them the widgets fall back to a plainer blur, so a
  // failure here must not stop the app from starting.
  try {
    await LiquidGlassWidgets.initialize();
  } catch (error) {
    debugPrint('Liquid glass shader warm-up skipped: $error');
  }

  // Read the saved theme mode BEFORE the app starts!
  // Defaults to 'system' if the user has never changed it.
  final prefs = await SharedPreferences.getInstance();
  final savedMode = prefs.getString('themeMode');
  themeProvider.initializeTheme(savedMode);

  // Disable orientation limitations on web to prevent startup crashes
  if (kIsWeb) {
    runApp(LiquidGlassWidgets.wrap(
      child: const AttendEaseApp(),
      // The nav pill's metaball blend and lens refraction are gated on
      // `GlassQuality.premium` inside `AdaptiveLiquidGlassLayer`, and premium
      // is only reachable through this scope or an explicit `GlassTheme`.
      // Without it the app is pinned to `standard` — the lightweight fragment
      // shader, no blend group — so the pill renders flat whatever it is
      // configured to do.
      //
      // Seeds at standard, benchmarks the device for ~3s, and promotes only if
      // the frame budget holds, so a weak device stays where it is today.
      adaptiveQuality: true,
    ));
  } else {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).then((_) {
      runApp(LiquidGlassWidgets.wrap(
      child: const AttendEaseApp(),
      // The nav pill's metaball blend and lens refraction are gated on
      // `GlassQuality.premium` inside `AdaptiveLiquidGlassLayer`, and premium
      // is only reachable through this scope or an explicit `GlassTheme`.
      // Without it the app is pinned to `standard` — the lightweight fragment
      // shader, no blend group — so the pill renders flat whatever it is
      // configured to do.
      //
      // Seeds at standard, benchmarks the device for ~3s, and promotes only if
      // the frame budget holds, so a weak device stays where it is today.
      adaptiveQuality: true,
    ));
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
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Hide scrollbars globally, especially useful for Web aesthetics
    return child;
  }
}

class _AttendEaseAppState extends State<AttendEaseApp>
    with WidgetsBindingObserver {
  bool _startupFlowRan = false;

  @override
  void initState() {
    super.initState();
    // Listen for OS-level brightness changes so ThemeMode.system reacts live
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runUpdateStartupFlow());
  }

  Future<void> _runUpdateStartupFlow() async {
    if (kIsWeb || _startupFlowRan) return;
    _startupFlowRan = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    try {
      // Reconcile a completed install and show "What's New" exactly once.
      final installedNotes = await UpdateService.instance.reconcileInstalledUpdate();
      final notesContext = AppRouter.rootNavigatorKey.currentContext;
      if (installedNotes != null && notesContext != null && notesContext.mounted) {
        await UpdateService.instance.runExclusiveSheet(
          () => showPatchNotesSheet(notesContext, installedNotes, markViewed: true),
        );
      }
      // Then check for a newer release. Guarded so a manual check can't stack.
      final update = await UpdateService.instance.checkForUpdate();
      final updateContext = AppRouter.rootNavigatorKey.currentContext;
      if (update != null && updateContext != null && updateContext.mounted) {
        await UpdateService.instance.runExclusiveSheet(
          () => showUpdateBottomSheet(updateContext, update),
        );
      }
    } catch (error) {
      debugPrint('Automatic update check skipped: $error');
    }
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
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final scale = mq.textScaler.scale(1.0);
            // Only clamp when the system scale is outside our comfort range;
            // calling clamp with equal min/max triggers an assertion in some
            // Flutter versions.
            final needsClamp = scale < 0.9 || scale > 1.3;
            final effective = needsClamp
                ? TextScaler.linear(scale.clamp(0.9, 1.3))
                : mq.textScaler;
            return MediaQuery(
              data: mq.copyWith(textScaler: effective),
              child: child!,
            );
          },
        );
      },
    );
  }
}
