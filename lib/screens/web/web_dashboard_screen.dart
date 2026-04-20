import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import 'gemini_insights_panel.dart';

class WebDashboardScreen extends StatefulWidget {
  const WebDashboardScreen({super.key});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
    _wakeUpBackend();
  }

  void _wakeUpBackend() {
    try {
      http.get(Uri.parse(
          'https://attendease-backend-ndxs.onrender.com/api/health'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _launchSAPPortal() async {
    final Uri url =
        Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  void _goToInsights() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _WebInsightsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _buildLandingPage(theme, isDark);
  }

  // ── LANDING PAGE ──────────────────────────────────────────
  Widget _buildLandingPage(ThemeData theme, bool isDark) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;

    // Responsive breakpoints
    final isMobile = w < 600;
    final isTablet = w >= 600 && w < 1024;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF1E1B4B),
                    const Color(0xFF0F172A),
                  ]
                : [
                    const Color(0xFFF0F4FF),
                    const Color(0xFFEEF2FF),
                    const Color(0xFFF8FAFF),
                  ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative blurred circles
            Positioned(
              top: -80,
              right: -80,
              child:
                  _glowCircle(280, const Color(0xFF6366F1).withOpacity(0.15)),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child:
                  _glowCircle(220, const Color(0xFF3B82F6).withOpacity(0.12)),
            ),

            // ── Scrollable content with HIDDEN scrollbar ──
            SafeArea(
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : (isTablet ? 40 : 60),
                              vertical: isMobile ? 28 : 40,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ── Hero Section ──
                                Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 640),
                                    child: _buildHeroSection(
                                        isDark, isMobile, isTablet),
                                  ),
                                ),

                                SizedBox(height: isMobile ? 16 : 24),

                                // ── Disclaimer ──
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 640),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.red.withOpacity(0.1) : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark ? Colors.red.withOpacity(0.3) : Colors.red.shade200,
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

                                SizedBox(height: isMobile ? 24 : 36),

                                // ── Feature Cards ──
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 960),
                                  child: _buildFeatureCards(
                                      isDark, isMobile, isTablet),
                                ),

                                SizedBox(height: isMobile ? 16 : 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HERO SECTION ──────────────────────────────────────────
  Widget _buildHeroSection(bool isDark, bool isMobile, bool isTablet) {
    final titleSize = isMobile ? 36.0 : (isTablet ? 46.0 : 54.0);
    final subtextSize = isMobile ? 14.0 : 16.0;
    final logoSize = isMobile ? 72.0 : 88.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isMobile ? 20 : 24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withOpacity(0.3),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(isDark ? 0.12 : 0.7),
              width: 2,
            ),
            image: const DecorationImage(
              image: AssetImage('assets/icon/app_icon2.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: isMobile ? 20 : 28),

        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: const Color(0xFF6366F1).withOpacity(0.3),
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
        SizedBox(height: isMobile ? 14 : 20),

        // Title
        Text(
          'AttendEase',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
            height: 1.05,
            foreground: Paint()
              ..shader = LinearGradient(
                colors: isDark
                    ? [Colors.white, const Color(0xFFA5B4FC)]
                    : [const Color(0xFF1E1B4B), const Color(0xFF4F46E5)],
              ).createShader(const Rect.fromLTWH(0, 0, 400, 70)),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isMobile ? 12 : 16),

        // Subtitle
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 20),
          child: Text(
            'Upload your detailed attendance report and get instant insights '
            'into your college attendance — track progress, spot trends, and '
            'stay on top of every subject.',
            style: TextStyle(
              fontSize: subtextSize,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : const Color(0xFF64748B),
              height: 1.65,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: isMobile ? 22 : 30),

        // CTA Buttons
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _buildPrimaryBtn(isMobile),
            _buildSignInBtn(isDark, isMobile),
          ],
        ),
        SizedBox(height: isMobile ? 14 : 18),

        // SAP Portal Note
        _buildSAPPortalNote(isDark, isMobile),
      ],
    );
  }

  // ── SAP PORTAL NOTE ───────────────────────────────────────
  Widget _buildSAPPortalNote(bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : const Color(0xFFFFF7ED),
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

  // ── FEATURE CARDS ─────────────────────────────────────────
  Widget _buildFeatureCards(bool isDark, bool isMobile, bool isTablet) {
    final features = [
      (
        Icons.upload_file_rounded,
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

    if (isMobile) {
      // Mobile: 2x2 grid
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                  child: _featureCard(features[0], isDark, compact: true)),
              const SizedBox(width: 10),
              Expanded(
                  child: _featureCard(features[1], isDark, compact: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _featureCard(features[2], isDark, compact: true)),
              const SizedBox(width: 10),
              Expanded(
                  child: _featureCard(features[3], isDark, compact: true)),
            ],
          ),
        ],
      );
    }

    // Tablet & Desktop: single row
    return Row(
      children: features
          .map((f) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _featureCard(f, isDark, compact: isTablet),
                ),
              ))
          .toList(),
    );
  }

  Widget _featureCard(
    (IconData, String, String, Color) data,
    bool isDark, {
    bool compact = false,
  }) {
    final (icon, title, desc, color) = data;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 32 : 38,
            height: compact ? 32 : 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: compact ? 16 : 18),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              height: 1.4,
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : const Color(0xFF94A3B8),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── BUTTONS ───────────────────────────────────────────────
  Widget _buildPrimaryBtn(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _goToInsights,
        icon: const Icon(Icons.upload_file_rounded, size: 18),
        label: const Text('Analyze PDF Report'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 28,
            vertical: isMobile ? 14 : 18,
          ),
          textStyle: TextStyle(
              fontSize: isMobile ? 14 : 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildSignInBtn(bool isDark, bool isMobile) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      },
      icon: const Icon(Icons.person_rounded, size: 18),
      label: const Text('Sign In'),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
        side: BorderSide(
          color: isDark
              ? const Color(0xFF6366F1).withOpacity(0.5)
              : const Color(0xFF6366F1).withOpacity(0.4),
          width: 1.5,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 28,
          vertical: isMobile ? 14 : 18,
        ),
        textStyle: TextStyle(
            fontSize: isMobile ? 14 : 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// ── Dedicated Insights Screen (enables browser back button) ──────────
class _WebInsightsScreen extends StatelessWidget {
  const _WebInsightsScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Top nav bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.white.withOpacity(0.8),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    image: const DecorationImage(
                      image: AssetImage('assets/icon/app_icon2.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'AttendEase',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: isDark ? Colors.white70 : Colors.black54),
                  label: Text(
                    'Back to Home',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: GeminiInsightsPanel(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
