import 'package:flutter/material.dart';

import '../../services/cloud_sync_service.dart';
import '../calendar/calender_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../profile/profile_screen.dart';
import '../today/today_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // 1. Tell Flutter to start watching if the app is open or closed
    WidgetsBinding.instance.addObserver(this);

    _buildPages();

    // ✅ REMOVED: The redundant App Open backup is gone!
  }

  @override
  void dispose() {
    // Stop watching when the screen is destroyed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 2. THIS IS THE MAGIC TRICK!
  // It detects the exact millisecond the user minimizes or leaves the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // ✅ OPTIMIZED: It ONLY backs up when the app goes into the background
      _performSilentBackup();
    }
  }

  // The Silent Auto-Sync Engine
  Future<void> _performSilentBackup() async {
    await CloudSyncService().backupDataToCloud();
    debugPrint("☁️ Silent Auto-Backup Completed on App Close!");
  }

  void _buildPages() {
    _pages = [
      const DashboardScreen(),
      const TodayScreen(),
      const CalendarScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;

            // FORCE DASHBOARD REFRESH
            if (index == 0) {
              _buildPages();
            }
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.today_rounded),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
