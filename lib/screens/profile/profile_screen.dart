import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart'; // ✅ Added to calculate accurate semester attendance
import '../report/report_screen.dart'; // ✅ IMPORTED THE NEW REPORT SCREEN
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
  final SubjectDao _subjectDao =
      SubjectDao(); // ✅ For fetching current semester's subjects

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

    // ✅ SMART ATTENDANCE CALCULATION: Only calculate for the currently active semester
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

  // ✅ PHASE 2: SEMESTER SWITCHER LOGIC
  Future<void> _switchSemester(int newSemester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('semester', newSemester);

    setState(() => _loading = true);
    await _loadProfileData(); // Reloads attendance for the new semester

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to Semester $newSemester')),
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
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // =========================
                  // RESTORED STUDENT CARD
                  // =========================
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

                  // =========================
                  // NEW UI: SEMESTER SWITCHER
                  // =========================
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

                  // =========================
                  // SETTINGS OPTIONS
                  // =========================
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
                      ).then(
                        (_) => _loadProfileData(),
                      ); // Recalculate attendance if subjects change
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

                  // ✅ NEW REAL BUTTON FOR REPORTS & ANALYTICS
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
                ],
              ),
            ),
    );
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFF2F4FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2563EB)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
