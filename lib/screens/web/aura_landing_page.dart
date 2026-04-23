import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/cloud_sync_service.dart';
import '../../theme/theme_provider.dart';
import '../../models/subject.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import 'aura_upload_config.dart';
import 'aura_ai_dashboard.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class AuraLandingPage extends StatefulWidget {
  /// Which tab to show on first load.
  /// 0 = Home (default), 1 = Upload, 2 = Dashboard
  final int initialIndex;
  final StatefulNavigationShell? navigationShell;

  const AuraLandingPage({super.key, this.initialIndex = 0, this.navigationShell});

  @override
  State<AuraLandingPage> createState() => _AuraLandingPageState();
}

class _AuraLandingPageState extends State<AuraLandingPage> with SingleTickerProviderStateMixin {
  late int _currentIndex; // 0 = Home, 1 = Upload, 2 = Dashboard, 3 = Alerts (mobile only text)
  int _refreshKey = 0; // forces tab content rebuild on refresh

  List<Subject>? _parsedSubjects;
  Map<int, Map<String, int>>? _parsedStats;
  Map<String, String>? _reportMeta;
  double _overallTarget = 75.0;
  double _subjectTarget = 70.0;

  late AnimationController _bgAnimController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell?.currentIndex ?? widget.initialIndex;
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
    // Restore the last-viewed tab after a browser refresh (if not using router)
    if (widget.navigationShell == null) {
      _restoreTabIndex();
    }
  }

  @override
  void didUpdateWidget(AuraLandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell != null) {
      setState(() {
        _currentIndex = widget.navigationShell!.currentIndex;
      });
    }
  }

  /// Reads the saved tab index from storage and jumps to it.
  Future<void> _restoreTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('web_tab_index') ?? 0;
    // Only restore tabs 0 (Home) and 1 (Upload). Dashboard (2) requires
    // in-memory parsed data which won't survive a refresh, so fall back to Upload.
    final restoredIndex = saved == 2 ? 1 : saved;
    if (mounted && restoredIndex != _currentIndex) {
      setState(() => _currentIndex = restoredIndex);
    }
  }

  /// Saves the current tab index so a browser refresh can restore it.
  Future<void> _saveTabIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('web_tab_index', index);
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(index);
    } else {
      setState(() {
        _currentIndex = index;
      });
      _saveTabIndex(index); // persist so browser refresh restores this tab
    }
  }

  /// Pull-to-refresh handler: syncs cloud data and rebuilds current tab.
  Future<void> _handleRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await CloudSyncService().restoreDataFromCloud();
    }
    if (mounted) {
      setState(() {
        _refreshKey++; // force tab content to rebuild
      });
    }
  }

  /// Toggles between light and dark mode (2-click).
  /// Respects the OS default when first toggling from system mode.
  void _toggleTheme() {
    final effectivelyDark = themeProvider.isDarkMode;
    themeProvider.setThemeMode(
      effectivelyDark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Ambient Background Shapes
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (context, child) {
                final animValue = _bgAnimController.value;
                return Stack(
                  children: [
                    Positioned(
                      top: -150 + (animValue * 80),
                      right: -100 - (animValue * 60),
                      child: Container(
                        width: 500,
                        height: 500,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              isDark ? const Color(0xFF6366F1).withOpacity(0.15) : const Color(0xFF6366F1).withOpacity(0.08),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.4 - (animValue * 60),
                      left: -200 + (animValue * 80),
                      child: Container(
                        width: 600,
                        height: 600,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              isDark ? const Color(0xFF8B5CF6).withOpacity(0.1) : const Color(0xFF8B5CF6).withOpacity(0.05),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Main Canvas
          Column(
            children: [
              // TopNavBar
              _buildTopNavBar(isDark),
              
              // Scrollable Content Region
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: const Color(0xFF6366F1),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 100), // padding for mobile nav
                    child: _buildCurrentTab(isDark),
                  ),
                ),
              ),
            ],
          ),

          // BottomNavBar (Mobile Only)
          if (MediaQuery.of(context).size.width < 768)
             Positioned(
               bottom: 0,
               left: 0,
               right: 0,
               child: _buildBottomNavBar(isDark),
             ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab(bool isDark) {
    switch (_currentIndex) {
      case 1:
        return AuraUploadConfig(
          key: ValueKey('upload_$_refreshKey'),
          onConfigured: (subjects, stats, meta, overall, subject) {
            setState(() {
              _parsedSubjects = subjects;
              _parsedStats = stats;
              _reportMeta = meta;
              _overallTarget = overall;
              _subjectTarget = subject;
              _currentIndex = 2; // Jump to dashboard
            });
          },
        );
      case 2:
        if (_parsedSubjects != null && _parsedStats != null) {
          return AuraAIDashboard(
            key: ValueKey('dashboard_$_refreshKey'),
            subjects: _parsedSubjects!,
            attendanceStats: _parsedStats!,
            overallTarget: _overallTarget,
            subjectTarget: _subjectTarget,
            reportMeta: _reportMeta,
          );
        }
        return ProfileScreen(key: ValueKey('profile_$_refreshKey'));
      case 0:
      default:
        return _buildHomeTab(isDark);
    }
  }

  // ── Top Nav Bar ──
  Widget _buildTopNavBar(bool isDark) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w >= 768;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          height: 64, // Reduced height
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A).withOpacity(0.3) : Colors.white.withOpacity(0.95),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF6366F1).withOpacity(0.2) : const Color(0xFFE2E8F0),
              ),
            ),
            boxShadow: [
               if (isDark) BoxShadow(
                 color: Colors.black.withOpacity(0.5),
                 blurRadius: 30,
                 offset: const Offset(0, 4),
               ),
               if (!isDark) BoxShadow(
                 color: Colors.black.withOpacity(0.02),
                 blurRadius: 10,
                 offset: const Offset(0, 4),
               ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Section: Brand + Nav
              Row(
                children: [
                  // Brand — tapping returns to Home
                  GestureDetector(
                    onTap: () => _onNavTap(0),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        children: [
                          Image.asset('assets/icon/app_icon2.png',
                              width: 32,
                              height: 32,
                              errorBuilder: (c, e, s) => Icon(Icons.school,
                                  color: isDark
                                      ? const Color(0xFFA5B4FC)
                                      : const Color(0xFF4F46E5))),
                          const SizedBox(width: 12),
                          Text(
                            'AttendEase',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              foreground: Paint()
                                ..shader = LinearGradient(
                                  colors: isDark
                                      ? [const Color(0xFFA5B4FC), const Color(0xFFC7D2FE)]
                                      : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                                ).createShader(const Rect.fromLTWH(0, 0, 150, 40)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Desktop Nav
                  if (isDesktop) ...[
                    const SizedBox(width: 48), // Gap between brand and nav
                    Row(
                      children: [
                        _navItem('Home', 0, isDark),
                        const SizedBox(width: 32),
                        _navItem('Upload', 1, isDark),
                        if (_parsedSubjects != null) ...[
                          const SizedBox(width: 32),
                          _navItem('Dashboard', 2, isDark),
                        ],
                      ],
                    ),
                  ],
                ],
              ),

              // Trailing — 2-click theme toggle: light ↔ dark
              Row(
                children: [
                  Tooltip(
                    message: themeProvider.isDarkMode
                        ? 'Switch to Light Mode'
                        : 'Switch to Dark Mode',
                    child: IconButton(
                      onPressed: _toggleTheme,
                      icon: Icon(
                        themeProvider.isDarkMode
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: isDark
                            ? const Color(0xFFC7D2FE)
                            : const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(String label, int index, bool isDark) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => _onNavTap(index),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isSelected 
              ? (isDark ? Colors.white : const Color(0xFF111319))
              : (isDark ? const Color(0xFFC7D2FE).withOpacity(0.8) : const Color(0xFF64748B)),
        ),
      ),
    );
  }

  // ── Bottom Nav (Mobile) ──
  Widget _buildBottomNavBar(bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
             color: isDark ? const Color(0xFF0F172A).withOpacity(0.4) : Colors.white.withOpacity(0.8),
             border: Border(
               top: BorderSide(
                 color: isDark ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.black.withOpacity(0.05),
               ),
             ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _bottomNavItem(Icons.home_rounded, 'Home', 0, isDark),
              _bottomNavItem(Icons.cloud_upload_rounded, 'Upload', 1, isDark),
              if (_parsedSubjects != null)
                _bottomNavItem(Icons.dashboard_rounded, 'Dashboard', 2, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem(IconData icon, String label, int index, bool isDark) {
    final isSelected = _currentIndex == index;
    final color = isSelected 
        ? (isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5))
        : (isDark ? const Color(0xFFC7D2FE).withOpacity(0.6) : const Color(0xFF94A3B8));

    return InkWell(
      onTap: () => _onNavTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: isSelected
          ? BoxDecoration(
              color: isDark ? const Color(0xFF6366F1).withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.transparent,
              ),
            )
          : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Home Tab ──
  Widget _buildHomeTab(bool isDark) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 768;
    final isTablet = w >= 768 && w < 1024;

    return Column(
      children: [
        // Hero
        Padding(
          padding: EdgeInsets.only(top: 20, bottom: 5, left: isMobile ? 16 : 24, right: isMobile ? 16 : 24),
          child: Column(
            children: [
              _buildVerfiedBadge(isDark),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF6366F1).withOpacity(0.1)
                      : const Color(0xFF6366F1).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF818CF8).withOpacity(0.3)
                        : const Color(0xFF6366F1).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 13, color: Color(0xFF818CF8)),
                    const SizedBox(width: 6),
                    Text(
                      'Smart Attendance Insights',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF818CF8)
                            : const Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AttendEase',
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width < 768 ? 32 : 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                  foreground: Paint()
                    ..shader = LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFFA5B4FC),
                              const Color(0xFFC4B5FD),
                              const Color(0xFFD8B4FE)
                            ]
                          : [
                              const Color(0xFF4F46E5),
                              const Color(0xFF6366F1),
                              const Color(0xFF818CF8)
                            ],
                    ).createShader(const Rect.fromLTWH(0, 0, 400, 100)),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 20),
                  child: Text(
                    'Upload your detailed attendance report and get instant insights '
                    'into your college attendance — track progress, spot trends, and '
                    'stay on top of every subject.',
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      color: isDark
                          ? Colors.white.withOpacity(0.6)
                          : const Color(0xFF64748B),
                      height: 1.65,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                    InkWell(
                      onTap: () => _onNavTap(1), // Go to upload
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 22 : 30,
                            vertical: isMobile ? 10 : 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.plagiarism_rounded,
                                color: Colors.white, size: 26),
                            const SizedBox(width: 6),
                            Text('Analyze PDF Report',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: isMobile ? 14 : 16)),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        if (FirebaseAuth.instance.currentUser != null) {
                          context.push('/app/dashboard');
                        } else {
                          context.push('/login');
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 22 : 30,
                            vertical: isMobile ? 10 : 14),
                        decoration: BoxDecoration(
                           color: isDark ? const Color(0xFF0F172A).withOpacity(0.5) : Colors.white,
                           borderRadius: BorderRadius.circular(12),
                           border: Border.all(
                             color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFF94A3B8),
                           ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                FirebaseAuth.instance.currentUser != null
                                    ? Icons.dashboard_rounded
                                    : Icons.login_rounded,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                                size: 24),
                            const SizedBox(width: 8),
                            Text(
                                FirebaseAuth.instance.currentUser != null
                                    ? 'Go to Dashboard'
                                    : 'Sign In',
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w600,
                                    fontSize: isMobile ? 14 : 16)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSAPPortalNote(isDark, isMobile),
            ],
          ),
        ),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1024),
            child: _buildFeatureCards(isDark, isMobile, isTablet),
          ),
        ),

        const SizedBox(height: 12),
        // Disclaimer
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color:
                    isDark ? Colors.red.withOpacity(0.1) : Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.red.withOpacity(0.3)
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 22,
                    color: isDark ? Colors.red.shade400 : Colors.red.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Disclaimer: AttendEase is an automated tool. We are not liable for any calculation inaccuracies or resulting consequences. Please verify your attendance with official college records.',
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildVerfiedBadge(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFF6366F1).withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
         border: Border.all(
            color: isDark ? const Color(0xFF818CF8).withOpacity(0.3) : const Color(0xFF6366F1).withOpacity(0.2),
         ),
         boxShadow: [
           BoxShadow(
             color: isDark ? Colors.black.withOpacity(0.5) : const Color(0xFF6366F1).withOpacity(0.05),
             blurRadius: isDark ? 32 : 10,
             offset: const Offset(0, 8),
           ),
         ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/icon/app_icon2.png',
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stk) => Center(
            child: Icon(
              Icons.verified_user_rounded,
              size: 48,
              color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
            ),
          ),
        ),
      ),
    );
  }

  void _featureCardHelper() {} // Placeholder for potential future use

  // ── FEATURE CARDS ─────────────────────────────────────────
  Widget _buildFeatureCards(bool isDark, bool isMobile, bool isTablet) {
    final features = [
      (
        Icons.document_scanner_rounded,
        'Upload & Analyze',
        'Get a complete breakdown from your PDF report.',
        const Color(0xFF6366F1),
      ),
      (
        Icons.bar_chart_rounded,
        'Track Progress',
        'See percentages, lectures attended, and targets.',
        const Color(0xFF3B82F6),
      ),
      (
        Icons.calendar_month_rounded,
        'Calendar View',
        'Visualize attendance day by day on a calendar.',
        const Color(0xFF8B5CF6),
      ),
      (
        Icons.notifications_active_rounded,
        'Stay Informed',
        'Know how many lectures you can skip or must attend.',
        const Color(0xFF06B6D4),
      ),
    ];

    final w = MediaQuery.of(context).size.width;
    final double horizontalPadding = isMobile ? 16 : 24;
    final double spacing = isMobile ? 12 : 24;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      alignment: WrapAlignment.center,
      children: features
          .map((f) => _featureCard(isDark, f.$1, f.$2, f.$3, f.$4, isMobile))
          .toList(),
    );
  }

  Widget _featureCard(
      bool isDark, IconData icon, String title, String desc, Color accent, bool isMobile) {
    final w = MediaQuery.of(context).size.width;
    double cardW = double.infinity;
    
    if (w >= 1024) {
      cardW = ((w > 1024 ? 1024 : w) - 120) / 4;
    } else if (w >= 768) {
      cardW = (w - 72) / 2;
    } else {
      // 2 columns on mobile
      cardW = (w - 32 - 12) / 2; // 32 is screen padding, 12 is spacing
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: cardW,
          height: isMobile ? 180 : 200,
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
             color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
             borderRadius: BorderRadius.circular(20),
             border: Border.all(
               color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0),
               width: 1.5,
             ),
             boxShadow: [
               BoxShadow(
                 color: Colors.black.withOpacity(isDark ? 0.4 : 0.05),
                 blurRadius: isDark ? 25 : 10,
                 offset: const Offset(0, 8),
               )
             ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isMobile ? 36 : 48,
                height: isMobile ? 36 : 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Icon(icon, color: accent, size: isMobile ? 18 : 24),
              ),
              SizedBox(height: isMobile ? 12 : 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 15 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  desc,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 13,
                    height: 1.4,
                    color: isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF64748B),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchSAPPortal() async {
    final Uri url =
        Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  // ── SAP PORTAL NOTE ───────────────────────────────────────
  Widget _buildSAPPortalNote(bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFFDBA74).withOpacity(0.5),
        ),
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_rounded,
                        size: 15,
                        color: isDark
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'SVKM / Mithibai students? Get your report from',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white.withOpacity(0.55)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _sapPortalChip(isDark),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school_rounded,
                    size: 16,
                    color: isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: 'SVKM / Mithibai students? ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFD97706),
                      ),
                      children: [
                        TextSpan(
                          text: 'Get your report from ',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? Colors.white.withOpacity(0.5)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sapPortalChip(isDark),
              ],
            ),
    );
  }

  Widget _sapPortalChip(bool isDark) {
    return InkWell(
      onTap: _launchSAPPortal,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFFFBBF24).withOpacity(0.15)
              : const Color(0xFFFBBF24).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? const Color(0xFFFBBF24).withOpacity(0.3)
                : const Color(0xFFD97706).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new_rounded,
                size: 12,
                color: isDark
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFFD97706)),
            const SizedBox(width: 4),
            Text(
              'SAP Portal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFFD97706),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
