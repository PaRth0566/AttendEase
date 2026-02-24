import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SubjectDao _subjectDao = SubjectDao();
  final AttendanceDao _attendanceDao = AttendanceDao();

  List<Subject> _subjects = [];
  Map<int, Map<String, int>> _attendanceStats = {};

  double _currentOverall = 0.0;
  double _requiredTarget = 75.0;
  int _activeSemester = 1;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final prefs = await SharedPreferences.getInstance();
    _requiredTarget = prefs.getDouble('overall_required_attendance') ?? 75.0;
    _activeSemester = prefs.getInt('semester') ?? 1;

    _subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
    _attendanceStats = await _attendanceDao.getAttendanceStats();

    int totalAttended = 0;
    int totalLectures = 0;

    for (final subject in _subjects) {
      final stat = _attendanceStats[subject.id] ?? {'attended': 0, 'total': 0};
      totalAttended += stat['attended']!;
      totalLectures += stat['total']!;
    }

    _currentOverall = totalLectures == 0
        ? 0
        : (totalAttended / totalLectures) * 100;

    // ✅ NEW LOGIC: Sort subjects by attendance percentage (Lowest to Highest)
    _subjects.sort((a, b) {
      final statA = _attendanceStats[a.id] ?? {'attended': 0, 'total': 0};
      final statB = _attendanceStats[b.id] ?? {'attended': 0, 'total': 0};

      final double percentA = statA['total'] == 0
          ? 0.0
          : (statA['attended']! / statA['total']!) * 100;
      final double percentB = statB['total'] == 0
          ? 0.0
          : (statB['attended']! / statB['total']!) * 100;

      // Ascending sort (Lowest at the top)
      int comparison = percentA.compareTo(percentB);

      // If percentages are identical, sort alphabetically by name as a tie-breaker
      if (comparison == 0) {
        return a.name.compareTo(b.name);
      }
      return comparison;
    });

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isSafe = _currentOverall >= _requiredTarget;
    Color statusColor = isSafe ? Colors.green : Colors.red;
    IconData statusIcon = isSafe ? Icons.check_rounded : Icons.close_rounded;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Semester $_activeSemester Overview',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // OVERALL ATTENDANCE CARD
            Card(
              color: const Color(0xFFF2F4FF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overall Attendance',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_currentOverall.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Target: ${_requiredTarget.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 70,
                          width: 70,
                          child: CircularProgressIndicator(
                            value: _currentOverall / 100,
                            backgroundColor: Colors.white,
                            color: statusColor,
                            strokeWidth: 8,
                          ),
                        ),
                        Icon(statusIcon, color: statusColor, size: 34),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Your Subjects',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // SUBJECT LIST
            if (_subjects.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: const Text(
                  'No subjects added for this semester yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _subjects.length,
                itemBuilder: (_, i) {
                  final subject = _subjects[i];
                  final stat =
                      _attendanceStats[subject.id] ??
                      {'attended': 0, 'total': 0};

                  final double percent = stat['total'] == 0
                      ? 0.0
                      : ((stat['attended']! / stat['total']!) * 100);

                  return _subjectCard(
                    subject.name,
                    percent,
                    stat['attended']!,
                    stat['total']!,
                    subject.requiredPercent,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // SUBJECT CARD
  static Widget _subjectCard(
    String subjectName,
    double percent,
    int attended,
    int total,
    double requiredPercent,
  ) {
    Color color = percent >= requiredPercent
        ? Colors.green
        : percent >= (requiredPercent - 10)
        ? Colors.orange
        : Colors.red;

    return Card(
      color: const Color(0xFFF2F4FF),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  subjectName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: percent / 100,
              color: color,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$attended/$total lectures',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  percent >= requiredPercent ? 'Safe' : 'Risk',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
