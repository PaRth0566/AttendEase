import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../services/app_refresh_bus.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/glass_nav_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass_action_button.dart';
import '../../widgets/app_overlays.dart';
import '../../widgets/beak_tooltip.dart';
import '../../widgets/calendar_day_header.dart';
import '../../widgets/callout_box.dart';
import '../root/tab_page_state.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

/// Whether [record] fills the trailing delete column of its row.
///
/// A stored Present or Absent renders the delete button; a stored "Not
/// Conducted" renders the disabled icon explaining why the report's own row
/// cannot be deleted. Those are the only two cases, so "stored, and not NU" is
/// the whole rule.
///
/// Read twice: once per row, to draw the right thing, and once across the day,
/// to decide whether the column exists at all. A day of nothing but "Not
/// Updated" lectures has no delete affordance anywhere in it, and reserving
/// width for one there is what left every row's P/A pills floating 42px short of
/// the card edge instead of sitting against it.
bool occupiesDeleteColumn(Map<String, dynamic> record) {
  final bool isVirtual =
      record['is_virtual'] == 1 || record['record_id'] == null;
  return !isVirtual && record['status'] != 'NU';
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

  /// How long "Undo" stays available after a delete.
  ///
  /// One constant so the confirmation dialog's copy, the snackbar's lifetime
  /// and the countdown ring can never disagree about the window.
  static const Duration _undoWindow = Duration(seconds: 5);

  /// The record most recently deleted, kept so [_undoDelete] can put it back.
  /// Cleared when the undo deadline expires or the snackbar is dismissed. In
  /// memory only — a killed app forfeits the window.
  _DeletedRecord? _lastDeleted;
  Timer? _undoTimer;

  /// True only for the duration of the [AppRefreshBus.refreshAll] call this
  /// screen makes after writing. See [_notifyOtherTabs].
  bool _ignoreBusReload = false;

  /// True while a "mark the whole day" is in flight. See [_markWholeDay].
  bool _bulkMarking = false;

  @override
  void initState() {
    super.initState();
    _initCalendarDates();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
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

    final bool changed =
        _activeSemester != sem || _firstDay != newFirst || _lastDay != newLast;
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
    // Already up to date: this is the app-wide refresh *this* screen just fired
    // after its own write, and re-reading here would only cost a spinner flash.
    if (_ignoreBusReload) return;

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

  // ── Mark the whole day ──────────────────────────────────────────────────────

  /// Whether the open day has anything a bulk mark could write.
  ///
  /// A day of nothing but "Not Conducted" rows does not — see [planDayMark],
  /// which owns that rule and every other one about what a whole-day mark is
  /// allowed to touch.
  bool get _hasBulkTargets => planDayMark(_dayRecords, 'P').markableCount > 0;

  /// Sets every markable lecture on the open day to [status] ('P' or 'A').
  ///
  /// Asks first only when the day already holds marked attendance that would be
  /// flipped. A day whose lectures are all still "Not Updated" has nothing to
  /// lose, so it is written straight away — a dialog there is friction for
  /// nothing.
  Future<void> _markWholeDay(String status) async {
    // One bulk mark at a time. Both pills plan from [_dayRecords], which is only
    // refreshed once the write completes — so a quick "All P" then "All A" would
    // otherwise run two writes off the same stale snapshot and leave the day
    // showing whichever finished last.
    if (_bulkMarking) return;
    final DateTime? day = _selectedDay;
    if (day == null) return;

    final plan = planDayMark(_dayRecords, status);
    if (plan.markableCount == 0) return;

    _bulkMarking = true;
    try {
      await _runMarkWholeDay(day, status, plan);
    } finally {
      _bulkMarking = false;
    }
  }

  /// The body of [_markWholeDay], split out only so the in-flight flag is
  /// released by one `finally` on every path out — including the early returns
  /// below and a cancelled dialog.
  Future<void> _runMarkWholeDay(
    DateTime day,
    String status,
    DayMarkPlan plan,
  ) async {
    final String word = status == 'P' ? 'present' : 'absent';

    if (plan.isEmpty) {
      _showDayMessage(
        'Every lecture on this day is already marked $word.',
        icon: Icons.info_outline_rounded,
        color: Theme.of(context).colorScheme.primary,
      );
      return;
    }

    if (plan.overwritesExistingMarks) {
      final bool confirmed = await _confirmMarkWholeDay(
        day: day,
        status: status,
        plan: plan,
      );
      if (!confirmed || !mounted) return;
      // The dialog is modal so the day cannot have been re-selected under it,
      // but a background refresh could have. Writing keys planned for a day that
      // is no longer open would edit records the user cannot see, so the safe
      // answer is to do nothing.
      if (!isSameDay(_selectedDay, day)) return;
    }

    await _applyMarkWholeDay(plan);
    if (!mounted) return;

    final c = context.appColors;
    final int n = plan.entries.length;
    _showDayMessage(
      n == 1 ? 'Marked 1 lecture $word.' : 'Marked $n lectures $word.',
      icon: status == 'P'
          ? Icons.check_circle_outline_rounded
          : Icons.cancel_outlined,
      color: status == 'P' ? c.success : c.danger,
    );
  }

  /// Writes [plan] in one transaction, then re-derives everything that reads it.
  ///
  /// The baseline rules that keep the "Manual" badge honest live in
  /// [planDayMark]; all that happens here is the write and the refresh.
  Future<void> _applyMarkWholeDay(DayMarkPlan plan) async {
    if (plan.isEmpty) return;

    await _attendanceDao.upsertAttendanceBatch(plan.entries);
    if (!mounted) return;

    await _fetchMonthData(_focusedDay);
    if (!mounted) return;
    final DateTime? selected = _selectedDay;
    if (selected != null) await _loadForDate(selected);
    CloudSyncService().backupDataToCloud();
    if (!mounted) return;
    _notifyOtherTabs();
  }

  /// Tells the rest of the app to re-read the database after a write here.
  ///
  /// A whole day changing at once moves the dashboard's percentages, the report's
  /// totals and the subject timelines, and [AppRefreshBus] is how a write in one
  /// tab reaches the others without waiting for the user to walk over.
  ///
  /// The bus fans out to every mounted tab, this one included — and this screen
  /// has already refreshed itself by the time it fires. `refreshAll` notifies
  /// synchronously, so setting the flag around the call is enough to skip that
  /// redundant second read (and the spinner flash it would bring).
  void _notifyOtherTabs() {
    _ignoreBusReload = true;
    AppRefreshBus.instance.refreshAll();
    _ignoreBusReload = false;
  }

  /// Asks before a bulk mark overwrites attendance that is already recorded.
  ///
  /// Same shape as the app's other consequential confirmations — tinted disc,
  /// centred copy, the thing being changed boxed on its own surface — and the
  /// counts are spelled out because "the whole day" is the one detail the user
  /// cannot check while the dialog covers the list.
  Future<bool> _confirmMarkWholeDay({
    required DateTime day,
    required String status,
    required DayMarkPlan plan,
  }) async {
    final theme = Theme.of(context);
    final c = context.appColors;
    final bool present = status == 'P';
    final Color tint = present ? c.success : c.danger;
    final String word = present ? 'Present' : 'Absent';
    final Color? muted = theme.textTheme.bodySmall?.color;

    String lectures(int n) => n == 1 ? '1 lecture' : '$n lectures';

    final bool? result = await showAppDialog<bool>(
      context: context,
      // A stray tap outside must never rewrite a whole day's attendance.
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        // The same tinted-disc header the sync dialog uses, in the colour of the
        // status being applied, so green and red are recognisable before the
        // title is read.
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            present ? Icons.done_all_rounded : Icons.remove_done_rounded,
            color: tint,
            size: 24,
          ),
        ),
        title: Text('Mark this day all ${word.toLowerCase()}?'),
        // Scrolls rather than overflows: AlertDialog lays its content out at
        // intrinsic height, and at the 1.4 text scale showAppDialog allows the
        // copy + box + footnote can outgrow a short viewport.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This day already has attendance recorded. Every lecture on it '
                'will be set to $word, replacing what is there now. Only this '
                'day changes — every other day stays as it is.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppDimens.space20),
              // The day, boxed on its own surface — the one thing worth double
              // checking before overwriting it.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space10,
                ),
                decoration: BoxDecoration(
                  color: c.subtleSurface,
                  borderRadius: AppDimens.brMd,
                  border: Border.all(color: c.cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(Icons.event_rounded, size: 18, color: muted),
                    ),
                    const SizedBox(width: AppDimens.space10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy').format(day),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: AppDimens.space2),
                          Text(
                            '${plan.entries.length} of '
                            '${lectures(plan.markableCount)} change · '
                            '${plan.overwriteCount} already marked',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.35,
                            ),
                          ),
                          if (plan.notConductedCount > 0)
                            Text(
                              '${lectures(plan.notConductedCount)} not '
                              'conducted — left as they are',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.space16),
              Text(
                'Your Report & Analysis percentages are recalculated, and the '
                'change syncs to your cloud backup.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppDimens.space20,
          AppDimens.space8,
          AppDimens.space20,
          AppDimens.space20,
        ),
        // "Mark all present" beside "Cancel" overruns a narrow phone's dialog,
        // and the default row would wrap the label inside the pill. Stacking
        // stays legible at any width — same treatment the replace dialog gets.
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: AppDimens.space8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppDimens.space4),
          FilledButton(
            // The app's own green/red, the same pair the day's cards and the
            // pill that opened this dialog are painted with.
            style: FilledButton.styleFrom(
              backgroundColor: tint,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space20,
                vertical: AppDimens.space12,
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Mark all ${word.toLowerCase()}'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// A one-line result chip for the bulk actions.
  ///
  /// Cleared of the calendar's floating "Add record" pill the same way the undo
  /// bar is — see [GlassNavTheme.snackBarPillClearance].
  void _showDayMessage(
    String text, {
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.only(
            left: AppDimens.space16,
            right: AppDimens.space16,
            bottom: GlassNavTheme.snackBarPillClearance,
          ),
          content: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
  }

  /// `2026-08-11_2` → `Mon, 11 Aug`.
  ///
  /// The `_n` suffix keys a subject's second lecture in a day. That is a storage
  /// detail; it has no business in a sentence shown to the user.
  String _prettyDate(String recordDate) {
    final base = recordDate.split('_').first;
    try {
      return DateFormat('EEE, d MMM').format(DateTime.parse(base));
    } catch (_) {
      return base;
    }
  }

  /// Step 1 — ask first, and show exactly *which* record is going.
  ///
  /// The record is rendered as the same status-dot + name + status-line card the
  /// calendar row uses, because the mis-tap this dialog exists to catch is
  /// "wrong row", not "wrong intent" — and a prose-only dialog cannot answer
  /// which row you hit.
  Future<bool> _confirmDelete({
    required String subjectName,
    required String statusLabel,
    required Color statusColor,
    required String prettyDate,
  }) async {
    final theme = Theme.of(context);
    final c = context.appColors;

    final bool? result = await showAppDialog<bool>(
      context: context,
      // An accidental tap outside must not silently complete an accidental
      // delete. Cancel is one explicit button away.
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        // Shape, elevation, title and content styles all come from dialogTheme.
        title: const Text('Delete this record?'),
        // Scrolls rather than overflows: AlertDialog lays its content out at
        // intrinsic height, and at the 1.4 text scale showAppDialog allows, a
        // card + callout + line of copy can outgrow a short viewport.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── The record, as a card ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space10,
                ),
                decoration: BoxDecoration(
                  color: c.subtleSurface,
                  borderRadius: AppDimens.brMd,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: AppDimens.space12),
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subjectName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: AppDimens.space2),
                          Text(
                            '$statusLabel · $prettyDate',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.space16),

              // ── What it costs ─────────────────────────────────────
              const CalloutBox(
                kind: CalloutKind.danger,
                title: 'This changes your attendance',
                message:
                    'The lecture is removed from this day, your Report & '
                    'Analysis percentages are recalculated, and the change '
                    'syncs to your cloud backup.',
              ),
              const SizedBox(height: AppDimens.space12),

              Text(
                'You can undo this for '
                '${_undoWindow.inSeconds} seconds.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            // c.danger, not Colors.red — the app has one red, and it is the
            // same one the "Absent" dot on this very card is painted with.
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Step 2 — delete, but remember the whole row so Undo can restore it.
  ///
  /// Deleting drops the only copy of `original_status` (the PDF baseline), so a
  /// re-import can never rebuild this record. Undo therefore re-inserts the
  /// captured row verbatim rather than creating a fresh one.
  Future<void> _deleteWithUndo({
    required int recordId,
    required int timetableEntryId,
    required String date,
    required String status,
    required String statusLabel,
    required String source,
    required String? originalStatus,
    required String subjectName,
  }) async {
    await _attendanceDao.deleteAttendanceById(recordId);

    _lastDeleted = _DeletedRecord(
      timetableEntryId: timetableEntryId,
      date: date,
      status: status,
      statusLabel: statusLabel,
      source: source,
      originalStatus: originalStatus,
      subjectName: subjectName,
    );

    if (!mounted) return;
    if (_selectedDay != null) await _loadForDate(_selectedDay!);
    if (!mounted) return;
    await _fetchMonthData(_focusedDay);
    CloudSyncService().backupDataToCloud();

    if (!mounted) return;
    _showUndoSnackBar();
  }

  /// Step 3 — offer Undo for [_undoWindow], then let the delete stick.
  void _showUndoSnackBar() {
    final messenger = ScaffoldMessenger.of(context);
    // One at a time. Queued undo bars would let the user tap Undo on a bar
    // whose record is no longer the one _lastDeleted holds.
    _undoTimer?.cancel();
    _undoTimer = null;
    messenger.hideCurrentSnackBar();

    final deleted = _lastDeleted;
    if (deleted == null) return;

    final snack = messenger.showSnackBar(
      SnackBar(
        duration: _undoWindow,
        // Shape, colour and floating behaviour all come from snackBarTheme.
        // Only the margin is set here, and only by what the theme cannot know:
        // the calendar's own floating "Add record" pill. See
        // GlassNavTheme.snackBarPillClearance for why the nav bar itself needs
        // no allowance.
        margin: const EdgeInsets.only(
          left: AppDimens.space16,
          right: AppDimens.space16,
          bottom: GlassNavTheme.snackBarPillClearance,
        ),
        content: Row(
          children: [
            const _UndoCountdownRing(duration: _undoWindow),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: Text(
                '${deleted.subjectName} · ${deleted.statusLabel} deleted',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Undo',
          // Bound to *this* bar's record, not to whatever _lastDeleted holds
          // when the tap lands. A bar that is already sliding out because a
          // second delete replaced it is still briefly tappable, and reading
          // the field there would restore the newer record instead of this one.
          onPressed: () => _undoDelete(deleted),
        ),
      ),
    );

    // SnackBars with an action intentionally stay open while accessibility
    // navigation is enabled. Keep the Undo affordance accessible, but enforce
    // the product's five-second deadline independently of that framework rule.
    _undoTimer = Timer(_undoWindow, () {
      if (!mounted || !identical(_lastDeleted, deleted)) return;
      _lastDeleted = null;
      _undoTimer = null;
      messenger.hideCurrentSnackBar();
    });

    // The delete sticks once the deadline expires (or the bar is dismissed).
    //
    // Identity-checked, not just null-checked: deleting a second record inside
    // the window calls hideCurrentSnackBar() above, and *this* future is what
    // completes as a result — a blind `_lastDeleted = null` would throw away
    // the newer record and make the second delete un-undoable.
    snack.closed.then((_) {
      if (!mounted) return;
      if (identical(_lastDeleted, deleted)) {
        _lastDeleted = null;
        _undoTimer?.cancel();
        _undoTimer = null;
      }
    });
  }

  /// Restores [deleted] exactly as it was, if its undo window is still open.
  ///
  /// The identity check is the whole guard: a bar whose record has already been
  /// superseded by a later delete, or whose window has elapsed, restores
  /// nothing. Only one delete is undoable at a time, by design.
  ///
  /// The heatmap and the day list are re-derived from the database rather than
  /// from a pre-delete snapshot: the row goes back with the same status, source
  /// and baseline, so the queries behind them return exactly what they returned
  /// before the delete — and a snapshot would be wrong anyway if the user paged
  /// the calendar to another month during the undo window.
  Future<void> _undoDelete(_DeletedRecord deleted) async {
    if (!identical(_lastDeleted, deleted)) return;
    _lastDeleted = null;
    _undoTimer?.cancel();
    _undoTimer = null;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    await _saveRecord(
      deleted.timetableEntryId,
      deleted.date,
      deleted.status,
      source: deleted.source,
      originalStatus: deleted.originalStatus,
    );
    if (!mounted) return;
    if (_selectedDay != null) await _loadForDate(_selectedDay!);
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = Theme.of(context);
          return Container(
            // Keyboard and system-navigation-bar insets are both handled
            // centrally by showAppModalSheet; adding either here would double
            // the gap.
            padding: const EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24,
            ),
            decoration: BoxDecoration(
              color: theme.bottomSheetTheme.backgroundColor ?? theme.cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: theme.dividerColor),
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
                  dropdownColor:
                      theme.dialogTheme.backgroundColor ?? theme.cardColor,
                  // Theme-derived: a DropdownButton replaces its text style
                  // rather than merging, so a bare TextStyle here left
                  // fontFamily null and the items painted blank on web.
                  //
                  style: theme.textTheme.bodyLarge,
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

  Widget _buildLegendItem(
    Color color,
    String title,
    String subtitle,
    ThemeData theme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        // No Flexible/Expanded here: the item reports its natural width so the
        // parent FittedBox can measure the true one-line width of all four and
        // scale the group as a unit. softWrap: false keeps a label on its own
        // single line even while being measured unbounded.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
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
    // Same gate as the per-row P/A pills, for the same reason: attendance for a
    // lecture that has not happened is not assertable (§4), a Sunday has no
    // lectures, and a day whose only rows are "Not Conducted" has nothing a bulk
    // mark could legitimately write. Hidden mid-load too — the pills would be
    // acting on the previous day's records.
    final canBulkMark = canAddRecord && !_loading && _hasBulkTargets;
    // Does *any* row on this day render something in the trailing delete column?
    //
    // The column is reserved per row so the P/A pills line up down the card
    // stack — but reserving it on a day where nothing can be deleted just
    // indents every row's pills by 42px away from the card's right edge, which
    // is what made an all-"Not Updated" day look mis-aligned. Decided once for
    // the whole day, so rows still agree with each other either way.
    final dayHasDeleteColumn = !isFutureDay &&
        _dayRecords.any(occupiesDeleteColumn);

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
                      10,
                      AppDimens.headerContentGap,
                      10,
                      0,
                    ),
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
                                child: Center(
                                  child: CircularProgressIndicator(),
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
                                // Match row height to the cell width (~width/7)
                                // so each filled tile reads as a rounded square.
                                rowHeight:
                                    (MediaQuery.sizeOf(context).width / 7.2)
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
                                      DateFormat.E(
                                        locale,
                                      ).format(date).toUpperCase(),
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

                                    final status =
                                        _monthStatuses[normalizedDay];
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
                                    final FontWeight weight =
                                        isToday || isSelected
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                            // The legend must read as a single row on every
                            // device. Three things guarantee that:
                            //  1. the row is pinned to its own text scale (below)
                            //     so a large system font cannot widen it;
                            //  2. mainAxisSize.min + explicit gutters — under a
                            //     FittedBox the main axis is unbounded, where
                            //     spaceBetween is undefined and used to leave a
                            //     few pixels of overflow;
                            //  3. scaleDown as the final fit, which on a narrow
                            //     phone trims a few percent rather than wrapping.
                            child: MediaQuery(
                              data: MediaQuery.of(
                                context,
                              ).copyWith(textScaler: TextScaler.linear(1.0)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _buildLegendItem(
                                      c.success,
                                      'All Present',
                                      'Attended all',
                                      theme,
                                    ),
                                    const SizedBox(width: 10),
                                    _buildLegendItem(
                                      c.danger,
                                      'All Absent',
                                      'Absent all',
                                      theme,
                                    ),
                                    const SizedBox(width: 10),
                                    _buildLegendItem(
                                      c.warning,
                                      'Mixed',
                                      'Partial attendance',
                                      theme,
                                    ),
                                    const SizedBox(width: 10),
                                    _buildLegendItem(
                                      isDark
                                          ? Colors.white.withAlpha(100)
                                          : Colors.grey,
                                      'Off',
                                      'No classes',
                                      theme,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Selected day label, with the day's two bulk-mark pills on
                  // the same line.
                  if (_selectedDay != null)
                    CalendarDayHeader(
                      day: _selectedDay!,
                      showBulkActions: canBulkMark,
                      onMarkAllPresent: () => _markWholeDay('P'),
                      onMarkAllAbsent: () => _markWholeDay('A'),
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
                            physics: const NeverScrollableScrollPhysics(),
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
                              // Delete is for *marked* attendance only.
                              //
                              // NU has no mark to remove — deleting a stored NU
                              // just destroys the PDF baseline that lets you tap
                              // P/A on it, and a virtual NU has no row at all.
                              // NC is a fact the report asserted (the lecture
                              // never happened) rather than something you
                              // marked, and it carries no weight in any
                              // percentage, so removing it would change nothing
                              // but the day's list.
                              final canDelete =
                                  !isVirtual && (isPresent || status == 'A');
                              final deleteBlockedReason =
                                  !isVirtual && isNotConducted
                                  // Deliberately short: this rides in a
                                  // one-line bubble, and the row it points at
                                  // already says "Not Conducted" an inch to the
                                  // left — repeating it here would cost the
                                  // single line and say nothing new.
                                  ? 'From your report — can’t be deleted'
                                  : null;                              final c = context.appColors;
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
                                              // Wraps to a second line rather
                                              // than ellipsizing: the whole
                                              // point of the row is knowing
                                              // which subject it is, and at a
                                              // larger font setting a single
                                              // line cut most names to
                                              // "Software Eng…". The card grows
                                              // a line instead.
                                              Text(
                                                subjectName,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.25,
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
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.25,
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
                                                          originalStatus ??
                                                          'NU',
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
                                                          originalStatus ??
                                                          'NU',
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
                                              // The delete column is reserved on
                                              // every row of a day that has one
                                              // anywhere, so the P/A pills line
                                              // up down the stack rather than
                                              // stepping 42px sideways on the
                                              // rows without a button. On a day
                                              // where nothing is deletable —
                                              // every lecture still "Not
                                              // Updated" — there is no column to
                                              // reserve, and the pills sit
                                              // against the card's edge like any
                                              // other trailing control.
                                              if (dayHasDeleteColumn) ...[
                                                const SizedBox(width: 6),
                                                if (canDelete)
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
                                                      tooltip: 'Delete record',
                                                      onPressed: () async {
                                                        final statusLabel =
                                                            isPresent
                                                            ? 'Present'
                                                            : 'Absent';
                                                        final ok =
                                                            await _confirmDelete(
                                                              subjectName:
                                                                  subjectName,
                                                              statusLabel:
                                                                  statusLabel,
                                                              // The row's own
                                                              // colour, so the
                                                              // dialog's dot
                                                              // matches the card
                                                              // that was tapped.
                                                              statusColor:
                                                                  statusColor,
                                                              prettyDate:
                                                                  _prettyDate(
                                                                    recordDate,
                                                                  ),
                                                            );
                                                        if (!ok) return;
                                                        if (!mounted) return;
                                                        await _deleteWithUndo(
                                                          recordId: recordId,
                                                          timetableEntryId:
                                                              timetableId,
                                                          // The raw key —
                                                          // storage, not
                                                          // display.
                                                          date: recordDate,
                                                          status: status,
                                                          statusLabel:
                                                              statusLabel,
                                                          source:
                                                              record['source']
                                                                  as String? ??
                                                              'manual',
                                                          originalStatus:
                                                              originalStatus,
                                                          subjectName:
                                                              subjectName,
                                                        );
                                                      },
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  )
                                                else if (deleteBlockedReason !=
                                                    null)
                                                  SizedBox(
                                                    width: 36,
                                                    child: BeakTooltip(
                                                      // Touch-first: a
                                                      // long-press-only tooltip
                                                      // is undiscoverable, so
                                                      // the explanation would
                                                      // never be read.
                                                      message:
                                                          deleteBlockedReason,
                                                      child: Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 20,
                                                        // 0.35 reads as "present
                                                        // but off"; the card's
                                                        // own border alpha
                                                        // (80/255) read as a
                                                        // glitch on the dark
                                                        // theme.
                                                        color: theme
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.color
                                                            ?.withValues(
                                                              alpha: 0.35,
                                                            ),
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  const SizedBox(width: 36),
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
      // 'Present'/'Absent' pills so clusters line up across rows. The max is
      // what stops a larger system font from inflating the 'Present' pill until
      // it crowds the subject name out of the row — past that the label
      // ellipsizes and the name keeps its space.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40, maxWidth: 92),
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

/// A deleted attendance record plus everything needed to put it back.
///
/// The whole row is captured, not just its key: `original_status` — the PDF
/// baseline that decides the "Manual" badge and whether the row can be reverted
/// to NU — lives only in `attendance_records`, so once the row is gone no
/// re-import can reconstruct it. Undo re-inserts these values verbatim.
class _DeletedRecord {
  const _DeletedRecord({
    required this.timetableEntryId,
    required this.date,
    required this.status,
    required this.statusLabel,
    required this.source,
    required this.originalStatus,
    required this.subjectName,
  });

  final int timetableEntryId;

  /// The full storage key, `_n` suffix included — the record's identity.
  final String date;

  /// 'P' or 'A'; delete is not offered on any other status.
  final String status;

  /// 'Present' or 'Absent' — so the snackbar names what went, not just where.
  final String statusLabel;
  final String source;

  /// The PDF baseline. Unrecoverable once the row is deleted.
  final String? originalStatus;
  final String subjectName;
}

/// A ring that drains over [duration], showing how long Undo remains available.
///
/// A window the user cannot see is a guess. Purely decorative: the SnackBar's
/// own `duration` is what actually closes the bar — this only visualises it.
class _UndoCountdownRing extends StatelessWidget {
  const _UndoCountdownRing({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    const double size = 20;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color progressColor = isDark
        ? const Color(0xFF62D488)
        : context.appColors.success;
    final Color trackColor = isDark
        ? const Color(0xFF303833)
        : const Color(0xFFD7DED9);
    final Color outlineColor = isDark
        ? const Color(0xFF77827B)
        : const Color(0xFF84928A);

    Widget framed(Widget child) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: outlineColor, width: 1),
          ),
          child: Padding(padding: const EdgeInsets.all(2), child: child),
        ),
      );
    }

    // Nothing to watch drain when the OS has "remove animations" on, and a
    // ring frozen at full would misreport the window as untouched.
    if (MediaQuery.of(context).disableAnimations) {
      return framed(Icon(Icons.timer_outlined, size: 13, color: progressColor));
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: duration,
      // Linear on purpose: an eased countdown lies about the time remaining.
      curve: Curves.linear,
      builder: (context, value, child) => framed(
        CircularProgressIndicator(
          value: value,
          strokeWidth: 2,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
        ),
      ),
    );
  }
}
