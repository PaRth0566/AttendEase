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

class CalendarScreenState extends TabPageState<CalendarScreen>
    with AutomaticKeepAliveClientMixin {
  // Kept alive so a tab slide composites this page instead of rebuilding it
  // mid-drag (§1.6).
  @override
  bool get wantKeepAlive => true;

  final AttendanceDao _attendanceDao = AttendanceDao();
  final SubjectDao _subjectDao = SubjectDao();
  final TimetableDao _timetableDao = TimetableDao();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime _firstDay = DateTime.now().subtract(const Duration(days: 365));
  DateTime _lastDay = DateTime.now().add(const Duration(days: 365));

  bool _loading = true;
  // Bumped on every load so the loading spinner gets a fresh AnimatedSwitcher
  // key each time. Without this, reloading the same date (refresh/sync) while
  // the previous spinner is still animating out puts two identical keys in the
  // switcher's transition Stack and crashes on duplicate keys.
  int _loadSeq = 0;
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

  /// Re-reads the active semester and its start/end bounds from prefs and
  /// updates [_firstDay] / [_lastDay] / [_activeSemester].
  ///
  /// Split out of [_initCalendarDates] so [reloadData] can pick up a start/end
  /// date the user edited in Profile without also resetting the focused month
  /// and selected day — those are the user's place in the calendar, not data.
  /// Returns true if anything changed.
  Future<bool> _loadSemesterBounds() async {
    final prefs = await SharedPreferences.getInstance();
    final int sem = prefs.getInt('semester') ?? 1;

    // Try the semester-specific keys first, then fall back to generic keys
    String? startStr = prefs.getString('semester_start_$sem');
    String? endStr = prefs.getString('semester_end_$sem');

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

    // Today is a floor, not a ceiling: a stale/past end date cannot lock the
    // calendar behind the current date, but a semester_end the user owns in
    // Profile is allowed to run into the future — nothing truncates it. That is
    // what lets the calendar reach tomorrow without re-importing the PDF.
    final now = DateTime.now();
    if (parsedEnd.isBefore(now)) parsedEnd = now;

    final DateTime newFirst = normalize(parsedStart);
    final DateTime newLast = normalize(parsedEnd);

    final bool changed = _activeSemester != sem ||
        _firstDay != newFirst ||
        _lastDay != newLast;
    if (!changed) return false;

    if (!mounted) return false;
    // Clamp focus/selection into the new range *in the same setState* that
    // narrows the bounds. The screen is a kept-alive tab, so on a semester
    // switch these still hold the previous semester's dates; committing the
    // tighter bounds first (and clamping in a later frame) would rebuild
    // TableCalendar with focusedDay outside [firstDay, lastDay], which its base
    // asserts — the calendar's "sometimes errors, sometimes breaks on tap" bug.
    DateTime clampDay(DateTime d) =>
        d.isBefore(newFirst) ? newFirst : (d.isAfter(newLast) ? newLast : d);

    setState(() {
      _activeSemester = sem;
      _firstDay = newFirst;
      _lastDay = newLast;
      _focusedDay = clampDay(_focusedDay);
      if (_selectedDay != null) _selectedDay = clampDay(_selectedDay!);
    });
    return true;
  }

  Future<void> _initCalendarDates() async {
    await _loadSemesterBounds();

    final now = DateTime.now();
    DateTime normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

    DateTime initialFocus = now;
    if (normalize(now).isBefore(_firstDay)) initialFocus = _firstDay;
    if (normalize(initialFocus).isAfter(_lastDay)) initialFocus = _lastDay;

    // Load all subjects once for the add-record sheet
    final subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
    // Ensure seed slots exist for all subjects
    for (final sub in subjects) {
      await _timetableDao.ensureSeedEntry(sub.id!);
    }

    if (!mounted) return;
    setState(() {
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
        } else if (statuses.every((s) => s == 'NU' || s == 'NC')) {
          newStatuses[day] = 'all_nu';
        } else {
          // Only conducted lectures determine the attendance heatmap state.
          final paStatuses = statuses
              .where((s) => s == 'P' || s == 'A')
              .toList();
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
    // Re-read bounds first so an end date the user just edited in Profile (or a
    // semester switch) is picked up on return to the tab, without a restart —
    // and before the heatmap, which marks out-of-range days 'outside'.
    final bool boundsChanged = await _loadSemesterBounds();

    if (boundsChanged) {
      final subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
      for (final sub in subjects) {
        await _timetableDao.ensureSeedEntry(sub.id!);
      }
      if (!mounted) return;
      setState(() => _allSubjects = subjects);
    }

    // Keep the user where they were, but do not strand focus/selection outside
    // a range that just shrank.
    DateTime focus = _focusedDay;
    if (focus.isBefore(_firstDay)) focus = _firstDay;
    if (focus.isAfter(_lastDay)) focus = _lastDay;
    if (focus != _focusedDay && mounted) setState(() => _focusedDay = focus);

    await _fetchMonthData(_focusedDay);
    final DateTime? current = _selectedDay;
    if (current != null) {
      DateTime selected = current;
      if (selected.isBefore(_firstDay)) selected = _firstDay;
      if (selected.isAfter(_lastDay)) selected = _lastDay;
      if (selected != current && mounted) {
        setState(() => _selectedDay = selected);
      }
      if (mounted) await _loadForDate(selected);
    }
  }

  /// Loads actual SAP records for imported report dates. Timetable-only slots
  /// appear as "Not Updated" only while that date has no imported SAP coverage.
  Future<void> _loadForDate(DateTime date) async {
    setState(() {
      _loading = true;
      _loadSeq++;
    });

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
            // Keyboard inset is handled centrally by showAppModalSheet's
            // scroll view; adding viewInsets here too would double the gap.
            padding: const EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24,
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

  Widget _buildLegendItem(Color color, String title, String subtitle, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: theme.textTheme.bodySmall?.color,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final today = DateTime.utc(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final isFutureDay = _selectedDay != null && _selectedDay!.isAfter(today);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = context.appColors;

    // Each day is a filled, bordered rounded tile. The fill tints the whole
    // box; the border is a touch more saturated so the edge stays crisp.
    final colorPresentBg = c.success.withAlpha(isDark ? 46 : 40);
    final colorPresentBorder = c.success.withAlpha(isDark ? 150 : 120);
    final colorAbsentBg = c.danger.withAlpha(isDark ? 52 : 44);
    final colorAbsentBorder = c.danger.withAlpha(isDark ? 160 : 130);
    // Matched to the present/absent alphas — the mixed tiles used to run hotter
    // (56/170), which read as a glow next to the calmer green/red boxes.
    final colorMixedBg = c.warning.withAlpha(isDark ? 46 : 40);
    final colorMixedBorder = c.warning.withAlpha(isDark ? 150 : 120);
    final colorHolidayBg = isDark
        ? Colors.white.withAlpha(14)
        : Colors.grey.withAlpha(24);

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
            // The whole page is one always-scrollable view so a pull-down
            // anywhere on the calendar screen engages the RefreshIndicator —
            // the same pattern Dashboard and Profile use. The records list
            // below is shrink-wrapped and non-scrolling so it flows as part of
            // this page scroll instead of fighting it.
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calendar widget
                  Container(
                  // Same header-to-content gap as Dashboard and Profile (§3).
                  margin: const EdgeInsets.fromLTRB(
                      10, AppDimens.headerContentGap, 10, 0),
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(15)
                        : Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(18),
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
                              // Match row height to the cell width (~width/7)
                              // so each filled tile reads as a rounded square.
                              rowHeight: (MediaQuery.sizeOf(context).width / 7.2)
                                  .clamp(44.0, 58.0),
                              daysOfWeekHeight: 16,
                              headerStyle: HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                                headerPadding: EdgeInsets.zero,
                                titleTextStyle: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                leftChevronIcon: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(25)
                                        : Colors.grey.withAlpha(30),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chevron_left,
                                    color: theme.iconTheme.color,
                                    size: 15,
                                  ),
                                ),
                                rightChevronIcon: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(25)
                                        : Colors.grey.withAlpha(30),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right,
                                    color: theme.iconTheme.color,
                                    size: 15,
                                  ),
                                ),
                              ),
                              daysOfWeekStyle: DaysOfWeekStyle(
                                weekdayStyle: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                                weekendStyle: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                                dowTextFormatter: (date, locale) =>
                                    DateFormat.E(locale).format(date).toUpperCase(),
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

                                  final status = _monthStatuses[normalizedDay];
                                  Color? bgColor;
                                  Color? borderColor;
                                  Color textColor =
                                      theme.textTheme.bodyLarge?.color ??
                                      Colors.black;
                                  // Selection no longer has a fill to carry it,
                                  // so it takes the same bold the current date
                                  // gets — otherwise the only thing separating a
                                  // picked day from an unpicked one is a 2px
                                  // border it may already share with its status.
                                  final FontWeight weight = isToday || isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600;

                                  switch (status) {
                                    case 'outside':
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
                                      borderColor = colorPresentBorder;
                                    case 'all_a':
                                      bgColor = colorAbsentBg;
                                      borderColor = colorAbsentBorder;
                                    case 'mixed':
                                      bgColor = colorMixedBg;
                                      borderColor = colorMixedBorder;
                                    case 'all_nu':
                                      bgColor = colorMixedBg;
                                      borderColor = colorMixedBorder;
                                  }

                                  // Fill the whole grid cell with an equal
                                  // margin on every side, so the gaps between
                                  // day tiles are the same horizontally and
                                  // vertically. A rounded rect gives the tile
                                  // its soft-square shape.
                                  Widget dayCell({
                                    required Color? fill,
                                    required Border? border,
                                    required Widget child,
                                  }) {
                                    return Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      margin: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: fill,
                                        border: border,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: child,
                                    );
                                  }

                                  // The date itself. Today is marked by a short
                                  // rounded underline beneath the number rather
                                  // than a border or a disc, which leaves the
                                  // border free to mean one thing only —
                                  // selection — so a selected day that is not
                                  // today can no longer be confused with the
                                  // current date. An underline also sits clear
                                  // of the tile's attendance fill instead of
                                  // covering it, which is what the old solid
                                  // chip (and its 8px blurred shadow, the glow)
                                  // got wrong.
                                  //
                                  // The stack is 14px of text + 3 gap + 3 rule =
                                  // ~26, safe at every row height: rowHeight
                                  // clamps to 44…58 and dayCell insets 3 a side,
                                  // so the cell is never shorter than 38.
                                  Widget label = Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: weight,
                                      fontSize: 14,
                                    ),
                                  );
                                  if (isToday) {
                                    label = Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        label,
                                        const SizedBox(height: 3),
                                        Container(
                                          width: 16,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return dayCell(
                                    fill: bgColor,
                                    border: isSelected
                                        ? Border.all(
                                            color: theme.colorScheme.primary,
                                            width: 2,
                                          )
                                        : borderColor != null
                                        ? Border.all(
                                            color: borderColor,
                                            width: 1.2,
                                          )
                                        : null,
                                    child: label,
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
                                // Keep focus inside the semester range; a page
                                // at the very edge can report a day just past
                                // the bound, which TableCalendar's base asserts.
                                final clamped = focusedDay.isBefore(_firstDay)
                                    ? _firstDay
                                    : (focusedDay.isAfter(_lastDay)
                                          ? _lastDay
                                          : focusedDay);
                                _focusedDay = clamped;
                                _fetchMonthData(clamped);
                              },
                            ),

                      // Divider above legend
                      if (_isCalendarReady)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: c.cardBorder,
                          ),
                        ),

                      // Legend
                      if (_isCalendarReady)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildLegendItem(
                                c.success,
                                'All Present',
                                'Attended all',
                                theme,
                              ),
                              _buildLegendItem(
                                c.danger,
                                'All Absent',
                                'Absent all',
                                theme,
                              ),
                              _buildLegendItem(
                                c.warning,
                                'Mixed',
                                'Partial attendance',
                                theme,
                              ),
                              _buildLegendItem(
                                isDark ? Colors.white.withAlpha(100) : Colors.grey,
                                'Off',
                                'No classes',
                                theme,
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

                // Records list. Flows within the page scroll (no Expanded):
                // the list shrink-wraps and the transient states get a fixed
                // height so the AnimatedSwitcher cross-fade has a stable box.
                AnimatedSwitcher(
                    duration: AppMotion.standard,
                    switchInCurve: AppMotion.enter,
                    switchOutCurve: AppMotion.exit,
                    child: _loading
                        // Keyed by load sequence (see _loadSeq): each load gets
                        // a unique key so a re-load's spinner never shares a key
                        // with the previous one still animating out of the
                        // switcher's transition Stack.
                        ? SizedBox(
                            height: 320,
                            key: ValueKey('loading-$_loadSeq'),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          )
                        : isSunday
                        ? const SizedBox(
                            height: 320,
                            key: ValueKey('sunday'),
                            child: EmptyState(
                              icon: Icons.weekend_rounded,
                              message: 'Sunday — no classes',
                              compact: true,
                            ),
                          )
                        // Future days fall through to the record list:
                        // getDaySchedule projects the weekday timetable for them,
                        // so they preview as read-only "Scheduled" rows (controls
                        // suppressed below). This is the §4 fix that removes the
                        // daily re-upload requirement.
                        : _dayRecords.isEmpty
                        ? const SizedBox(
                            height: 320,
                            key: ValueKey('empty'),
                            child: EmptyState(
                              icon: Icons.event_note_outlined,
                              message:
                                  'No records for this date\nTap + to add one',
                              compact: true,
                            ),
                          )
                        : ListView.builder(
                            key: ValueKey(_selectedDay),
                            // Shrink-wrapped into the page scroll instead of
                            // owning its own viewport, so the whole screen is
                            // one pull-to-refresh surface (§ calendar refresh).
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              AppDimens.space16,
                              AppDimens.space4,
                              AppDimens.space16,
                              // Clear the whole floating stack so the last card
                              // never tucks under it: nav bar + its float off
                              // the edge, then the gap + the "Add record" pill
                              // sitting above it, plus a little breathing room.
                              // (A flat 100 was ~32 short of the pill's top.)
                              GlassNavTheme.verticalInset +
                                  GlassNavTheme.barHeight +
                                  GlassNavTheme.actionGap +
                                  GlassNavTheme.actionHeight +
                                  AppDimens.space16 +
                                  MediaQuery.paddingOf(context).bottom,
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
                              final isNotConducted = status == 'NC';
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
                              // Future rows are a read-only preview; a neutral
                              // dot rather than the warning colour NU picks (§4).
                              final statusColor = isFutureDay
                                  ? (theme.textTheme.bodyMedium?.color ??
                                        c.warning)
                                  : isNU || isNotConducted
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
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
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
                                                // A future row is a virtual NU
                                                // slot, but "tap to set status"
                                                // is a lie there — it is a
                                                // preview, not markable (§4).
                                                isFutureDay
                                                    ? (hasDuplicates
                                                          ? 'Scheduled - Lecture $lectureNum'
                                                          : 'Scheduled')
                                                    : isNotConducted
                                                    ? (hasDuplicates
                                                          ? 'Not Conducted - Lecture $lectureNum'
                                                          : 'Not Conducted')
                                                    : isNU
                                                    ? (hasDuplicates
                                                          ? 'Not Updated - Lecture $lectureNum'
                                                          : 'Not Updated - tap to set status')
                                                    : (hasDuplicates
                                                          ? '${isPresent ? 'Present' : 'Absent'} - Lecture $lectureNum'
                                                          : (isPresent
                                                                ? 'Present'
                                                                : 'Absent')),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
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
                                        // Future days show no controls: attendance
                                        // for a lecture that has not happened is
                                        // not assertable. The FAB is already
                                        // suppressed by canAddRecord; this closes
                                        // the per-row path (§4).
                                        if (timetableId != null && !isFutureDay)
                                          // Trailing controls — fixed block, right-aligned so the
                                          // P/A cluster and delete icon land on the same x on
                                          // every row regardless of subject-name length.
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              if (isNotConducted) ...[
                                                const SizedBox.shrink(),
                                              ] else if (isNU) ...[
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
                                              // Virtual (timetable-filled) rows have nothing stored to
                                              // delete — they reappear from the timetable anyway.
                                              if (!isVirtual) ...[
                                                const SizedBox(width: 6),
                                                SizedBox(
                                                  width: 36,
                                                  child: IconButton(
                                                    icon: Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      size: 20,
                                                      color: theme
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.color,
                                                    ),
                                                    onPressed: () =>
                                                        _deleteRecord(
                                                          timetableId,
                                                          recordDate,
                                                        ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                      ],
                                    ),
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
      // Min width keeps the 'P'/'A'/'NU' pills the same size as the wider
      // 'Present'/'Absent' pills so clusters line up across rows.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
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
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? color : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
