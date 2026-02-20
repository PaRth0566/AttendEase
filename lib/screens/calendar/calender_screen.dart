import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final TimetableDao _timetableDao = TimetableDao();
  final SubjectDao _subjectDao = SubjectDao();
  final AttendanceDao _attendanceDao = AttendanceDao();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime _firstDay = DateTime.now().subtract(const Duration(days: 365));
  DateTime _lastDay = DateTime.now().add(const Duration(days: 365));

  List<TimetableEntry> _dayEntries = [];
  Map<int, Subject> _subjectMap = {};

  bool _loading = true;
  bool _isCalendarReady = false;

  final Map<int, String> _attendanceSelection = {};

  // ✅ HEATMAP DATA VARIABLES
  Map<DateTime, String> _monthStatuses = {};
  Map<int, int> _lecturesPerDay = {};

  @override
  void initState() {
    super.initState();
    _initCalendarDates();
  }

  Future<void> _initCalendarDates() async {
    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;

    final startStr = prefs.getString('semester_start_$sem');
    final endStr = prefs.getString('semester_end_$sem');

    DateTime normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

    DateTime parsedStart = DateTime.now();
    DateTime parsedEnd = DateTime.now().add(const Duration(days: 180));

    if (startStr != null) parsedStart = DateTime.parse(startStr);
    if (endStr != null) {
      parsedEnd = DateTime.parse(endStr);
    } else {
      parsedEnd = parsedStart.add(const Duration(days: 180));
    }

    final now = DateTime.now();
    DateTime initialFocus = now;

    if (now.isBefore(parsedStart))
      initialFocus = parsedStart;
    else if (now.isAfter(parsedEnd))
      initialFocus = parsedEnd;

    // Fetch how many lectures happen on each day of the week to calculate "Forgot" status
    for (int i = 1; i <= 6; i++) {
      final entries = await _timetableDao.getEntriesForDay(i, sem);
      _lecturesPerDay[i] = entries.length;
    }

    setState(() {
      _firstDay = normalize(parsedStart);
      _lastDay = normalize(parsedEnd);
      _focusedDay = normalize(initialFocus);
      _selectedDay = normalize(initialFocus);
      _isCalendarReady = true;
    });

    await _fetchMonthData(_focusedDay);
    await _loadForDate(_selectedDay!);
  }

  // ============================
  // ✅ NEW: CALCULATE COLORS FOR ENTIRE MONTH
  // ============================
  Future<void> _fetchMonthData(DateTime month) async {
    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;

    DateTime monthStart = DateTime(month.year, month.month, 1);
    DateTime monthEnd = DateTime(month.year, month.month + 1, 0);

    final startStr = DateFormat('yyyy-MM-dd').format(monthStart);
    final endStr = DateFormat('yyyy-MM-dd').format(monthEnd);

    final dateStatuses = await _attendanceDao.getMonthlyAttendanceStatus(
      startStr,
      endStr,
      sem,
    );

    Map<DateTime, String> newStatuses = {};
    DateTime today = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    for (int i = 1; i <= monthEnd.day; i++) {
      DateTime day = DateTime.utc(month.year, month.month, i);

      bool isHoliday =
          day.weekday == DateTime.sunday ||
          day.isBefore(_firstDay) ||
          day.isAfter(_lastDay) ||
          (_lecturesPerDay[day.weekday] ?? 0) == 0;

      if (isHoliday) {
        newStatuses[day] = 'holiday';
      } else if (day.isAfter(today)) {
        newStatuses[day] = 'future';
      } else {
        // It's a past/present day with lectures. Let's check attendance.
        final dateKey = DateFormat('yyyy-MM-dd').format(day);
        final statuses = dateStatuses[dateKey] ?? [];

        if (statuses.isEmpty) {
          newStatuses[day] = 'forgot';
        } else if (statuses.every((s) => s == 'P')) {
          newStatuses[day] = 'all_p';
        } else if (statuses.every((s) => s == 'A')) {
          newStatuses[day] = 'all_a';
        } else {
          newStatuses[day] = 'mixed';
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _monthStatuses = newStatuses;
    });
  }

  Future<void> _loadForDate(DateTime date) async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;

    if (date.weekday == DateTime.sunday) {
      setState(() {
        _dayEntries = [];
        _attendanceSelection.clear();
        _loading = false;
      });
      return;
    }

    final entries = await _timetableDao.getEntriesForDay(date.weekday, sem);
    final subjects = await _subjectDao.getSubjectsBySemester(sem);

    _subjectMap = {for (final s in subjects) s.id!: s};

    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final savedAttendance = await _attendanceDao.getAttendanceForDate(dateKey);

    if (!mounted) return;

    setState(() {
      _dayEntries = entries;
      _attendanceSelection
        ..clear()
        ..addAll(savedAttendance);
      _loading = false;
    });
  }

  Future<void> _saveAttendance() async {
    if (_selectedDay == null) return;

    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);

    for (final entry in _dayEntries) {
      final timetableId = entry.id!;
      final status = _attendanceSelection[timetableId];

      if (status == null) {
        await _attendanceDao.deleteAttendance(timetableId, dateKey);
      } else {
        await _attendanceDao.upsertAttendance(
          timetableId: timetableId,
          date: dateKey,
          status: status,
        );
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attendance updated')));

    // ✅ REFRESH CALENDAR COLORS INSTANTLY
    await _fetchMonthData(_focusedDay);
  }

  Widget _attendanceButton(int timetableId, String value, String label) {
    final selected = _attendanceSelection[timetableId] == value;
    final color = value == 'P' ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Calendar',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: !_isCalendarReady
                ? const SizedBox(
                    height: 350,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  )
                : TableCalendar(
                    firstDay: _firstDay,
                    lastDay: _lastDay,
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: CalendarFormat.month,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Month',
                    },
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),

                    // ✅ CUSTOM HEATMAP UI OVERRIDE
                    calendarBuilders: CalendarBuilders(
                      prioritizedBuilder: (context, day, focusedDay) {
                        final normalizedDay = DateTime.utc(
                          day.year,
                          day.month,
                          day.day,
                        );
                        bool isSelected = isSameDay(_selectedDay, day);
                        bool isToday = isSameDay(DateTime.now(), day);

                        // 1. Solid Blue for Selected Day
                        if (isSelected) {
                          return Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }

                        // 2. Heatmap Colors
                        final status = _monthStatuses[normalizedDay];
                        Color? bgColor;
                        Color textColor = Colors.black;
                        FontWeight weight = isToday
                            ? FontWeight.bold
                            : FontWeight.normal;

                        if (status == 'holiday') {
                          bgColor = Colors.grey.withOpacity(0.15);
                          textColor = Colors.grey.shade600;
                        } else if (status == 'all_p') {
                          bgColor = Colors.green.withOpacity(0.25);
                        } else if (status == 'all_a') {
                          bgColor = Colors.red.withOpacity(0.25);
                        } else if (status == 'mixed') {
                          bgColor = Colors.orange.withOpacity(0.25);
                        } else if (status == 'forgot') {
                          bgColor = const Color(0xFFFEF3C7); // Light Amber
                        }

                        // Outline today if not selected
                        Border? border = isToday
                            ? Border.all(
                                color: const Color(0xFF2563EB),
                                width: 1.5,
                              )
                            : null;

                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: bgColor,
                            shape: BoxShape.circle,
                            border: border,
                          ),
                          child: Center(
                            child: status == 'forgot'
                                ? const Icon(
                                    Icons.question_mark_rounded,
                                    size: 16,
                                    color: Color(0xFFD97706),
                                  ) // Amber Question Mark
                                : Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: weight,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      if (!isSameDay(_selectedDay, selectedDay)) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        _loadForDate(selectedDay);
                      }
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                      _fetchMonthData(focusedDay); // Fetch colors for new month
                    },
                  ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _selectedDay != null
                  ? DateFormat('EEEE, MMM d').format(_selectedDay!)
                  : '',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  )
                : _dayEntries.isEmpty
                ? const Center(
                    child: Text(
                      'No lectures for this day',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _dayEntries.length,
                    itemBuilder: (_, i) {
                      final entry = _dayEntries[i];
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
                                    fontSize: 16,
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

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
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
                  'Save Changes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
