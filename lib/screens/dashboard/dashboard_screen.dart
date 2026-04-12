import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import '../report/subject_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final List<Subject>? overrideSubjects;
  final Map<int, Map<String, int>>? overrideStats;

  const DashboardScreen({super.key, this.overrideSubjects, this.overrideStats});

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

  int _totalAttendedOverall = 0;
  int _totalLecturesOverall = 0;

  int _currentStreak = 0;

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

    if (widget.overrideSubjects != null && widget.overrideStats != null) {
      // Bypass database and use provided data immediately
      _subjects = widget.overrideSubjects!;
      _attendanceStats = widget.overrideStats!;
      _currentStreak = 0; 
    } else {
      _subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
      _attendanceStats = await _attendanceDao.getAttendanceStats();
      _currentStreak = await _attendanceDao.getCurrentStreak();
    }

    _totalAttendedOverall = 0;
    _totalLecturesOverall = 0;

    for (final subject in _subjects) {
      final stat = _attendanceStats[subject.id] ?? {'attended': 0, 'total': 0};
      _totalAttendedOverall += stat['attended']!;
      _totalLecturesOverall += stat['total']!;
    }

    _currentOverall = _totalLecturesOverall == 0
        ? 0
        : (_totalAttendedOverall / _totalLecturesOverall) * 100;

    _subjects.sort((a, b) {
      final statA = _attendanceStats[a.id] ?? {'attended': 0, 'total': 0};
      final statB = _attendanceStats[b.id] ?? {'attended': 0, 'total': 0};

      final double percentA = statA['total'] == 0
          ? 0.0
          : (statA['attended']! / statA['total']!) * 100;
      final double percentB = statB['total'] == 0
          ? 0.0
          : (statB['attended']! / statB['total']!) * 100;

      int comparison = percentA.compareTo(percentB);
      if (comparison == 0) return a.name.compareTo(b.name);
      return comparison;
    });

    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> _getPredictiveInsight(
    int attended,
    int total,
    double requiredPercent,
  ) {
    if (total == 0)
      return {'text': 'No classes recorded yet.', 'isSafe': true, 'skips': 0};

    double reqFrac = requiredPercent / 100;
    double currentPercent = (attended / total) * 100;

    if (currentPercent >= requiredPercent) {
      int skips = ((attended / reqFrac) - total).floor();
      if (skips <= 0)
        return {
          'text': 'On track, but you cannot skip the next lecture.',
          'isSafe': true,
          'skips': 0,
        };
      return {
        'text':
            'You can safely skip the next $skips lecture${skips > 1 ? 's' : ''}.',
        'isSafe': true,
        'skips': skips,
      };
    } else {
      int attends = (((reqFrac * total) - attended) / (1 - reqFrac)).ceil();
      return {
        'text':
            'Attend the next $attends lecture${attends > 1 ? 's' : ''} to reach ${requiredPercent.toStringAsFixed(0)}%.',
        'isSafe': false,
        'attends': attends,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    bool isSafe = _currentOverall >= _requiredTarget;
    Color statusColor = isSafe ? Colors.green : Colors.red;
    IconData statusIcon = isSafe ? Icons.check_rounded : Icons.close_rounded;
    final overallInsight = _getPredictiveInsight(
      _totalAttendedOverall,
      _totalLecturesOverall,
      _requiredTarget,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Dashboard',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        actions: [
          // ✅ CHANGED: Only shows up if streak is 3 or more days!
          if (_currentStreak >= 3)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withAlpha(25)
                        : Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_currentStreak',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Semester $_activeSemester Overview',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // OVERALL ATTENDANCE CARD
            Card(
              color: theme.cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Overall Attendance',
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_currentOverall.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: theme.textTheme.bodyLarge?.color,
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
                                backgroundColor: theme.dividerColor,
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

                  // BUNK PLANNER: OVERALL INSIGHT
                  if (_totalLecturesOverall > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: overallInsight['isSafe']
                            ? Colors.green.withAlpha(isDark ? 38 : 25)
                            : Colors.red.withAlpha(isDark ? 38 : 25),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            overallInsight['isSafe']
                                ? Icons.lightbulb_outline
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: overallInsight['isSafe']
                                ? (isDark
                                      ? Colors.green.shade400
                                      : Colors.green.shade700)
                                : (isDark
                                      ? Colors.red.shade400
                                      : Colors.red.shade700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              overallInsight['text'],
                              style: TextStyle(
                                color: overallInsight['isSafe']
                                    ? (isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade800)
                                    : (isDark
                                          ? Colors.red.shade300
                                          : Colors.red.shade800),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Your Subjects',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 12),

            // SUBJECT LIST
            if (_subjects.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Text(
                  'No subjects added for this semester yet.',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
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
                    subject,
                    percent,
                    stat['attended']!,
                    stat['total']!,
                    theme,
                    isDark,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // =========================
  // SUBJECT CARD
  // =========================
  Widget _subjectCard(
    Subject subject,
    double percent,
    int attended,
    int total,
    ThemeData theme,
    bool isDark,
  ) {
    Color color = percent >= subject.requiredPercent
        ? Colors.green
        : percent >= (subject.requiredPercent - 10)
        ? Colors.orange
        : Colors.red;
    final insight = _getPredictiveInsight(
      attended,
      total,
      subject.requiredPercent,
    );

    return Card(
      color: theme.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubjectDetailScreen(subject: subject),
            ),
          ).then((_) {
            setState(() => _loading = true);
            _loadDashboardData();
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                subject.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: theme.dividerColor,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : percent / 100,
                    color: color,
                    backgroundColor: theme.dividerColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$attended/$total lectures',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        percent >= subject.requiredPercent ? 'Safe' : 'Risk',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (total > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: insight['isSafe']
                      ? Colors.green.withAlpha(isDark ? 38 : 25)
                      : Colors.red.withAlpha(isDark ? 38 : 25),
                ),
                child: Row(
                  children: [
                    Icon(
                      insight['isSafe']
                          ? Icons.lightbulb_outline
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: insight['isSafe']
                          ? (isDark
                                ? Colors.green.shade400
                                : Colors.green.shade700)
                          : (isDark
                                ? Colors.red.shade400
                                : Colors.red.shade700),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        insight['text'],
                        style: TextStyle(
                          color: insight['isSafe']
                              ? (isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade800)
                              : (isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade800),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
