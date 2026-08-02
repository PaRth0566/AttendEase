import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../services/cloud_sync_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/glass_nav_theme.dart';
import '../../widgets/animated_nav_icons.dart';
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

  /// Owns the physics of the sliding strip.
  late final PageController _pageController;

  /// Continuous page position: 0.0 Dashboard … 2.0 Profile. Single source of
  /// truth for both the strip and the pill, so they cannot drift apart.
  ///
  /// A [ValueNotifier] rather than a plain field so [_onPageScroll] can push a
  /// new position every frame *without* a `setState`: only the
  /// [ValueListenableBuilder] around the nav bar listens, so the pill tracks the
  /// slide while the actively-scrolling PageView, the GlassPage and the Scaffold
  /// are all left alone. Seeded because `PageController.page` is only readable
  /// after first layout and the pill needs a value on the very first build.
  final ValueNotifier<double> _pagePosition = ValueNotifier<double>(0);

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

  /// Incremented every time a tab becomes the arrived one, and again when the
  /// arrived tab is re-tapped. Handed to the nav icons, which play any epoch
  /// they have not yet played — the mechanism that survives the package tearing
  /// a filled icon down and rebuilding it mid-travel. 0 means "no navigation
  /// yet", so the cold-start tab stays quiet. See `animated_nav_icons.dart`.
  int _iconEpoch = 0;

  /// Which tab's icon is playing. Tracks [_currentIndex], and like it never
  /// takes the value of a page merely crossed on the way to somewhere else.
  ///
  /// `PageView.onPageChanged` fires for *every* page the strip crosses, so
  /// tapping Profile from Dashboard reports Calendar on the way. [_onPageSettled]
  /// drops those crossings, so neither this nor [_currentIndex] ever lands on a
  /// tab the user did not ask for — which is what "a different tab's icon
  /// animates, and I have to tap twice" was.
  int _iconIndex = 0;

  /// Where a tap or a router change is heading, so [_onPageSettled] can tell
  /// the destination from the pages crossed to reach it. Null during a drag,
  /// where every settle is a real destination.
  int? _navTarget;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell?.currentIndex ?? 0;
    _iconIndex = _currentIndex;
    _pagePosition.value = _currentIndex.toDouble();
    _pageController = PageController(initialPage: _currentIndex);
    _pageController.addListener(_onPageScroll);
    WidgetsBinding.instance.addObserver(this);
    _initialSync();
  }

  /// Mirrors the controller's continuous position into [_pagePosition] every
  /// frame of a drag or a tap-driven `animateToPage`.
  ///
  /// Deliberately *not* a `setState`: writing the [ValueNotifier] rebuilds only
  /// the [ValueListenableBuilder] wrapping the nav bar, so the pill tracks the
  /// slide frame-for-frame while the PageView keeps scrolling undisturbed. The
  /// old `setState` here rebuilt the whole screen — the actively-scrolling
  /// PageView included — every frame, and reconstructing a scrollable mid-scroll
  /// fights its own physics. That was the stutter, on both the swipe and the tap.
  void _onPageScroll() {
    final double? page = _pageController.page;
    if (page == null) return;
    _pagePosition.value = page;
  }

  @override
  void didUpdateWidget(RootScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GoRouter can change the branch from outside (deep link, back button).
    final int? shellIndex = widget.navigationShell?.currentIndex;
    if (shellIndex == null || shellIndex == _currentIndex) return;
    _currentIndex = shellIndex;
    _navTarget = shellIndex;
    // Only chase the shell when the strip is not already heading there — during
    // a drag-settle _onPageSettled has already called goBranch, and animating
    // again here would restart the motion the user just finished.
    if (_pageController.hasClients &&
        _pageController.page?.round() != shellIndex) {
      _pageController.animateToPage(
        shellIndex,
        duration: AppMotion.emphasized,
        curve: AppMotion.morph,
      );
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
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pagePosition.dispose();
    _reloadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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
    return PageView.builder(
      controller: _pageController,
      itemCount: 3,
      // Snaps to whole pages, so a half-drag never leaves the strip parked
      // between two screens.
      pageSnapping: true,
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      onPageChanged: _onPageSettled,
      itemBuilder: (context, i) => TickerMode(
        // Compare against the settled index, not the live position: during a
        // drag both neighbours must keep painting, and only the one you land on
        // should resume its tickers.
        enabled: _currentIndex == i,
        child: _buildPage(i),
      ),
    );
  }

  /// Fires when the strip settles on a new page (drag release or tap animation).
  /// The drag already moved the strip, so this only syncs GoRouter and schedules
  /// the deferred reload.
  ///
  /// `PageView.onPageChanged` fires for *every* page the strip crosses, so a far
  /// tap (Dashboard→Profile) reports the crossed Calendar page mid-flight. Doing
  /// the full arrival work for that crossing — a `setState` that rebuilds the
  /// PageView while `animateToPage` is still animating it, plus a GoRouter
  /// `goBranch` that swaps the shell's active branch — lands two heavy jobs in
  /// the middle of the slide and is exactly why a far tap stuttered while an
  /// adjacent one did not. A crossing is therefore skipped here entirely: the
  /// pill is already tracking the physical position through [_pagePosition], and
  /// the router + index + icons are all synced once, on arrival at [_navTarget].
  void _onPageSettled(int index) {
    if (index == _currentIndex) return;
    // Only the destination does arrival work. A page merely crossed on the way
    // to [_navTarget] gets nothing here — no rebuild, no branch switch — so the
    // slide runs uninterrupted. The pill still sweeps the full distance because
    // it follows the continuous [_pagePosition], not this discrete callback.
    final bool isCrossing = _navTarget != null && _navTarget != index;
    if (isCrossing) return;
    setState(() {
      _currentIndex = index;
      _iconIndex = index;
      _iconEpoch++;
    });
    _navTarget = null;
    widget.navigationShell?.goBranch(index);
    _reloadTimer?.cancel();
    _reloadTimer = Timer(_pillSettleDelay, () {
      if (mounted) _pageState(index)?.reloadData();
    });
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
          // Only this subtree listens to the per-frame page position, so the
          // slide never rebuilds the PageView above it. Everything else here
          // (selected index, icon epoch) changes only on settle, when the outer
          // setState rebuilds this builder with fresh values anyway.
          bottomNavigationBar: ValueListenableBuilder<double>(
            valueListenable: _pagePosition,
            builder: (context, pagePosition, _) {
              // Distance to the nearest whole tab: 0 when parked, up to 0.5
              // mid-slide. Drives the masking-quality swap below.
              final double offTab =
                  (pagePosition - pagePosition.roundToDouble()).abs();
              return GlassTabBar.bottom(
                selectedIndex: _currentIndex,
                // Maps page position 0…2 onto the pill's alignment space -1…1 —
                // same mapping as computeAlignment, on a continuous position.
                // (pos / (count - 1)) * 2 - 1; 2 is hard-coded to match the three
                // hard-coded tabs below.
                alignmentOverride: (pagePosition / 2).clamp(0.0, 1.0) * 2 - 1,
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
                // High-quality masking is the pill's most expensive frame by far:
                // it clips two full-bar-width icon layers through
                // `Clip.antiAliasWithSaveLayer` and rebuilds two jelly clip paths
                // *every frame* the pill moves — the costliest raster op Flutter
                // has, on the Impeller path. None of it is visible mid-slide: the
                // "magic lens" reveal it buys only reads once the pill is parked
                // over an icon. So it runs at rest and drops to the clip-free
                // `.off` path the instant the pill is travelling.
                //
                // The swap is invisible because it happens at the extremes only.
                // `.off` parks the selected icon as a static overlay at the target
                // tab; `.high` reveals it through the moving lens. Those two
                // coincide exactly when the pill is over a tab, so restoring `.high`
                // within 0.02 of a whole tab (essentially parked) shows no jump.
                // `_pagePosition` is an exact integer at rest, so at rest this is
                // always `.high`.
                maskingQuality: offTab < 0.02
                    ? MaskingQuality.high
                    : MaskingQuality.off,

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
                //
                // One painter per tab in two variants — outline resting, solid
                // active — replacing the Material outlined/rounded pair. Mixing a
                // hand-drawn set with Material's would put two icon vocabularies in
                // one bar. See [_navIcon]: `filled` is the row, `active` is the
                // animation, and they are not the same axis.
                tabs: [
                  GlassTab(
                    icon: _navIcon(0, filled: false),
                    activeIcon: _navIcon(0, filled: true),
                    label: 'DASHBOARD',
                    semanticLabel: 'Dashboard',
                  ),
                  GlassTab(
                    icon: _navIcon(1, filled: false),
                    activeIcon: _navIcon(1, filled: true),
                    label: 'CALENDAR',
                    semanticLabel: 'Calendar',
                  ),
                  GlassTab(
                    icon: _navIcon(2, filled: false),
                    activeIcon: _navIcon(2, filled: true),
                    label: 'PROFILE',
                    semanticLabel: 'Profile',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The animated icon for [index], in its outline or [filled] variant.
  ///
  /// Two axes, and they are not the same thing:
  ///
  /// * [filled] is which of the bar's two rows this copy belongs to — outline
  ///   for `icon`, solid for `activeIcon`. The bar draws both rows in full and
  ///   clips the solid one to the travelling pill, so the fill arrives exactly
  ///   as the pill sweeps across, with no state of its own.
  /// * `active` is whether this tab is the current one, and it drives the
  ///   animation. It has to be passed in because neither row's icon can see it
  ///   — one row is drawn wholly unselected and the other wholly selected, so
  ///   no icon ever observes a change. Handing the same flag to both copies is
  ///   also what keeps them in step: they start on the same setState.
  ///
  /// This runs on every frame of a swipe, since [_onPageScroll] rebuilds for
  /// the pill. That costs a widget and nothing more: the icons restart only
  /// when `active` or the replay token actually changes.
  Widget _navIcon(int index, {required bool filled}) {
    final bool active = _iconIndex == index;
    switch (index) {
      case 1:
        return CalendarDaysIcon(
          filled: filled,
          active: active,
          epoch: _iconEpoch,
        );
      case 2:
        return AvatarLookingAroundIcon(
          filled: filled,
          active: active,
          epoch: _iconEpoch,
        );
      default:
        return DashboardMorphIcon(
          filled: filled,
          active: active,
          epoch: _iconEpoch,
        );
    }
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) {
      // Already here — there is no navigation to do, but the tap should still
      // get an answer, so bump the epoch to replay the icon.
      setState(() => _iconEpoch++);
      return;
    }
    // Claim the destination before the strip starts moving, so the pages it
    // crosses on the way are recognised as crossings rather than arrivals.
    _navTarget = index;
    // Not jumpToPage: animating is what makes a tap read as the same motion as
    // a drag. onPageChanged fires as it settles, so _onPageSettled does the
    // GoRouter + reload work for both paths. Under "remove animations",
    // AppMotion.duration collapses to zero, so tap-switching is instant.
    //
    // Duration scales with the distance so a far tap (Dashboard↔Profile, two
    // pages) does not cover twice the ground in the same time and whip past the
    // middle screen. Scaling is sub-linear — √distance, so a two-page trip runs
    // ~1.41× the one-page time rather than 2× — which holds the *feel* roughly
    // constant without letting the far trip drag. The now-cheap `.off` masking
    // during motion makes the extra frames essentially free.
    final int distance = (index - _currentIndex).abs();
    final Duration base = Duration(
      milliseconds: (AppMotion.emphasized.inMilliseconds * math.sqrt(distance))
          .round(),
    );
    _pageController.animateToPage(
      index,
      duration: AppMotion.duration(context, base),
      curve: AppMotion.morph,
    );
  }
}
