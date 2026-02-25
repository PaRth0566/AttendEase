import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart'; // ✅ NEW: Added the Cloud Sync Service import
import '../../widgets/backup_sync_card.dart';
import '../auth/login_screen.dart';
import '../report/report_screen.dart';
import '../setup/add_subjects_screen.dart';
import '../setup/attendance_criteria_screen.dart';
import '../setup/basic_info_screen.dart';
import '../setup/timetable_setup_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    semester = prefs.getInt('semester') ?? 1;

    final subjectsForSem = await _subjectDao.getSubjectsBySemester(semester);
    final stats = await _attendanceDao.getAttendanceStats();

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
  }

  Future<void> _switchSemester(int newSemester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('semester', newSemester);

    setState(() => _loading = true);
    await _loadProfileData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to Semester $newSemester')),
    );
  }

  // ✅ UPDATED: SECURE LOGOUT & AUTO-BACKUP FUNCTION
  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing while backing up
      builder: (context) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text(
          'Your data will be securely backed up to the cloud before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // Show a loading circle over the dialog while backing up
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );

              // 1. AUTO BACKUP TO CLOUD BEFORE WIPING!
              await CloudSyncService().backupDataToCloud();

              // 2. Log out of Google & Firebase Auth
              await AuthService().signOut();

              // 3. Wipe Local Settings (SharedPreferences)
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              // 4. Wipe SQLite Database
              final db = await DBHelper.instance.database;
              await db.delete('attendance_records');
              await db.delete('timetable');
              await db.delete('subjects');

              // 5. Send them back to the Login Screen
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
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
                          '$course • Year $year • Div $division',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Semester $semester',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.percent,
                              size: 18,
                              color: Color(0xFF2563EB),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Active Semester',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        DropdownButton<int>(
                          value: semester,
                          underline: const SizedBox(),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Color(0xFF2563EB),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
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

                  _profileTile(
                    icon: Icons.person_rounded,
                    title: 'Edit Profile & Dates',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const BasicInfoScreen(isEditMode: true),
                        ),
                      ).then((_) => _loadProfileData());
                    },
                  ),

                  _profileTile(
                    icon: Icons.book_rounded,
                    title: 'Edit Subjects (Sem $semester)',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AddSubjectsScreen(isEditMode: true),
                        ),
                      ).then((_) => _loadProfileData());
                    },
                  ),

                  _profileTile(
                    icon: Icons.schedule_rounded,
                    title: 'Edit Timetable (Sem $semester)',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const TimetableSetupScreen(isEditMode: true),
                        ),
                      );
                    },
                  ),

                  _profileTile(
                    icon: Icons.rule_rounded,
                    title: 'Attendance Preferences',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AttendanceCriteriaScreen(isEditMode: true),
                        ),
                      );
                    },
                  ),

                  _profileTile(
                    icon: Icons.bar_chart_rounded,
                    title: 'Reports & Analytics',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 8),
                  const BackupSyncCard(),
                  const SizedBox(height: 8),

                  _profileTile(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    textColor: Colors.red,
                    iconColor: Colors.red,
                    onTap: _handleLogout,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color textColor = Colors.black,
    Color iconColor = const Color(0xFF2563EB),
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: textColor == Colors.red
          ? Colors.red.shade50
          : const Color(0xFFF2F4FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: textColor == Colors.red
              ? Colors.red.shade200
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: textColor == Colors.red ? Colors.red : Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }
}
