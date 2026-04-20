import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../services/notification_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final AttendanceDao _attendanceDao = AttendanceDao();
  final SubjectDao _subjectDao = SubjectDao();
  final TimetableDao _timetableDao = TimetableDao();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime _firstDay = DateTime.now().subtract(const Duration(days: 365));
  DateTime _lastDay = DateTime.now().add(const Duration(days: 365));

  bool _loading = true;
  bool _isCalendarReady = false;

  // Heatmap: normalized UTC date -> status string
  Map<DateTime, String> _monthStatuses = {};

  // Records for the selected date: subjectId, subjectName, timetableEntryId, status
  List<Map<String, dynamic>> _dayRecords = [];

  // All subjects for the semester (used in the add-record sheet)
  List<Subject> _allSubjects = [];

  int _activeSemester = 1;

  @override
  void initState() {
    super.initState();
    _initCalendarDates();
  }

  Future<void> _initCalendarDates() async {
    final prefs = await SharedPreferences.getInstance();
    _activeSemester = prefs.getInt('semester') ?? 1;

    final startStr = prefs.getString('semester_start_$_activeSemester');
    final endStr = prefs.getString('semester_end_$_activeSemester');

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
    if (now.isBefore(parsedStart)) initialFocus = parsedStart;
    if (now.isAfter(parsedEnd)) initialFocus = parsedEnd;

    // Load all subjects once for the add-record sheet
    final subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
    // Ensure seed slots exist for all subjects
    for (final sub in subjects) {
      await _timetableDao.ensureSeedEntry(sub.id!);
    }

    if (!mounted) return;
    setState(() {
      _firstDay = normalize(parsedStart);
      _lastDay = normalize(parsedEnd);
      _focusedDay = normalize(initialFocus);
      _selectedDay = normalize(initialFocus);
      _allSubjects = subjects;
      _isCalendarReady = true;
    });

    await _fetchMonthData(_focusedDay);
    await _loadForDate(_selectedDay!);
  }

  Future<void> _fetchMonthData(DateTime month) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);

    final startStr = DateFormat('yyyy-MM-dd').format(monthStart);
    final endStr = DateFormat('yyyy-MM-dd').format(monthEnd);

    final dateStatuses = await _attendanceDao.getMonthlyAttendanceStatus(
      startStr,
      endStr,
      _activeSemester,
    );

    final Map<DateTime, String> newStatuses = {};
    final today = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    for (int i = 1; i <= monthEnd.day; i++) {
      final day = DateTime.utc(month.year, month.month, i);

      if (day.isBefore(_firstDay) || day.isAfter(_lastDay)) {
        newStatuses[day] = 'outside';
      } else if (day.weekday == DateTime.sunday) {
        newStatuses[day] = 'holiday';
      } else if (day.isAfter(today)) {
        newStatuses[day] = 'future';
      } else {
        final dateKey = DateFormat('yyyy-MM-dd').format(day);
        final statuses = dateStatuses[dateKey] ?? [];

        if (statuses.isEmpty) {
          newStatuses[day] = 'no_record';
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
    setState(() => _monthStatuses = newStatuses);
  }

  /// Loads only subjects with actual records on this date (INNER JOIN).
  Future<void> _loadForDate(DateTime date) async {
    setState(() => _loading = true);

    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    final records = await _attendanceDao.getAttendanceForDateBySeedSlot(
      dateKey,
      _activeSemester,
    );

    if (!mounted) return;
    setState(() {
      _dayRecords = records;
      _loading = false;
    });
  }

  Future<void> _saveRecord(int timetableEntryId, String date, String status) async {
    await _attendanceDao.upsertAttendance(
      timetableId: timetableEntryId,
      date: date,
      status: status,
    );
    await _fetchMonthData(_focusedDay);
    await NotificationService().scheduleSmartNotifications();
  }

  Future<void> _deleteRecord(int timetableEntryId, String date) async {
    await _attendanceDao.deleteAttendance(timetableEntryId, date);
    if (_selectedDay != null) await _loadForDate(_selectedDay!);
    await _fetchMonthData(_focusedDay);
    await NotificationService().scheduleSmartNotifications();
  }

  // Opens bottom sheet to add a new attendance record for the selected date
  void _showAddRecordSheet(String? dateKey) {
    if (dateKey == null) return;
    // Subjects that don't already have a record for this date
    final recordedSubjectIds = _dayRecords
        .map((r) => r['subject_id'] as int)
        .toSet();
    final available = _allSubjects
        .where((s) => !recordedSubjectIds.contains(s.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All subjects already have a record for this date')),
      );
      return;
    }

    Subject? selectedSubject;
    String selectedStatus = 'P';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = Theme.of(context);
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  'Add Record — $dateKey',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 20),

                // Subject picker
                DropdownButtonFormField<Subject>(
                  value: selectedSubject,
                  decoration: InputDecoration(
                    labelText: 'Select Subject',
                    labelStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                  dropdownColor: theme.cardColor,
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  items: available
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedSubject = v),
                ),

                const SizedBox(height: 20),

                // Status selector
                Text(
                  'Attendance Status',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _statusToggleButton(
                        label: 'Present',
                        icon: Icons.check_circle_outline_rounded,
                        value: 'P',
                        selected: selectedStatus == 'P',
                        color: Colors.green,
                        theme: theme,
                        onTap: () => setSheetState(() => selectedStatus = 'P'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statusToggleButton(
                        label: 'Absent',
                        icon: Icons.cancel_outlined,
                        value: 'A',
                        selected: selectedStatus == 'A',
                        color: Colors.red,
                        theme: theme,
                        onTap: () => setSheetState(() => selectedStatus = 'A'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedSubject == null
                        ? null
                        : () async {
                            final sub = selectedSubject!;
                            final seedId = await _timetableDao.ensureSeedEntry(sub.id!);
                            await _saveRecord(seedId, dateKey, selectedStatus);
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            await _loadForDate(_selectedDay!);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: theme.dividerColor,
                    ),
                    child: const Text(
                      'Save Record',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Status toggle button used inside the add-record sheet
  Widget _statusToggleButton({
    required String label,
    required IconData icon,
    required String value,
    required bool selected,
    required Color color,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(38) : theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : theme.iconTheme.color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? color : theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
    final today = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final isFutureDay = _selectedDay != null && _selectedDay!.isAfter(today);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colorPresentBg = Colors.green.withAlpha(64);
    final colorAbsentBg = Colors.red.withAlpha(64);
    final colorMixedBg = Colors.orange.withAlpha(64);
    final colorHolidayBg = isDark ? Colors.white.withAlpha(25) : Colors.grey.withAlpha(38);

    // Date key for selected day
    final selectedDateKey = _selectedDay != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDay!)
        : null;
    final isSunday = _selectedDay?.weekday == DateTime.sunday;
    final canAddRecord = !isFutureDay && !isSunday && selectedDateKey != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Calendar'), elevation: 0),
      floatingActionButton: canAddRecord
          ? FloatingActionButton.extended(
              onPressed: () => _showAddRecordSheet(selectedDateKey),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Record', style: TextStyle(fontWeight: FontWeight.w600)),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar widget
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              children: [
                !_isCalendarReady
                    ? const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : TableCalendar(
                        firstDay: _firstDay,
                        lastDay: _lastDay,
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                        calendarFormat: CalendarFormat.month,
                        availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                        rowHeight: 42,
                        daysOfWeekHeight: 20,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          headerPadding: const EdgeInsets.symmetric(vertical: 4),
                          titleTextStyle: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 17,
                          ),
                          leftChevronIcon:
                              Icon(Icons.chevron_left, color: theme.iconTheme.color),
                          rightChevronIcon:
                              Icon(Icons.chevron_right, color: theme.iconTheme.color),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle:
                              TextStyle(color: theme.textTheme.bodyMedium?.color),
                          weekendStyle:
                              TextStyle(color: theme.textTheme.bodyMedium?.color),
                        ),
                        calendarBuilders: CalendarBuilders(
                          prioritizedBuilder: (context, day, focusedDay) {
                            final normalizedDay =
                                DateTime.utc(day.year, day.month, day.day);
                            final bool isSelected = isSameDay(_selectedDay, day);
                            final bool isToday = isSameDay(DateTime.now(), day);

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
                                theme.textTheme.bodyLarge?.color ?? Colors.black;
                            final FontWeight weight =
                                isToday ? FontWeight.bold : FontWeight.normal;

                            switch (status) {
                              case 'outside':
                                bgColor = Colors.transparent;
                                textColor = isDark
                                    ? Colors.white.withAlpha(50)
                                    : Colors.black.withAlpha(50);
                              case 'holiday':
                                bgColor = colorHolidayBg;
                                textColor = theme.textTheme.bodyMedium?.color ?? Colors.grey;
                              case 'all_p':
                                bgColor = colorPresentBg;
                              case 'all_a':
                                bgColor = colorAbsentBg;
                              case 'mixed':
                                bgColor = colorMixedBg;
                              default:
                                bgColor = null;
                            }

                            return Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: bgColor,
                                shape: BoxShape.circle,
                                border: isToday
                                    ? Border.all(
                                        color: theme.colorScheme.primary, width: 1.5)
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                      color: textColor, fontWeight: weight),
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

                // Legend
                if (_isCalendarReady)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(child: _buildLegendItem(colorPresentBg, 'All Present', theme)),
                        Expanded(child: _buildLegendItem(colorAbsentBg, 'All Absent', theme)),
                        Expanded(child: _buildLegendItem(colorMixedBg, 'Mixed', theme)),
                        Expanded(child: _buildLegendItem(colorHolidayBg, 'Off', theme)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Selected day label
          if (_selectedDay != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay!),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),

          // Records list
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : isSunday
                    ? _emptyState(Icons.weekend_rounded, 'Sunday — no classes', theme)
                    : isFutureDay
                        ? _emptyState(Icons.event_outlined, 'No records yet', theme)
                        : _dayRecords.isEmpty
                            ? _emptyState(
                                Icons.event_note_outlined,
                                'No records for this date\nTap + to add one',
                                theme,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                                itemCount: _dayRecords.length,
                                itemBuilder: (_, i) {
                                  final record = _dayRecords[i];

                                  final recordId = record['record_id'] as int?;
                                  final subjectName =
                                      record['subject_name'] as String? ?? 'Unknown';
                                  final status = record['status'] as String? ?? '';
                                  final timetableId =
                                      record['timetable_entry_id'] as int?;
                                  final recordDate = 
                                      record['record_date'] as String? ?? selectedDateKey!;

                                  // Determine lecture index for duplicate subjects
                                  int lectureNum = 1;
                                  for (int j = 0; j < i; j++) {
                                    if (_dayRecords[j]['subject_name'] == subjectName) {
                                      lectureNum++;
                                    }
                                  }
                                  final bool hasDuplicates = _dayRecords
                                      .where((r) => r['subject_name'] == subjectName)
                                      .length > 1;

                                  final isPresent = status == 'P';
                                  final statusColor =
                                      isPresent ? Colors.green : Colors.red;

                                  return Card(
                                    key: ValueKey(recordId ?? 'rec_$i'),
                                    color: theme.cardColor,
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: statusColor.withAlpha(80),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          // Status dot
                                          Container(
                                            width: 10,
                                            height: 10,
                                            margin: const EdgeInsets.only(right: 12),
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          // Subject name
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  subjectName,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.textTheme.bodyLarge?.color,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  hasDuplicates
                                                      ? '${isPresent ? 'Present' : 'Absent'} · Lecture $lectureNum'
                                                      : (isPresent ? 'Present' : 'Absent'),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Toggle P/A
                                          if (timetableId != null) ...[
                                            _inlineToggle(
                                              label: isPresent ? 'Present' : 'Absent',
                                              selected: true,
                                              color: isPresent ? Colors.green : Colors.red,
                                              theme: theme,
                                              onTap: () async {
                                                final newStatus =
                                                    isPresent ? 'A' : 'P';
                                                await _saveRecord(timetableId,
                                                    recordDate, newStatus);
                                                await _loadForDate(_selectedDay!);
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            // Delete
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: theme.textTheme.bodyMedium?.color,
                                              ),
                                              onPressed: () async {
                                                await _deleteRecord(
                                                  timetableId,
                                                  recordDate,
                                                );
                                              },
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _inlineToggle({
    required String label,
    required bool selected,
    required Color color,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(38) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : theme.dividerColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? color : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.textTheme.bodyMedium?.color?.withAlpha(100)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
