import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../services/cloud_sync_service.dart';
import '../../theme/glass_nav_theme.dart';
import '../calendar/calender_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../profile/profile_screen.dart';

class RootScreen extends StatefulWidget {
  final StatefulNavigationShell? navigationShell;
  const RootScreen({super.key, this.navigationShell});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isSyncing = kIsWeb; // Only sync on start for Web

  // Use a key to force-rebuild pages when data changes
  int _pageRebuildKey = 0;

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
        setState(() {
          _isSyncing = false;
          _pageRebuildKey++; // Force fresh pages after sync
        });
      }
    }
  }

  @override
  void dispose() {
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
      if (mounted) {
        setState(() {
          _pageRebuildKey++;
        });
      }
    }
  }

  /// Build the page for the given index. Uses _pageRebuildKey as a ValueKey
  /// to force Flutter to recreate the widget (and fire initState) whenever
  /// data is synced or the tab is re-selected.
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(key: ValueKey('dashboard_$_pageRebuildKey'));
      case 1:
        return CalendarScreen(key: ValueKey('calendar_$_pageRebuildKey'));
      case 2:
        return ProfileScreen(key: ValueKey('profile_$_pageRebuildKey'));
      default:
        return DashboardScreen(key: ValueKey('dashboard_$_pageRebuildKey'));
    }
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
      child: AdaptiveLiquidGlassLayer(
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
          body: _buildPage(_currentIndex),
          bottomNavigationBar: GlassTabBar.bottom(
            selectedIndex: _currentIndex,
            onTabSelected: _onTabSelected,
            settings: glassSettings,

            // Proportions — a floating object, not a full-width toolbar.
            // The metaball blend that stretches the pill toward the bar's edges
            // as it moves. It is the single biggest source of the "liquid"
            // read, and it costs a shared-layer composite every frame of the
            // move. Off: the pill is a rounded rect that slides.
            enableBlend: false,

            barHeight: GlassNavTheme.barHeight,
            barBorderRadius: GlassNavTheme.barRadius,
            horizontalPadding: GlassNavTheme.horizontalInset,
            verticalPadding: GlassNavTheme.verticalInset,
            iconSize: GlassNavTheme.iconSize,
            iconLabelSpacing: 3,

            // A brighter glass lens riding on the bar's glass.
            indicatorColor: GlassNavTheme.selectionTint(brightness),
            indicatorSettings: GlassNavTheme.selectionSettings(brightness),
            indicatorBorderRadius: GlassNavTheme.barRadius - 6,
            indicatorExpansion:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 6),

            // The pill just travels. The package layers three separate
            // deformations on top of that glide — a concave lens pinch, an
            // icon scale-up, and a press bounce — and with only three tabs the
            // trip is short enough that they all fire at once and read as the
            // pill wobbling rather than moving. Neutralised so the motion is
            // one thing: position.
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
    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(index);
    } else {
      setState(() {
        _currentIndex = index;
        _pageRebuildKey++;
      });
    }
  }
}
