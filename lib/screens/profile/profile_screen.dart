import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/theme_provider.dart'; // ✅ NEW IMPORT
import '../../widgets/backup_sync_card.dart';
import '../auth/login_screen.dart';
import '../dashboard/refresh_pdf_screen.dart';
import 'account_settings_screen.dart';
import 'bug_report_screen.dart';

import '../report/report_screen.dart';
import '../setup/add_subjects_screen.dart';
import '../setup/attendance_criteria_screen.dart';
import '../setup/basic_info_screen.dart';
import '../setup/timetable_setup_screen.dart';
import '../web/aura_landing_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AttendanceDao _attendanceDao = AttendanceDao();
  final SubjectDao _subjectDao = SubjectDao();

  String name = '';
  String course = '';
  String year = '';
  String division = '';
  int semester = 1;

  double overallAttendance = 0.0;
  bool _loading = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    semester = prefs.getInt('semester') ?? 1;

    final subjectsForSem = await _subjectDao.getSubjectsBySemester(semester);
    final stats = await _attendanceDao.getAttendanceStats(semester);

    int attended = 0;
    int total = 0;

    for (final sub in subjectsForSem) {
      final s = stats[sub.id];
      if (s != null) {
        attended += s['attended']!;
        total += s['total']!;
      }
    }

    setState(() {
      name = prefs.getString('full_name') ?? 'AttendEase User';
      course = prefs.getString('course') ?? '';
      year = prefs.getString('year') ?? '';
      division = prefs.getString('division') ?? '';

      overallAttendance = total == 0 ? 0.0 : (attended / total) * 100;
      _loading = false;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version} (${info.buildNumber})';
        });
      }
    } catch (_) {}
  }

  Future<void> _switchSemester(int newSemester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('semester', newSemester);

    setState(() => _loading = true);
    await _loadProfileData();

    // Auto-sync after switching semester
    CloudSyncService().backupDataToCloud();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to Semester $newSemester')),
    );
  }

  /// Pull-to-refresh: bidirectional cloud sync then reload
  Future<void> _syncAndReload() async {
    await CloudSyncService().syncBidirectional();
    await _loadProfileData();
  }

  Future<void> _handleLogout() async {
    final rootContext = context; // capture before dialog opens
    showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text(
          'Your data will be securely backed up to the cloud before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx); // close confirmation dialog

              // Show full-screen loading on root context
              showDialog(
                context: rootContext,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );

              try {
                bool backedUp = await CloudSyncService().backupDataToCloud();
                await AuthService().signOut();

                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                // Only wipe local data if cloud backup succeeded
                if (backedUp) {
                  final db = await DBHelper.instance.database;
                  await db.delete('attendance_records');
                  await db.delete('timetable');
                  await db.delete('subjects');
                }
              } catch (_) {}

              if (!mounted) return;
              rootContext.go(kIsWeb ? '/web/home' : '/login');
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Allows us to grab the current theme colors dynamically
    final theme = Theme.of(context);

    return Scaffold(
      // ✅ Removed hardcoded Colors.white
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: RefreshIndicator(
                  onRefresh: _syncAndReload,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width > 600 ? 32 : 16,
                      vertical: 16,
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor, // ✅ Dynamic Card Color
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.dividerColor,
                      ), // ✅ Dynamic Border
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [course, if (year.isNotEmpty) 'Year $year', if (division.isNotEmpty) division].where((e) => e.isNotEmpty).join(' • '),
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Semester $semester',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.percent,
                              size: 18,
                              color: theme
                                  .colorScheme
                                  .primary, // ✅ Dynamic primary
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Overall Attendance: ${overallAttendance.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color:
                          theme.scaffoldBackgroundColor, // ✅ Matches background
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Active Semester',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        DropdownButton<int>(
                          value: semester,
                          underline: const SizedBox(),
                          dropdownColor:
                              theme.cardColor, // ✅ Dynamic dropdown menu color
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: theme.colorScheme.primary,
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          items: List.generate(
                            8,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('Semester ${i + 1}'),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null && val != semester) {
                              _switchSemester(val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  _themeToggleTile(),

                  _profileTile(
                    icon: Icons.person_rounded,
                    title: 'Edit Profile & Dates',
                    onTap: () {
                      context.go('/app/profile/basic');
                    },
                  ),

                  _profileTile(
                    icon: Icons.book_rounded,
                    title: 'Edit Subjects (Sem $semester)',
                    onTap: () {
                      context.go('/app/profile/subjects');
                    },
                  ),

                  _profileTile(
                    icon: Icons.schedule_rounded,
                    title: 'Edit Timetable (Sem $semester)',
                    onTap: () {
                      context.go('/app/profile/timetable');
                    },
                  ),

                  _profileTile(
                    icon: Icons.rule_rounded,
                    title: 'Attendance Preferences',
                    onTap: () {
                      context.go('/app/profile/criteria');
                    },
                  ),

                  _profileTile(
                    icon: Icons.bar_chart_rounded,
                    title: 'Reports & Analytics',
                    onTap: () {
                      context.go('/app/profile/report');
                    },
                  ),

                  _profileTile(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Sync New Attendance Report',
                    onTap: () {
                      context.go('/app/profile/refresh-pdf');
                    },
                  ),

                  const SizedBox(height: 8),
                  BackupSyncCard(onSyncComplete: _loadProfileData),
                  const SizedBox(height: 8),

                  _profileTile(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Account Settings',
                    onTap: () {
                      context.go('/app/profile/account');
                    },
                  ),

                  _profileTile(
                    icon: Icons.bug_report_rounded,
                    title: 'Report a Bug',
                    onTap: () {
                      context.go('/app/profile/bug-report');
                    },
                  ),

                  _profileTile(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    isRedAlert:
                        true, // ✅ Uses dynamic styling for the red button
                    onTap: _handleLogout,
                  ),

                  const SizedBox(height: 16),
                  if (_appVersion.isNotEmpty)
                    Center(
                      child: Text(
                        'AttendEase $_appVersion',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _themeToggleTile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => RotationTransition(
            turns: Tween<double>(begin: 0.5, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
            key: ValueKey(isDark),
            color: theme.colorScheme.primary,
          ),
        ),
        title: const Text(
          'Dark Mode',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Switch.adaptive(
          value: isDark,
          activeColor: theme.colorScheme.primary,
          onChanged: (bool value) {
            themeProvider.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
            setState(() {});
          },
        ),
      ),
    );
  }

  // ✅ UPDATED: Dynamically colors the tiles based on Light/Dark Mode
  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isRedAlert = false,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      // If it's the logout button, make it a soft red. Otherwise, use the theme card color.
      color: isRedAlert
          ? (isDark ? Colors.red.withAlpha(38) : Colors.red.shade50)
          : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRedAlert ? Colors.red.withAlpha(76) : theme.dividerColor,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isRedAlert ? Colors.red : theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isRedAlert
                ? Colors.red
                : theme.textTheme.bodyLarge?.color, // ✅ Dynamic Text Color
          ),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isRedAlert ? Colors.red : Colors.grey,
            ),
        onTap: onTap,
      ),
    );
  }
}
