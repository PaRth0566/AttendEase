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
import 'services/play_update_service.dart';
import 'widgets/incoming_pdf_handler.dart';
import 'widgets/theme_crossfade.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable Path URL strategy to remove '#' from web routing
  usePathUrlStrategy();

  // Everything below this point decides how long the user stares at a blank
  // page before the first frame paints, so on web we do as little as possible
  // here and move the rest off the critical path.
  if (kIsWeb) {
    // Firebase is still awaited: the router's redirect reads
    // `FirebaseAuth.instance.currentUser` on the very first navigation, so
    // starting without it would flash the logged-out landing page at a
    // signed-in user. It is a local SDK init, not a round-trip.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // The shader warm-up is deliberately NOT awaited on web. It exists to stop
    // the glass nav bar flashing white on its first paint, and that bar is
    // mobile-only — it never renders in the web shell. On web the two
    // `FragmentProgram.fromAsset` calls inside it are network fetches for
    // shader assets, so awaiting them bought nothing while blocking first
    // paint. `LightweightLiquidGlass` already pre-warms itself lazily on first
    // use, so dropping it here costs nothing.
    //
    // The theme read, by contrast, IS still awaited. It backs onto
    // localStorage rather than the network, so it is cheap — and it has to
    // resolve before the first frame: `initializeTheme` deliberately does not
    // call `notifyListeners()`, so a late load would leave a saved dark-mode
    // user on the light theme until something else happened to rebuild.
    try {
      final prefs = await SharedPreferences.getInstance();
      themeProvider.initializeTheme(prefs.getString('themeMode'));
    } catch (error) {
      // Falls back to ThemeMode.system, which is the default anyway.
      debugPrint('Theme restore skipped: $error');
    }

    runApp(
      LiquidGlassWidgets.wrap(
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
      ),
    );
    return;
  }

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

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(
      LiquidGlassWidgets.wrap(
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
      ),
    );
  });
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runUpdateStartupFlow(),
    );
  }

  Future<void> _runUpdateStartupFlow() async {
    if (kIsWeb || _startupFlowRan) return;
    _startupFlowRan = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    // Ask Google Play whether a newer build is on the user's track and, if so,
    // download it flexibly in the background then prompt to restart. No-op on
    // non-Play builds; every failure is swallowed inside the service.
    await PlayUpdateService.instance.checkAndStartFlexibleUpdate();
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
          themeAnimationDuration: Duration.zero,
          themeMode: themeProvider.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,

          routerConfig: AppRouter.router,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final overlayTheme = AppTheme.withResponsiveOverlays(
              Theme.of(context),
              mq.size.width,
            );
            final scale = mq.textScaler.scale(1.0);
            // The app's layouts are dense — subject names, the profile hero and
            // the dashboard cards all pack text into fixed-width rows — so a
            // large system font setting was the single biggest source of
            // truncated names and overflow ribbons on other people's phones.
            //
            // 1.15 is the ceiling those layouts hold at with every name still
            // fully readable; past that Android's own "Font size"/"Display
            // size" sliders start eating the content instead of enlarging it.
            // The 0.9 floor keeps a shrunk system setting legible.
            //
            // Narrow phones get a tighter ceiling still: the same 1.15 that is
            // comfortable at 400dp starts clipping at 360dp, where there is
            // simply less width for a scaled-up subject name to live in.
            const double minScale = 0.9;
            final double maxScale = mq.size.width < 360
                ? 1.0
                : (mq.size.width < 400 ? 1.1 : 1.15);
            // Only clamp when the system scale is outside our comfort range;
            // calling clamp with equal min/max triggers an assertion in some
            // Flutter versions.
            final needsClamp = scale < minScale || scale > maxScale;
            final effective = needsClamp
                ? TextScaler.linear(scale.clamp(minScale, maxScale))
                : mq.textScaler;
            return MediaQuery(
              data: mq.copyWith(textScaler: effective),
              // Wraps the whole app so a Dark Mode toggle reads as one unified
              // crossfade (background, text, icons, cards, glass nav bar all on
              // the same timeline) instead of half the UI snapping at the theme
              // lerp midpoint. Triggered via ThemeCrossfade.of(context) — see
              // the Profile screen's Dark Mode switch.
              //
              // The incoming-PDF handler sits outside that crossfade and renders
              // its child untouched. It lives here, above the router's pages,
              // because a report opened from Android's "Open with" chooser can
              // arrive on any screen — or before there is one, on a cold start —
              // so nothing further down the tree is reliably alive to catch it.
              child: Theme(
                data: overlayTheme,
                child: IncomingPdfHandler(child: ThemeCrossfade(child: child!)),
              ),
            );
          },
        );
      },
    );
  }
}
