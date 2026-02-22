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

  // HEATMAP DATA VARIABLES
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
        selectedColor: color.withAlpha(38),
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

  Widget _buildLegendItem(Color color, String label, {Widget? icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, // Slightly smaller circles to save space
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: icon),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    bool isFutureDay = _selectedDay != null && _selectedDay!.isAfter(today);

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
            child: Column(
              children: [
                !_isCalendarReady
                    // ✅ COMPACT LOADING SPINNER SPACE
                    ? const SizedBox(
                        height: 270,
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
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        calendarFormat: CalendarFormat.month,
                        availableCalendarFormats: const {
                          CalendarFormat.month: 'Month',
                        },

                        // ✅ MASSIVE SPACE SAVER: Forces the calendar to be much shorter vertically
                        rowHeight: 42,
                        daysOfWeekHeight: 20,

                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          headerPadding: EdgeInsets.symmetric(
                            vertical: 4,
                          ), // Tighter header
                        ),
                        calendarBuilders: CalendarBuilders(
                          prioritizedBuilder: (context, day, focusedDay) {
                            final normalizedDay = DateTime.utc(
                              day.year,
                              day.month,
                              day.day,
                            );
                            bool isSelected = isSameDay(_selectedDay, day);
                            bool isToday = isSameDay(DateTime.now(), day);

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

                            final status = _monthStatuses[normalizedDay];
                            Color? bgColor;
                            Color textColor = Colors.black;
                            FontWeight weight = isToday
                                ? FontWeight.bold
                                : FontWeight.normal;

                            if (status == 'holiday') {
                              bgColor = Colors.grey.withAlpha(38);
                              textColor = Colors.grey.shade600;
                            } else if (status == 'all_p') {
                              bgColor = Colors.green.withAlpha(64);
                            } else if (status == 'all_a') {
                              bgColor = Colors.red.withAlpha(64);
                            } else if (status == 'mixed') {
                              bgColor = Colors.orange.withAlpha(64);
                            } else if (status == 'forgot') {
                              bgColor = const Color(0xFFF3E8FF);
                            }

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
                                child: Text(
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
                          _fetchMonthData(focusedDay);
                        },
                      ),

                if (_isCalendarReady)
                  Padding(
                    // ✅ COMPACT LEGEND PADDING
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFF2563EB),
                                'Selected',
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                Colors.green.withAlpha(64),
                                'All Present',
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                Colors.red.withAlpha(64),
                                'All Absent',
                              ),
                            ),
                          ],
                        ),
                        // ✅ TIGHTER VERTICAL SPACING IN LEGEND
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                Colors.orange.withAlpha(64),
                                'Mixed',
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFFF3E8FF),
                                'Forgot / Not Held',
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                Colors.grey.withAlpha(38),
                                'Holiday / Off',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ✅ REDUCED SPACING BELOW CALENDAR
          const SizedBox(height: 12),

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

          const SizedBox(height: 8),

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
                        // ✅ TIGHTER CARD MARGINS TO FIT MORE LECTURES
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          // ✅ TIGHTER INTERNAL PADDING FOR LECTURE ROWS
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
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
                              if (isFutureDay)
                                const Text(
                                  'Upcoming',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              else ...[
                                _attendanceButton(entry.id!, 'P', 'Present'),
                                _attendanceButton(entry.id!, 'A', 'Absent'),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (!isFutureDay && _dayEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveAttendance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    // ✅ SLIGHTLY SLIMMER SAVE BUTTON
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
            )
          else if (isFutureDay && _dayEntries.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
              child: Center(
                child: Text(
                  'Cannot mark attendance for future dates',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
