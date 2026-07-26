import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/glass_nav_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass_action_button.dart';
import '../../widgets/app_overlays.dart';
import '../root/tab_page_state.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends TabPageState<CalendarScreen> {
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

    // Try the semester-specific keys first, then fall back to generic keys
    String? startStr = prefs.getString('semester_start_$_activeSemester');
    String? endStr = prefs.getString('semester_end_$_activeSemester');

    // Fallback: try without semester suffix (older data format)
    startStr ??= prefs.getString('semester_start');
    endStr ??= prefs.getString('semester_end');

    DateTime normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

    DateTime parsedStart = DateTime.now();
    DateTime parsedEnd = DateTime.now().add(const Duration(days: 180));

    if (startStr != null && startStr.isNotEmpty) {
      try {
        parsedStart = DateTime.parse(startStr);
      } catch (_) {
        debugPrint('Calendar: Failed to parse semester start: $startStr');
      }
    }
    if (endStr != null && endStr.isNotEmpty) {
      try {
        parsedEnd = DateTime.parse(endStr);
      } catch (_) {
        debugPrint('Calendar: Failed to parse semester end: $endStr');
        parsedEnd = parsedStart.add(const Duration(days: 180));
      }
    } else {
      parsedEnd = parsedStart.add(const Duration(days: 180));
    }

    // Ensure end is after start
    if (parsedEnd.isBefore(parsedStart)) {
      parsedEnd = parsedStart.add(const Duration(days: 180));
    }

    // Always allow navigation up to today, even if PDF end date is in the past
    final now = DateTime.now();
    if (parsedEnd.isBefore(now)) parsedEnd = now;

    DateTime initialFocus = now;
    if (now.isBefore(parsedStart)) initialFocus = parsedStart;

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
    final today = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

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
        } else if (statuses.every((s) => s == 'NU')) {
          newStatuses[day] = 'all_nu';
        } else {
          // Filter out NU to determine P/A status
          final paStatuses = statuses.where((s) => s != 'NU').toList();
          if (paStatuses.isEmpty) {
            newStatuses[day] = 'all_nu';
          } else if (paStatuses.every((s) => s == 'P')) {
            newStatuses[day] = 'all_p';
          } else if (paStatuses.every((s) => s == 'A')) {
            newStatuses[day] = 'all_a';
          } else {
            newStatuses[day] = 'mixed';
          }
        }
      }
    }

    if (!mounted) return;
    setState(() => _monthStatuses = newStatuses);
  }

  /// Re-reads the month heatmap and, if a day is open, that day's schedule.
  ///
  /// Deliberately not `_initCalendarDates`: the semester bounds and the day the
  /// user has scrolled to are view state, not data, and re-deriving them would
  /// throw you back to today every time you crossed the nav bar.
  @override
  Future<void> reloadData() async {
    await _fetchMonthData(_focusedDay);
    final DateTime? selected = _selectedDay;
    if (selected != null && mounted) await _loadForDate(selected);
  }

  /// Loads the full day schedule: every lecture the weekly timetable expects
  /// for this weekday, merged with the stored records. Slots with no record yet
  /// appear as virtual "Not Updated" rows, so each weekday shows a consistent
  /// lecture count instead of only the ones that happen to be recorded.
  Future<void> _loadForDate(DateTime date) async {
    setState(() => _loading = true);

    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    final records = await _attendanceDao.getDaySchedule(
      dateKey,
      _activeSemester,
    );

    if (!mounted) return;
    setState(() {
      _dayRecords = records;
      _loading = false;
    });
  }

  Future<void> _saveRecord(
    int timetableEntryId,
    String date,
    String status, {
    String source = 'manual',
    String? originalStatus,
  }) async {
    await _attendanceDao.upsertAttendance(
      timetableId: timetableEntryId,
      date: date,
      status: status,
      source: source,
      originalStatus: originalStatus,
    );
    await _fetchMonthData(_focusedDay);
    CloudSyncService().backupDataToCloud();
  }

  /// Reverts a record back to "Not Updated". Only valid for records whose PDF
  /// baseline was NU — a real Present/Absent from the report cannot be reverted
  /// to NU (the report never left it blank). If the record was a virtual slot
  /// (never persisted), there is nothing to remove.
  Future<void> _revertToNotUpdated(
    int timetableEntryId,
    String date,
    int? recordId,
  ) async {
    if (recordId == null) return; // virtual slot; nothing stored
    await _saveRecord(
      timetableEntryId,
      date,
      'NU',
      source: 'pdf',
      originalStatus: 'NU',
    );
    await _loadForDate(_selectedDay!);
  }

  Future<void> _deleteRecord(int timetableEntryId, String date) async {
    await _attendanceDao.deleteAttendance(timetableEntryId, date);
    if (_selectedDay != null) await _loadForDate(_selectedDay!);
    await _fetchMonthData(_focusedDay);
    CloudSyncService().backupDataToCloud();
  }

  /// Pull-to-refresh: bidirectional cloud sync then reinitialize calendar
  Future<void> _syncAndReload() async {
    await CloudSyncService().syncBidirectional();
    await _initCalendarDates();
  }

  // Opens bottom sheet to add a new attendance record for the selected date
  void _showAddRecordSheet(String? dateKey) {
    if (dateKey == null) return;

    // All subjects are always available — multiple lectures on the same day are allowed
    final available = List<Subject>.from(_allSubjects);

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No subjects found. Please add subjects first.'),
        ),
      );
      return;
    }

    Subject? selectedSubject;
    String selectedStatus = 'P';

    showAppModalSheet(
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                  initialValue: selectedSubject,
                  decoration: InputDecoration(
                    labelText: 'Select Subject',
                    labelStyle: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  dropdownColor: theme.cardColor,
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  items: available
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.name)),
                      )
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
                        color: context.appColors.success,
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
                        color: context.appColors.danger,
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
                            final seedId = await _timetableDao.ensureSeedEntry(
                              sub.id!,
                            );

                            // Find a free date key for this subject. _dayRecords
                            // now includes virtual timetable slots, so pick the
                            // first key not already taken by a REAL record — this
                            // fills an empty timetable slot before creating an
                            // extra one beyond the schedule.
                            final usedKeys = _dayRecords
                                .where(
                                  (r) =>
                                      r['subject_id'] == sub.id &&
                                      r['record_id'] != null,
                                )
                                .map((r) => r['record_date'] as String)
                                .toSet();
                            var idx = 0;
                            String candidate() =>
                                idx == 0 ? dateKey : '${dateKey}_${idx + 1}';
                            while (usedKeys.contains(candidate())) {
                              idx++;
                            }
                            final uniqueDateKey = candidate();

                            await _saveRecord(
                              seedId,
                              uniqueDateKey,
                              selectedStatus,
                              originalStatus: selectedStatus,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadForDate(_selectedDay!);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: theme.dividerColor,
                    ),
                    child: const Text(
                      'Save Record',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
            Icon(
              icon,
              color: selected ? color : theme.iconTheme.color,
              size: 20,
            ),
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
    final today = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final isFutureDay = _selectedDay != null && _selectedDay!.isAfter(today);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = context.appColors;

    final colorPresentBg = c.success.withAlpha(64);
    final colorAbsentBg = c.danger.withAlpha(64);
    final colorMixedBg = c.warning.withAlpha(64);
    final colorHolidayBg = isDark
        ? Colors.white.withAlpha(25)
        : Colors.grey.withAlpha(38);

    // Date key for selected day
    final selectedDateKey = _selectedDay != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDay!)
        : null;
    final isSunday = _selectedDay?.weekday == DateTime.sunday;
    final canAddRecord = !isFutureDay && !isSunday && selectedDateKey != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Calendar'), elevation: 0),
      // The pill appears and disappears as the selection moves between valid
      // days, and Scaffold's default animator scale-rotates it in every time.
      // That made day-tapping feel like it was launching something rather than
      // just selecting; the pill now cuts straight in and out.
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      floatingActionButton: canAddRecord
          // The shell Scaffold sets extendBody, so this inner Scaffold's
          // bottom edge is the screen edge and endFloat drops the FAB right
          // under the floating glass bar. Scaffold's own clearance is
          // max(16, viewPadding.bottom) — the system gesture inset only; it
          // knows nothing about a bar belonging to a Scaffold above it. The
          // record list already makes this correction for its last row.
          //
          // This double-counts the gesture inset, since Scaffold's margin
          // covered that part already. Left as-is: the overlap is the gap
          // between the FAB and the bar, and a floating control wants one.
          ? Padding(
              padding: EdgeInsets.only(
                // endFloat already lifts the pill by max(16, viewPadding) for
                // the system gesture inset, then this clears the nav bar on
                // top of that — so the two stacked into a wide gap. Subtracting
                // the margin back out leaves exactly GlassNavTheme.actionGap
                // of air between the pill and the bar's glass.
                bottom:
                    (MediaQuery.paddingOf(context).bottom -
                            math.max(
                              kFloatingActionButtonMargin,
                              MediaQuery.viewPaddingOf(context).bottom,
                            ) -
                            GlassNavTheme.verticalInset +
                            GlassNavTheme.actionGap)
                        .clamp(0.0, double.infinity),
                // Scaffold's endFloat sits the pill 16 from the screen edge;
                // the bar is inset 32. Making up the difference is what puts
                // the two on a shared right edge, which is most of why the
                // pill reads as part of the bar rather than next to it.
                right: GlassNavTheme.actionInset - kFloatingActionButtonMargin,
              ),
              child: GlassActionButton(
                icon: Icons.add_rounded,
                label: 'Add record',
                onPressed: () => _showAddRecordSheet(selectedDateKey),
              ),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: RefreshIndicator(
            onRefresh: _syncAndReload,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Calendar widget
                Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
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
                                  final bool isSelected = isSameDay(
                                    _selectedDay,
                                    day,
                                  );
                                  final bool isToday = isSameDay(
                                    DateTime.now(),
                                    day,
                                  );

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
                                  final FontWeight weight = isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal;

                                  switch (status) {
                                    case 'outside':
                                      bgColor = Colors.transparent;
                                      textColor = isDark
                                          ? Colors.white.withAlpha(50)
                                          : Colors.black.withAlpha(50);
                                    case 'holiday':
                                      bgColor = colorHolidayBg;
                                      textColor =
                                          theme.textTheme.bodyMedium?.color ??
                                          Colors.grey;
                                    case 'all_p':
                                      bgColor = colorPresentBg;
                                    case 'all_a':
                                      bgColor = colorAbsentBg;
                                    case 'mixed':
                                      bgColor = colorMixedBg;
                                    case 'all_nu':
                                      bgColor = c.warning.withAlpha(
                                        isDark ? 80 : 60,
                                      );
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
                                              color: theme.colorScheme.primary,
                                              width: 1.5,
                                            )
                                          : null,
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

                      // Legend
                      if (_isCalendarReady)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Row(
                            children: [
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
                              Expanded(
                                child: _buildLegendItem(
                                  colorMixedBg,
                                  'Mixed',
                                  theme,
                                ),
                              ),
                              Expanded(
                                child: _buildLegendItem(
                                  colorHolidayBg,
                                  'Off',
                                  theme,
                                ),
                              ),
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
                  child: AnimatedSwitcher(
                    duration: AppMotion.standard,
                    switchInCurve: AppMotion.enter,
                    switchOutCurve: AppMotion.exit,
                    child: _loading
                        ? Center(
                            key: const ValueKey('loading'),
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : isSunday
                        ? EmptyState(
                            key: const ValueKey('sunday'),
                            icon: Icons.weekend_rounded,
                            message: 'Sunday — no classes',
                            compact: true,
                          )
                        : isFutureDay
                        ? EmptyState(
                            key: const ValueKey('future'),
                            icon: Icons.event_outlined,
                            message: 'No records yet',
                            compact: true,
                          )
                        : _dayRecords.isEmpty
                        ? EmptyState(
                            key: const ValueKey('empty'),
                            icon: Icons.event_note_outlined,
                            message:
                                'No records for this date\nTap + to add one',
                            compact: true,
                          )
                        : ListView.builder(
                            key: ValueKey(_selectedDay),
                            padding: EdgeInsets.fromLTRB(
                              AppDimens.space16,
                              AppDimens.space4,
                              AppDimens.space16,
                              // Was a flat 100 for the FAB; the floating
                              // glass nav bar now sits under here too.
                              100 + MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: _dayRecords.length,
                            itemBuilder: (_, i) {
                              final record = _dayRecords[i];
                              final recordId = record['record_id'] as int?;
                              final subjectName =
                                  record['subject_name'] as String? ??
                                  'Unknown';
                              final status = record['status'] as String? ?? '';
                              final timetableId =
                                  record['timetable_entry_id'] as int?;
                              final recordDate =
                                  record['record_date'] as String? ??
                                  selectedDateKey!;

                              var lectureNum = 1;
                              for (var j = 0; j < i; j++) {
                                if (_dayRecords[j]['subject_name'] ==
                                    subjectName) {
                                  lectureNum++;
                                }
                              }
                              final hasDuplicates =
                                  _dayRecords
                                      .where(
                                        (r) => r['subject_name'] == subjectName,
                                      )
                                      .length >
                                  1;

                              final isPresent = status == 'P';
                              final isNU = status == 'NU';
                              final isVirtual =
                                  record['is_virtual'] == 1 || recordId == null;
                              final originalStatus =
                                  record['original_status'] as String?;
                              // "Manual" = the current value differs from the PDF baseline.
                              final isManual =
                                  !isVirtual &&
                                  originalStatus != null &&
                                  status != originalStatus;
                              // Can revert to NU only when the PDF itself reported NU here.
                              final canRevertToNu =
                                  !isVirtual && originalStatus == 'NU' && !isNU;
                              final c = context.appColors;
                              final statusColor = isNU
                                  ? c.warning
                                  : isPresent
                                  ? c.success
                                  : c.danger;

                              return TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: Duration(
                                  milliseconds: 260 + (i * 40).clamp(0, 220),
                                ),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) => Opacity(
                                  opacity: value.clamp(0.0, 1.0),
                                  child: child,
                                ),
                                child: Card(
                                  key: ValueKey(recordId ?? 'rec_$i'),
                                  color: theme.cardColor,
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: statusColor.withAlpha(80),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
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
                                                  color: theme
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.color,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isNU
                                                    ? (hasDuplicates
                                                          ? 'Not Updated - Lecture $lectureNum'
                                                          : 'Not Updated - tap to set status')
                                                    : (hasDuplicates
                                                          ? '${isPresent ? 'Present' : 'Absent'} - Lecture $lectureNum'
                                                          : (isPresent
                                                                ? 'Present'
                                                                : 'Absent')),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: statusColor,
                                                ),
                                              ),
                                              if (isManual && !isNU)
                                                Text(
                                                  'Manual',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color
                                                        ?.withAlpha(160),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (timetableId != null) ...[
                                          if (isNU) ...[
                                            _inlineToggle(
                                              label: 'P',
                                              selected: false,
                                              color: c.success,
                                              theme: theme,
                                              onTap: () async {
                                                // Preserve NU baseline so this can be reverted later.
                                                await _saveRecord(
                                                  timetableId,
                                                  recordDate,
                                                  'P',
                                                  originalStatus:
                                                      originalStatus ?? 'NU',
                                                );
                                                await _loadForDate(
                                                  _selectedDay!,
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            _inlineToggle(
                                              label: 'A',
                                              selected: false,
                                              color: c.danger,
                                              theme: theme,
                                              onTap: () async {
                                                await _saveRecord(
                                                  timetableId,
                                                  recordDate,
                                                  'A',
                                                  originalStatus:
                                                      originalStatus ?? 'NU',
                                                );
                                                await _loadForDate(
                                                  _selectedDay!,
                                                );
                                              },
                                            ),
                                          ] else ...[
                                            _inlineToggle(
                                              label: isPresent
                                                  ? 'Present'
                                                  : 'Absent',
                                              selected: true,
                                              color: isPresent
                                                  ? c.success
                                                  : c.danger,
                                              theme: theme,
                                              onTap: () async {
                                                await _saveRecord(
                                                  timetableId,
                                                  recordDate,
                                                  isPresent ? 'A' : 'P',
                                                );
                                                await _loadForDate(
                                                  _selectedDay!,
                                                );
                                              },
                                            ),
                                            // Only offer revert-to-NU when the PDF itself reported NU.
                                            if (canRevertToNu) ...[
                                              const SizedBox(width: 4),
                                              _inlineToggle(
                                                label: 'NU',
                                                selected: false,
                                                color: c.warning,
                                                theme: theme,
                                                onTap: () =>
                                                    _revertToNotUpdated(
                                                      timetableId,
                                                      recordDate,
                                                      recordId,
                                                    ),
                                              ),
                                            ],
                                          ],
                                          const SizedBox(width: 6),
                                          // Virtual (timetable-filled) rows have nothing stored to
                                          // delete — they reappear from the timetable anyway.
                                          if (!isVirtual)
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color,
                                              ),
                                              onPressed: () => _deleteRecord(
                                                timetableId,
                                                recordDate,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
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
}
