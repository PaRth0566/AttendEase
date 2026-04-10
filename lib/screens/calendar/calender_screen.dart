import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';
import '../../services/notification_service.dart';

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

    if (now.isBefore(parsedStart)) {
      initialFocus = parsedStart;
    } else if (now.isAfter(parsedEnd)) {
      initialFocus = parsedEnd;
    }

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

      // ✅ FIX: Separate "Outside" dates from "Holiday" dates
      if (day.isBefore(_firstDay) || day.isAfter(_lastDay)) {
        newStatuses[day] = 'outside';
      } else if (day.weekday == DateTime.sunday ||
          (_lecturesPerDay[day.weekday] ?? 0) == 0) {
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

    await NotificationService().scheduleSmartNotifications();
  }

  Widget _attendanceButton(
    int timetableId,
    String value,
    String label,
    ThemeData theme,
  ) {
    final selected = _attendanceSelection[timetableId] == value;
    final baseColor = value == 'P' ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: baseColor.withAlpha(38),
        backgroundColor: theme.scaffoldBackgroundColor,
        labelStyle: TextStyle(
          color: selected ? baseColor : theme.textTheme.bodyLarge?.color,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(
          color: selected ? Colors.transparent : theme.dividerColor,
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

  Widget _buildLegendItem(
    Color color,
    String label,
    ThemeData theme, {
    Widget? icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: icon),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodyMedium?.color,
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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colorPresentBg = Colors.green.withAlpha(64);
    final colorAbsentBg = Colors.red.withAlpha(64);
    final colorMixedBg = Colors.orange.withAlpha(64);
    final colorForgotBg = isDark
        ? Colors.purple.withAlpha(64)
        : const Color(0xFFF3E8FF);
    final colorHolidayBg = isDark
        ? Colors.white.withAlpha(25)
        : Colors.grey.withAlpha(38);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Calendar'), elevation: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              children: [
                !_isCalendarReady
                    ? Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
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
                        rowHeight: 42,
                        daysOfWeekHeight: 20,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          headerPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          titleTextStyle: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 17,
                          ),
                          leftChevronIcon: Icon(
                            Icons.chevron_left,
                            color: theme.iconTheme.color,
                          ),
                          rightChevronIcon: Icon(
                            Icons.chevron_right,
                            color: theme.iconTheme.color,
                          ),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          weekendStyle: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
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
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
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
                            Color textColor =
                                theme.textTheme.bodyLarge?.color ??
                                Colors.black;
                            FontWeight weight = isToday
                                ? FontWeight.bold
                                : FontWeight.normal;

                            // ✅ FIX: No background bubble at all if outside semester dates
                            if (status == 'outside') {
                              bgColor = Colors.transparent;
                              textColor = isDark
                                  ? Colors.white.withAlpha(50)
                                  : Colors.black.withAlpha(
                                      50,
                                    ); // Highly faded text
                            } else if (status == 'holiday') {
                              bgColor = colorHolidayBg;
                              textColor =
                                  theme.textTheme.bodyMedium?.color ??
                                  Colors.grey.shade600;
                            } else if (status == 'all_p') {
                              bgColor = colorPresentBg;
                            } else if (status == 'all_a') {
                              bgColor = colorAbsentBg;
                            } else if (status == 'mixed') {
                              bgColor = colorMixedBg;
                            } else if (status == 'forgot') {
                              bgColor = colorForgotBg;
                            }

                            Border? border = isToday
                                ? Border.all(
                                    color: theme.colorScheme.primary,
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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                theme.colorScheme.primary,
                                'Selected',
                                theme,
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                colorPresentBg,
                                'All Present',
                                theme,
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                colorAbsentBg,
                                'All Absent',
                                theme,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                colorMixedBg,
                                'Mixed',
                                theme,
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                colorForgotBg,
                                'Forgot / Not Held',
                                theme,
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                colorHolidayBg,
                                'Holiday / Off',
                                theme,
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

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _selectedDay != null
                  ? DateFormat('EEEE, MMM d').format(_selectedDay!)
                  : '',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  )
                : _dayEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No lectures for this day',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _dayEntries.length,
                    itemBuilder: (_, i) {
                      final entry = _dayEntries[i];
                      final subject = _subjectMap[entry.subjectId]!;

                      return Card(
                        color: theme.cardColor,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subject.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyLarge?.color,
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
                                _attendanceButton(
                                  entry.id!,
                                  'P',
                                  'Present',
                                  theme,
                                ),
                                _attendanceButton(
                                  entry.id!,
                                  'A',
                                  'Absent',
                                  theme,
                                ),
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
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
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
