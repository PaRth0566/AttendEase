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
              child: _glowCircle(280, const Color(0xFF6366F1).withOpacity(0.15)),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: _glowCircle(220, const Color(0xFF3B82F6).withOpacity(0.12)),
            ),

            // Main content
            Center(
              child: SingleChildScrollView(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6366F1)
                                        .withOpacity(0.3),
                                    blurRadius: 40,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(
                                      isDark ? 0.12 : 0.7),
                                  width: 2,
                                ),
                                image: const DecorationImage(
                                  image:
                                      AssetImage('assets/icon/app_icon2.png'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),

                            // Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color:
                                      const Color(0xFF6366F1).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.auto_awesome,
                                      size: 13, color: Color(0xFF818CF8)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Powered by Gemini AI',
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
                            const SizedBox(height: 20),

                            // Title
                            Text(
                              'AttendEase',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2,
                                height: 1.05,
                                foreground: Paint()
                                  ..shader = LinearGradient(
                                    colors: isDark
                                        ? [
                                            Colors.white,
                                            const Color(0xFFA5B4FC),
                                          ]
                                        : [
                                            const Color(0xFF1E1B4B),
                                            const Color(0xFF4F46E5),
                                          ],
                                  ).createShader(const Rect.fromLTWH(
                                      0, 0, 400, 70)),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 18),

                            // Subtext
                            Text(
                              'Unlock smart insights into your college attendance. Download your report from the SAP portal and let Gemini AI analyze it in seconds.',
                              style: TextStyle(
                                fontSize: 17,
                                color: isDark
                                    ? Colors.white.withOpacity(0.6)
                                    : const Color(0xFF64748B),
                                height: 1.7,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 52),

                            // Step guide
                            _buildStepGuide(isDark),
                            const SizedBox(height: 40),

                            // CTA Buttons
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildOutlinedBtn(isDark),
                                _buildPrimaryBtn(),
                                _buildSignInBtn(isDark),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepGuide(bool isDark) {
    final steps = [
      (Icons.login_rounded, 'Login to SAP', 'Open the college portal'),
      (Icons.download_rounded, 'Download Report', 'Save your PDF attendance report'),
      (Icons.upload_file_rounded, 'Upload & Analyze', 'Let AI generate your insights'),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (i) {
          final step = steps[i];
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(step.$1, color: const Color(0xFF6366F1), size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  step.$2,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  step.$3,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white.withOpacity(0.45)
                        : const Color(0xFF94A3B8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOutlinedBtn(bool isDark) {
    return OutlinedButton.icon(
      onPressed: _launchSAPPortal,
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: const Text('SAP Portal'),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.2)
              : const Color(0xFFCBD5E1),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildPrimaryBtn() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _goToInsights,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Analyze PDF Report'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInBtn(bool isDark) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      icon: const Icon(Icons.person_rounded, size: 18),
      label: const Text('Sign In'),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
        side: BorderSide(
          color: isDark
              ? const Color(0xFF6366F1).withOpacity(0.5)
              : const Color(0xFF6366F1).withOpacity(0.4),
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
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
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
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
