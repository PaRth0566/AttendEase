import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../services/cloud_sync_service.dart';
import '../../theme/glass_nav_theme.dart';
import '../calendar/calender_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../profile/profile_screen.dart';
import 'tab_page_state.dart';

class RootScreen extends StatefulWidget {
  final StatefulNavigationShell? navigationShell;
  const RootScreen({super.key, this.navigationShell});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isSyncing = kIsWeb; // Only sync on start for Web

  /// Handles onto the three live tab pages, so a tab change can ask the page it
  /// reveals to refresh itself instead of replacing it. See [_buildBody].
  final GlobalKey<TabPageState> _dashboardKey = GlobalKey<TabPageState>();
  final GlobalKey<TabPageState> _calendarKey = GlobalKey<TabPageState>();
  final GlobalKey<TabPageState> _profileKey = GlobalKey<TabPageState>();

  /// Defers the revealed page's data reload until the selection pill has landed.
  ///
  /// The reload itself is off the UI thread, but the `setState` that lands its
  /// results is not: on the dashboard it rebuilds every subject card at once,
  /// which is easily a dropped frame. Holding it until the pill is parked keeps
  /// that cost out of the one window where a dropped frame is visible as a
  /// stutter in the slide.
  Timer? _reloadTimer;

  /// [GlassTabBar]'s pill travels on a 350 ms spring; this clears its tail.
  static const Duration _pillSettleDelay = Duration(milliseconds: 420);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell?.currentIndex ?? 0;
    WidgetsBinding.instance.addObserver(this);
    _initialSync();
  }

  @override
  void didUpdateWidget(RootScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell != null) {
      _currentIndex = widget.navigationShell!.currentIndex;
    }
  }

  Future<void> _initialSync() async {
    if (kIsWeb) {
      await CloudSyncService().restoreDataFromCloud();
      if (mounted) {
        // No page refresh needed: `_isSyncing` gates the body, so the pages
        // are built for the first time here, after the restore has landed.
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _performSilentBackup();
    } else if (state == AppLifecycleState.resumed) {
      _performSilentSync();
    }
  }

  Future<void> _performSilentBackup() async {
    await CloudSyncService().backupDataToCloud();
    debugPrint('☁️ Silent Auto-Backup Completed on App Close!');
  }

  Future<void> _performSilentSync() async {
    debugPrint('☁️ App Resumed: Checking for cloud updates...');
    final result = await CloudSyncService().syncBidirectional();
    if (result == 'restored') {
      debugPrint('☁️ Data updated from cloud! Refreshing UI...');
      if (!mounted) return;
      // Every page, not just the visible one — they are all mounted now, and a
      // restore can have moved data under any of them.
      for (int i = 0; i < 3; i++) {
        _pageState(i)?.reloadData();
      }
    }
  }

  /// Build the page for the given index.
  ///
  /// Keyed by [GlobalKey] rather than the old `ValueKey('dashboard_$n')`: the
  /// pages are no longer replaced to refresh them, they are asked to reload in
  /// place, and the key is the handle that asking goes through.
  Widget _buildPage(int index) {
    switch (index) {
      case 1:
        return CalendarScreen(key: _calendarKey);
      case 2:
        return ProfileScreen(key: _profileKey);
      default:
        return DashboardScreen(key: _dashboardKey);
    }
  }

  /// The live state of the page at [index], or null before its first build.
  TabPageState? _pageState(int index) => switch (index) {
        1 => _calendarKey.currentState,
        2 => _profileKey.currentState,
        _ => _dashboardKey.currentState,
      };

  /// All three tabs, alive at once, with only the selected one painting.
  ///
  /// The body used to be a single `_buildPage(_currentIndex)`, so every tab
  /// change tore one screen out of the tree and built the other from scratch —
  /// `initState`, its database read, and the `setState` that rebuilds the whole
  /// page when that read lands. All of that fell inside the 350 ms the
  /// selection pill spends travelling, and it ate the window whole: recording
  /// the bar frame by frame, a Dashboard→Profile switch painted the pill at its
  /// origin, once about 5% along, and then already parked at its destination.
  /// Three positions is not a slide, which is exactly why it read as a jump.
  ///
  /// An [IndexedStack] costs a repaint and nothing else, so the spring gets
  /// every frame. It also drops the skeleton flash that used to greet you on
  /// every return to a tab, since the page you come back to is the one you
  /// left. Freshness is preserved by [_onTabSelected] instead — it asks the
  /// revealed page to reload once the pill has landed.
  ///
  /// [TickerMode] is what stops the hidden pages from costing anything:
  /// [IndexedStack] keeps its children mounted but does not silence their
  /// tickers, so without it the dashboard's progress sweeps would keep
  /// animating — and driving layout — from behind the calendar.
  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          TickerMode(enabled: _currentIndex == i, child: _buildPage(i)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final glassSettings = GlassNavTheme.settings(brightness);
    final Color unselectedContent = GlassNavTheme.unselectedContent(brightness);

    if (_isSyncing) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // 1. Try to pop any sub-screens pushed via Navigator.push (e.g., from Profile)
        final bool handledLocally = await Navigator.maybePop(context);
        if (handledLocally || !context.mounted) return;

        // 2. If no sub-screens, handle internal GoRouter history or home redirect
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/web/home');
        }
      },
      // [GlassNavTheme]'s material, carried on the package's documented page
      // root rather than a bare `AdaptiveLiquidGlassLayer`.
      //
      // The layer renders, but it is *only* the renderer — it carries no
      // `LiquidGlassScope`, so `GlassBackgroundSource` has no capture key to
      // find and colour absorption is off entirely. `GlassPage` supplies that
      // scope and forwards `settings` to the same layer underneath, so the
      // glass stays the tuned one below while the sampling path is wired.
      child: GlassPage(
        settings: glassSettings,
        child: Scaffold(
          // The glass has to have something to refract. With the default
          // (extendBody: false) the Scaffold reserves the bar's height and the
          // only thing behind it is the flat scaffold background, which makes
          // the effect invisible. Content now scrolls underneath instead.
          extendBody: true,
          // Tabs swap with no transition at all.
          //
          // A cross-fade here has to hold both screens laid out at once, and
          // mid-fade the two AppBars and both backgrounds composite over each
          // other — which is the part that reads as movement even after the
          // slide is gone. The pill is already animating during the same
          // window and is the better carrier of the change; the page under it
          // just needs to be there.
          body: _buildBody(),
          // The bar is [GlassNavTheme]'s — its proportions, its material, its
          // per-theme content colours. The *pill* is the package's, left as the
          // upstream demo renders it.
          bottomNavigationBar: GlassTabBar.bottom(
            selectedIndex: _currentIndex,
            onTabSelected: _onTabSelected,
            settings: glassSettings,

            // Proportions — a floating object, not a full-width toolbar.
            barHeight: GlassNavTheme.barHeight,
            barBorderRadius: GlassNavTheme.barRadius,
            horizontalPadding: GlassNavTheme.horizontalInset,
            verticalPadding: GlassNavTheme.verticalInset,
            iconSize: GlassNavTheme.iconSize,
            iconLabelSpacing: 3,

            // ── The pill: the demo's look, this app's motion ──────────
            //
            // Look is upstream's. `indicatorSettings` is gone — that was the
            // blur-0 / index-1.0 material that made the pill a flat tinted
            // chip instead of a glass lens — so the pill takes the package's
            // own material, tinted and masked exactly as the demo does it.
            // `indicatorBorderRadius` and `indicatorExpansion` are unset for
            // the same reason: the demo sets neither, and both were hand-fitted
            // off [GlassNavTheme.barRadius].
            // Neutral frosted chip rather than a blue tint; the selected
            // icon/label colours below are untouched.
            //
            // The tint has to invert with the theme, because the pill is a step
            // in brightness away from the bar and the bar's glass sits at
            // opposite ends in the two themes. White at 0.12 is a visible lift
            // on dark glass and *nothing at all* on light glass — which is what
            // made the light-mode pill disappear — so light mode darkens by the
            // same idea instead.
            indicatorColor: brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFF1F2126).withValues(alpha: 0.10),

            // The *travelling* pill, light mode only.
            //
            // `indicatorColor` above is only the resting chip. The moment the
            // pill starts moving it cross-fades to the package's glass lens,
            // whose default material is a near-transparent white — a lift, on a
            // bar that is already the brightest thing on a light screen. That
            // is the pill going faint mid-trip: not the chip's colour, the
            // lens's. Light mode swaps in a flat chip that matches the resting
            // one, so the cross-fade has nothing to give away.
            //
            // Dark mode passes null and keeps the package lens untouched — the
            // default lift works there precisely because the bar is dark.
            indicatorSettings: brightness == Brightness.dark
                ? null
                : GlassNavTheme.travellingPill(brightness),
            maskingQuality: MaskingQuality.high,

            // Motion is unchanged from what this app already had.
            //
            // The package layers three deformations on top of the glide — a
            // concave lens pinch, an icon scale-up, and a press bounce — and
            // with only three tabs the trip is short enough that they all fire
            // at once and read as the pill wobbling rather than moving. The
            // metaball blend that stretches it toward the bar's edges is the
            // fourth, and it costs a shared-layer composite every frame of the
            // move. All four stay neutralised, so the motion is one thing:
            // position.
            //
            // The one deformation kept is the jelly stretch, because it is the
            // only one that describes the travel rather than decorating it: the
            // pill elongates along its path and contracts on arrival, holding
            // its area throughout. Upstream has that backwards — it squashes
            // *along* the direction of motion, which took the pill to 0.6x
            // width on the Dashboard↔Profile trip and read as it receding
            // rather than accelerating. Fixed in the vendored copy of the
            // package; see third_party/liquid_glass_widgets/README.attendease.md.
            enableBlend: false,
            indicatorPinchStrength: 0,
            magnification: 1.0,
            pressScale: 1.0,

            selectedIconColor: GlassNavTheme.selectedIcon(brightness),
            selectedLabelColor: GlassNavTheme.selectedLabel(brightness),
            unselectedIconColor: unselectedContent,
            unselectedLabelColor: unselectedContent,
            labelFontSize: GlassNavTheme.labelSize,
            selectedLabelStyle: GlassNavTheme.labelStyle(selected: true),
            unselectedLabelStyle: GlassNavTheme.labelStyle(selected: false),

            // No glowColor on any tab. The package's default halo is 32px blur
            // at 0.6 opacity per tab, which is where the coloured haze across
            // the bar came from.
            tabs: const [
              GlassTab(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'DASHBOARD',
                semanticLabel: 'Dashboard',
              ),
              GlassTab(
                icon: Icon(Icons.calendar_month_outlined),
                activeIcon: Icon(Icons.calendar_month_rounded),
                label: 'CALENDAR',
                semanticLabel: 'Calendar',
              ),
              GlassTab(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: 'PROFILE',
                semanticLabel: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;

    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(index);
    } else {
      setState(() => _currentIndex = index);
    }

    // The page is already on screen with the data it had when you left it;
    // this catches it up. Held until the pill has parked — see [_reloadTimer].
    _reloadTimer?.cancel();
    _reloadTimer = Timer(_pillSettleDelay, () {
      if (mounted) _pageState(index)?.reloadData();
    });
  }
}
