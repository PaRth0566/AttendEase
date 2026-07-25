import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import '../../services/cloud_sync_service.dart';
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
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _buildPage(_currentIndex),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            if (widget.navigationShell != null) {
              widget.navigationShell!.goBranch(index);
            } else {
              setState(() {
                _currentIndex = index;
                _pageRebuildKey++;
              });
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
