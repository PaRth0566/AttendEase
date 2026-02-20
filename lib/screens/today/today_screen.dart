import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final TimetableDao _timetableDao = TimetableDao();
  final SubjectDao _subjectDao = SubjectDao();
  final AttendanceDao _attendanceDao = AttendanceDao();

  List<TimetableEntry> _todayEntries = [];
  Map<int, Subject> _subjectMap = {};

  bool _loading = true;
  bool _isOutsideSemester = false;
  final Map<int, String> _attendanceSelection = {};

  @override
  void initState() {
    super.initState();
    _loadTodayLectures();
  }

  Future<void> _loadTodayLectures() async {
    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;

    // ✅ Dynamic semester keys for complete isolation
    final startStr = prefs.getString('semester_start_$sem');
    final endStr = prefs.getString('semester_end_$sem');

    DateTime now = DateTime.now();
    DateTime todayNormalized = DateTime(now.year, now.month, now.day);
    bool outside = false;

    if (startStr != null) {
      DateTime start = DateTime.parse(startStr);
      if (todayNormalized.isBefore(
        DateTime(start.year, start.month, start.day),
      )) {
        outside = true;
      }
    }
    if (endStr != null) {
      DateTime end = DateTime.parse(endStr);
      if (todayNormalized.isAfter(DateTime(end.year, end.month, end.day))) {
        outside = true;
      }
    }

    final todayWeekday = now.weekday;

    // If it's Sunday OR outside the active semester dates, lock the screen
    if (todayWeekday == DateTime.sunday || outside) {
      if (!mounted) return;
      setState(() {
        _todayEntries = [];
        _attendanceSelection.clear();
        _isOutsideSemester = outside;
        _loading = false;
      });
      return;
    }

    // ✅ Fetch only for the active semester
    final entries = await _timetableDao.getEntriesForDay(todayWeekday, sem);
    final subjects = await _subjectDao.getSubjectsBySemester(sem);

    _subjectMap = {for (final s in subjects) s.id!: s};

    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedAttendance = await _attendanceDao.getAttendanceForDate(
      todayDate,
    );

    if (!mounted) return;

    setState(() {
      _todayEntries = entries;
      _attendanceSelection
        ..clear()
        ..addAll(savedAttendance);
      _loading = false;
    });
  }

  Future<void> _saveAttendance() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (final entry in _todayEntries) {
      final timetableId = entry.id!;
      final status = _attendanceSelection[timetableId];

      if (status == null) {
        await _attendanceDao.deleteAttendance(timetableId, today);
      } else {
        await _attendanceDao.upsertAttendance(
          timetableId: timetableId,
          date: today,
          status: status,
        );
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attendance saved')));
  }

  Widget _attendanceButton(int timetableId, String value, String label) {
    final selected = _attendanceSelection[timetableId] == value;
    final color = value == 'P' ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: color.withOpacity(0.15),
        labelStyle: TextStyle(
          color: selected ? color : Colors.black,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (bool isSelected) {
          setState(() {
            if (isSelected) {
              _attendanceSelection[timetableId] = value;
            } else {
              _attendanceSelection.remove(timetableId);
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat(
      'EEEE, MMM d, yyyy',
    ).format(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Today's Attendance",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formattedDate, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _todayEntries.isEmpty
                  ? Center(
                      child: Text(
                        _isOutsideSemester
                            ? 'Today is outside your active semester dates.'
                            : 'No lectures today',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _todayEntries.length,
                      itemBuilder: (_, i) {
                        final entry = _todayEntries[i];
                        final subject = _subjectMap[entry.subjectId]!;

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    subject.name,
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                _attendanceButton(entry.id!, 'P', 'Present'),
                                _attendanceButton(entry.id!, 'A', 'Absent'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            if (_todayEntries.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveAttendance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Attendance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
