import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/container_transform.dart';
import '../../utils/calculation_utils.dart';
import '../root/tab_page_state.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pressable.dart';

/// Whether the dashboard's progress sweeps — the overall ring and every subject
/// bar — have already played in this process.
///
/// They are a "here is where you stand" flourish, which only reads as one on a
/// cold launch. The shell rebuilds each tab's page on selection, so without
/// this every bar re-filled from zero each time the Dashboard tab came back,
/// and again after every data reload. A library-level flag (rather than State
/// fields) survives those State recreations and is shared by the ring and the
/// cards, which are separate widgets; it dies with the process, so the sweep
/// returns on the next launch after the app is killed.
///
/// Flipped by the ring's `onEnd` — it and the bars start on the same frame with
/// the same duration, so one owner covers both.
bool _sweepsPlayed = false;

class DashboardScreen extends StatefulWidget {
  final List<Subject>? overrideSubjects;
  final Map<int, Map<String, int>>? overrideStats;

  const DashboardScreen({super.key, this.overrideSubjects, this.overrideStats});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends TabPageState<DashboardScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  // Kept alive so the PageView composites an existing layer during a tab slide
  // instead of rebuilding this page mid-drag (§1.6).
  @override
  bool get wantKeepAlive => true;

  final SubjectDao _subjectDao = SubjectDao();
  final AttendanceDao _attendanceDao = AttendanceDao();

  List<Subject> _subjects = [];
  Map<int, Map<String, int>> _attendanceStats = {};

  double _currentOverall = 0.0;
  double _requiredTarget = 75.0;
  int _activeSemester = 1;

  int _totalAttendedOverall = 0;
  int _totalLecturesOverall = 0;

  /// This week's day-by-day skip verdicts. Null when there is nothing
  /// meaningful to show: the web preview path, or no inferable schedule yet.
  WeekSkipPlan? _weekSkipPlan;

  /// Subject names, for naming the blocking subject on an unsafe day.
  Map<int, String> _subjectNames = const {};

  /// The calendar date [_weekSkipPlan] was built for. Every verdict in the
  /// strip is relative to "today", so a plan built yesterday is actively
  /// misleading — see [didChangeAppLifecycleState] and
  /// [_scheduleMidnightRefresh].
  DateTime? _planComputedFor;
  Timer? _midnightTimer;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// The app coming back from the background is the common way the week strip
  /// goes stale: `RootScreen`'s resume handler only reloads pages when a cloud
  /// restore actually changed something, so a phone left in a pocket overnight
  /// would still render yesterday as "today".
  ///
  /// Date-compare only, so a resume on the same day costs nothing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_planComputedFor != null && today.isAfter(_planComputedFor!)) {
      _loadDashboardData();
    }
  }

  /// Reloads at the next local midnight, for an app left open across the date
  /// boundary. Re-armed by each load.
  ///
  /// A `Timer` measures elapsed time rather than wall-clock, so a manual clock
  /// change or DST shift can fire it early; the `_planComputedFor` guard above
  /// is the backstop, and a reload that finds the same date is harmless.
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    // Dart normalises day overflow, so month/year rollover needs no special
    // casing.
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      // A couple of seconds of slack so we land clearly inside the new day.
      nextMidnight.difference(now) + const Duration(seconds: 2),
      () {
        if (mounted) _loadDashboardData();
      },
    );
  }

  @override
  Future<void> reloadData() => _loadDashboardData();

  Future<void> _loadDashboardData() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final prefs = await SharedPreferences.getInstance();
      _requiredTarget = prefs.getDouble('overall_required_attendance') ?? 75.0;
      _activeSemester = prefs.getInt('semester') ?? 1;

      if (widget.overrideSubjects != null && widget.overrideStats != null) {
        _subjects = widget.overrideSubjects!;
        _attendanceStats = widget.overrideStats!;
      } else {
        _subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
        _attendanceStats = await _attendanceDao.getAttendanceStats(
          _activeSemester,
        );
      }

      _totalAttendedOverall = 0;
      _totalLecturesOverall = 0;

      for (final subject in _subjects) {
        final stat =
            _attendanceStats[subject.id] ?? {'attended': 0, 'total': 0};
        _totalAttendedOverall += stat['attended']!;
        _totalLecturesOverall += stat['total']!;
      }

      _currentOverall = _totalLecturesOverall == 0
          ? 0
          : (_totalAttendedOverall / _totalLecturesOverall) * 100;

      // Which days of this week can be fully skipped while staying on target.
      // Skipped when using override stats (web preview) — no timetable there.
      if (widget.overrideSubjects == null) {
        try {
          final history = await _attendanceDao.getAttendanceHistoryForSemester(
            _activeSemester,
          );
          _subjectNames = {
            for (final s in _subjects)
              if (s.id != null) s.id!: s.name,
          };
          _weekSkipPlan = computeWeekSkipPlan(
            subjectStats: _attendanceStats,
            subjectRequired: {
              for (final s in _subjects)
                if (s.id != null) s.id!: s.requiredPercent,
            },
            subjectHistory: history,
            overallRequired: _requiredTarget,
            today: today,
          );
        } catch (e) {
          debugPrint('Week skip-plan calc error: $e');
          _weekSkipPlan = null;
        }
      } else {
        _weekSkipPlan = null;
      }

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
    } catch (e) {
      debugPrint('Dashboard load error: $e');
    } finally {
      // Every strip verdict is relative to this date; record it and re-arm the
      // rollover watch. Both happen even on the error path, so a failed load
      // doesn't leave the app without a refresh trigger.
      _planComputedFor = today;
      _scheduleMidnightRefresh();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncAndReload() async {
    await CloudSyncService().syncBidirectional();
    await _loadDashboardData();
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
      if (skips <= 0) {
        return {
          'text': 'On track, but you cannot skip the next lecture.',
          'isSafe': true,
          'skips': 0,
        };
      }
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
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final c = context.appColors;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool isSafe = _currentOverall >= _requiredTarget;
    final Color statusColor = isSafe ? c.success : c.danger;
    final overallInsight = _getPredictiveInsight(
      _totalAttendedOverall,
      _totalLecturesOverall,
      _requiredTarget,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Dashboard', style: theme.textTheme.headlineSmall),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: RefreshIndicator(
            onRefresh: _syncAndReload,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                MediaQuery.of(context).size.width > 600
                    ? AppDimens.space32
                    : AppDimens.space16,
                AppDimens.headerContentGap,
                MediaQuery.of(context).size.width > 600
                    ? AppDimens.space32
                    : AppDimens.space16,
                // The Scaffold reports the floating glass nav bar's height as
                // bottom padding (it uses extendBody), so the last card can be
                // scrolled clear of it instead of sitting under the glass.
                AppDimens.space16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Overall attendance card ──────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimens.space20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Overall Attendance ',
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          TextSpan(
                                            text: '(Sem $_activeSemester)',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: AppTheme.primaryBlue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: AppDimens.space4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${_currentOverall.toStringAsFixed(1)}%',
                                        style: theme.textTheme.displaySmall
                                            ?.copyWith(
                                              color: theme
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color,
                                              // The one number the card exists
                                              // to show, sized to dominate it
                                              // as in the reference.
                                              fontSize: 40,
                                              height: 1.1,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: AppDimens.space2),
                                    Text(
                                      'Target: ${_requiredTarget.toStringAsFixed(1)}%',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppDimens.space16),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    // Wheel: tighter footprint, heavier ring —
                                    // the ring is the card's primary signal, so
                                    // it thickens even as the wheel shrinks (§9).
                                    height: 76,
                                    width: 76,
                                    child: TweenAnimationBuilder<double>(
                                      // Sweep from 0 only on the first app-open;
                                      // afterwards jump straight to the value so
                                      // it doesn't re-animate on every tab return.
                                      tween: Tween(
                                        begin: _sweepsPlayed
                                            ? _currentOverall / 100
                                            : 0,
                                        end: _currentOverall / 100,
                                      ),
                                      duration: _sweepsPlayed
                                          ? Duration.zero
                                          : AppMotion.duration(
                                              context,
                                              AppMotion.slow,
                                            ),
                                      curve: AppMotion.enter,
                                      onEnd: () => _sweepsPlayed = true,
                                      builder: (context, value, _) =>
                                          CircularProgressIndicator(
                                            value: value,
                                            backgroundColor: theme.dividerColor,
                                            color: statusColor,
                                            strokeWidth: 13,
                                          ),
                                    ),
                                  ),
                                  Icon(
                                    // Shrunk to clear the thicker ring: inner
                                    // clear = 76 - 2*13 = 50 (§9).
                                    isSafe
                                        ? Icons.check_rounded
                                        : Icons.close_rounded,
                                    color: statusColor,
                                    size: 28,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_totalLecturesOverall > 0) ...[
                            const SizedBox(height: AppDimens.space12),
                            _InsightFooter(
                              isSafe: overallInsight['isSafe'] as bool,
                              text: overallInsight['text'] as String,
                              // The lecture count is the number you act on, so
                              // it carries the status colour while the sentence
                              // around it stays body text.
                              highlight: (overallInsight['isSafe'] as bool)
                                  ? overallInsight['skips'] as int?
                                  : overallInsight['attends'] as int?,
                            ),
                          ],
                          if (_weekSkipPlan != null) ...[
                            const SizedBox(height: AppDimens.space16),
                            Divider(height: 1, color: theme.dividerColor),
                            const SizedBox(height: AppDimens.space12),
                            _SkippableDaysSection(
                              plan: _weekSkipPlan!,
                              subjectNames: _subjectNames,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppDimens.space24),
                  Text('Your Subjects', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppDimens.space12),

                  // ── Subject list ─────────────────────────────────────
                  if (_subjects.isEmpty)
                    EmptyState(
                      icon: Icons.book_outlined,
                      title: 'No subjects yet',
                      message: 'No subjects added for this semester yet.',
                    )
                  else
                    for (int i = 0; i < _subjects.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppDimens.space12),
                      _buildSubjectCard(_subjects[i]),
                    ],

                  const SizedBox(height: AppDimens.space16),
                  CalloutBox(
                    kind: CalloutKind.info,
                    icon: Icons.info_outline_rounded,
                    title: 'Attendance Disclaimer',
                    message:
                        'This app tracks attendance based on your SAP PDF report. '
                        'Always verify with your official college records. '
                        'AttendEase is not responsible for any discrepancies.',
                  ),
                  const SizedBox(height: AppDimens.space24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectCard(Subject subject) {
    final stat = _attendanceStats[subject.id] ?? {'attended': 0, 'total': 0};
    final double percent = stat['total'] == 0
        ? 0.0
        : ((stat['attended']! / stat['total']!) * 100);
    return _SubjectCard(
      subject: subject,
      percent: percent,
      attended: stat['attended']!,
      total: stat['total']!,
      insight: _getPredictiveInsight(
        stat['attended']!,
        stat['total']!,
        subject.requiredPercent,
      ),
    );
  }
}

// ── Private widgets ──────────────────────────────────────────────────────────

/// The "Semester 5" pill at the top of the overall card.
///
/// Blue, not a status colour: which semester you are looking at is navigation
/// context, not a verdict. Green or red here would read as a judgement on the
/// semester itself and compete with the ring, which is the one thing on this
/// card that should carry status colour.
class _SemesterBadge extends StatelessWidget {
  const _SemesterBadge({required this.semester});

  final int semester;

  /// The app's system blue, the same one the nav bar and buttons use.
  static const _accent = AppTheme.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.school_rounded, size: 16, color: _accent),
          const SizedBox(width: AppDimens.space6),
          Text(
            'Semester $semester',
            style: const TextStyle(
              color: _accent,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline verdict under the percentage: "You can safely skip the next
/// **15** lectures."
///
/// An outlined box on the card's own background rather than a filled banner.
/// The status colour arrives through the border, a barely-there fill, and the
/// one number that matters — a fully tinted block at this size competes with
/// the ring for the eye.
class _InsightFooter extends StatelessWidget {
  const _InsightFooter({
    required this.isSafe,
    required this.text,
    this.highlight,
  });
  final bool isSafe;
  final String text;

  /// The lecture count inside [text] to pick out in the status colour. Null (or
  /// a value not present in the string) renders the sentence uniformly, so a
  /// wording change can never produce a mangled highlight.
  final int? highlight;

  /// Splits [text] around the first standalone occurrence of [highlight] so the
  /// number can carry its own style.
  ///
  /// Word-boundary matched: without it, "skip the next 1 lecture" would light
  /// up the `1` inside a nearby "15", and "reach 75%" would match a target of 7.
  List<InlineSpan> _spans(Color accent, Color base) {
    final n = highlight;
    if (n == null || n <= 0) return [TextSpan(text: text)];
    final match = RegExp(r'(?<!\d)' + n.toString() + r'(?!\d)').firstMatch(text);
    if (match == null) return [TextSpan(text: text)];
    return [
      TextSpan(text: text.substring(0, match.start)),
      TextSpan(
        text: match.group(0),
        style: TextStyle(color: accent, fontWeight: FontWeight.w800),
      ),
      TextSpan(text: text.substring(match.end)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final color = isSafe ? c.success : c.danger;
    final baseColor = theme.textTheme.bodyLarge?.color ?? color;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text.rich(
        TextSpan(children: _spans(color, baseColor)),
        style: TextStyle(
          color: baseColor.withValues(alpha: 0.7),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }
}

/// A Mon→Sun strip marking each day of the current week as skippable or not,
/// shown under the overall attendance card.
///
/// A fixed 7-column `Row` of `Expanded` children rather than a `Wrap` or grid:
/// a week is exactly seven items and must stay on one line, or the Mon→Sun
/// mental map — the whole point of the strip — breaks. Nothing has a fixed
/// width, so the columns self-scale down to very narrow screens with no
/// breakpoint logic.
class _SkippableDaysSection extends StatelessWidget {
  const _SkippableDaysSection({
    required this.plan,
    required this.subjectNames,
  });

  final WeekSkipPlan plan;
  final Map<int, String> subjectNames;

  /// Weekday names, Mon → Sun. Hardcoded rather than formatted from each date
  /// so the strip's column order is fixed by construction: the plan's `days` is
  /// contractually Mon→Sun, and a locale whose `EEE` starts the week elsewhere
  /// must not silently relabel these columns.
  static const _labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  /// `Wed & Fri are free if you attend the rest of the week.`
  ///
  /// The conditional wording is not optional: every verdict here assumes the
  /// non-green days are attended as planned, and a "free day" that isn't is the
  /// most costly error this feature can make.
  String _summary() {
    final free = plan.skippableDays
        .map((d) => DateFormat('EEE').format(d.date))
        .toList();
    if (free.isEmpty) {
      return plan.isNextWeek
          ? 'No full days off next week — keep attending.'
          : 'No full days off this week — keep attending.';
    }
    final names = free.length == 1
        ? free.first
        : '${free.take(free.length - 1).join(', ')} & ${free.last}';
    final verb = free.length == 1 ? 'is' : 'are';
    return '$names $verb free if you attend the rest of the week.';
  }

  /// The verdict explanation shown in the day's popover. Pure string builder —
  /// the presentation (an anchored [GlassPopover]) lives in [_DayCell].
  String _message(WeekSkipDay day) {
    final when = DateFormat('EEE').format(day.date);
    switch (day.verdict) {
      case SkipVerdict.unsafe:
        final subject = day.blockingSubjectId == null
            ? null
            : subjectNames[day.blockingSubjectId];
        return subject == null
            ? 'Skipping $when drops your overall attendance below target.'
            : 'Skipping $when drops $subject below target.';
      case SkipVerdict.skippable:
        final n = day.lectureCount;
        return '$when is free — $n lecture${n == 1 ? '' : 's'} off, '
            'if you attend the rest of the week.';
      case SkipVerdict.noClasses:
        return 'No classes on $when.';
      case SkipVerdict.past:
        return '$when has already passed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Blue like the semester badge: this is a section heading, and the
            // verdicts it introduces are what carry green and red.
            const Icon(
              Icons.event_available_rounded,
              size: 20,
              color: AppTheme.primaryBlue,
            ),
            const SizedBox(width: AppDimens.space8),
            Expanded(
              child: Text(
                plan.isNextWeek
                    ? 'Days you can skip · next week'
                    : 'Days you can skip · this week',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space12),
        Row(
          children: [
            for (var i = 0; i < plan.days.length; i++)
              Expanded(
                // The gutter lives inside each Expanded rather than as
                // SizedBox separators, so all seven columns stay
                // mathematically equal at any width. Halved on the two outer
                // edges so the strip sits flush with the card's padding
                // instead of inset by a half-gutter on each side.
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : AppDimens.space4,
                    right: i == plan.days.length - 1 ? 0 : AppDimens.space4,
                  ),
                  child: _DayCell(
                    day: plan.days[i],
                    label: _labels[i],
                    isToday: plan.days[i].date == today,
                    blockingSubject:
                        subjectNames[plan.days[i].blockingSubjectId],
                    message: _message(plan.days[i]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),
        // The glyphs are the only thing distinguishing the three verdicts for a
        // colourblind reader, so they need naming somewhere. One line with `|`
        // dividers, exactly as in the reference; FittedBox scales the whole row
        // down on narrow screens rather than wrapping or truncating the key.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegendItem(
                glyph: Icons.check_circle_outline_rounded,
                label: 'You can skip',
                color: c.success,
              ),
              _legendDivider(theme),
              _LegendItem(
                glyph: Icons.cancel_outlined,
                label: 'Attend to stay on track',
                color: theme.textTheme.bodySmall?.color ?? c.danger,
              ),
              _legendDivider(theme),
              _LegendItem(
                glyph: Icons.remove_circle_outline_rounded,
                label: 'Not in session',
                color: theme.textTheme.bodySmall?.color ?? c.danger,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDivider(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space10),
        child: Text(
          '|',
          style: TextStyle(color: theme.dividerColor, fontSize: 14),
        ),
      );
}

/// One "glyph — meaning" pair in the week strip's key.
class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.glyph,
    required this.label,
    required this.color,
  });

  final IconData glyph;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(glyph, size: 15, color: color),
        const SizedBox(width: AppDimens.space6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// One day of the week strip: a tile holding the weekday name over the date
/// number, with the verdict glyph below it.
///
/// Colours come from `theme.textTheme` and the status tokens, since the strip
/// now sits directly on the card background rather than on a green container.
class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.isToday,
    required this.blockingSubject,
    required this.message,
  });

  final WeekSkipDay day;

  /// Three-letter weekday name — `MON`. Unambiguous on its own, unlike the
  /// single initials this replaced (T/T and S/S relied on column position).
  final String label;

  final bool isToday;
  final String? blockingSubject;

  /// The verdict explanation shown in the popover anchored to this day.
  final String message;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  /// Measures the square date tile so the popover anchors directly under it.
  final GlobalKey _tileKey = GlobalKey();

  /// The live popover, or null when closed. A plain [OverlayEntry] that just
  /// fades in place below the date — it does not expand or morph.
  OverlayEntry? _popover;

  @override
  void didUpdateWidget(covariant _DayCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A week refresh can change this cell's verdict/message while its popover
    // is open; drop the stale bubble rather than leave wrong text floating.
    if (oldWidget.message != widget.message) _removePopover();
  }

  @override
  void dispose() {
    _removePopover();
    super.dispose();
  }

  void _removePopover() {
    _popover?.remove();
    _popover = null;
  }

  void _togglePopover() {
    if (_popover != null) {
      _removePopover();
      return;
    }
    final tileBox = _tileKey.currentContext?.findRenderObject() as RenderBox?;
    if (tileBox == null || !tileBox.hasSize) return;
    final overlay = Overlay.of(context);

    final tilePos = tileBox.localToGlobal(Offset.zero);
    final tileSize = tileBox.size;
    final screen = MediaQuery.sizeOf(context);

    const bubbleWidth = 240.0;
    const edgePad = 8.0;
    const gap = 6.0;

    final targetCenterX = tilePos.dx + tileSize.width / 2;
    final top = tilePos.dy + tileSize.height + gap;
    // Center the bubble under the tile, then clamp it on-screen. maxLeft can
    // fall below edgePad on a very narrow screen, so guard lo <= hi.
    final maxLeft = screen.width - edgePad - bubbleWidth;
    final left = maxLeft <= edgePad
        ? edgePad
        : (targetCenterX - bubbleWidth / 2).clamp(edgePad, maxLeft);
    // Keep the beak pointing at the tile after clamping, clear of the corners.
    final beakCenterX = (targetCenterX - left).clamp(16.0, bubbleWidth - 16.0);

    _popover = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap anywhere to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removePopover,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _SkipPopoverBubble(
              width: bubbleWidth,
              beakCenterX: beakCenterX,
              message: widget.message,
            ),
          ),
        ],
      ),
    );
    overlay.insert(_popover!);
  }

  String _semanticLabel() {
    final day = widget.day;
    final date = DateFormat('EEEE d MMMM').format(day.date);
    switch (day.verdict) {
      case SkipVerdict.skippable:
        final n = day.lectureCount;
        return '$date, can be skipped, '
            '$n lecture${n == 1 ? '' : 's'}';
      case SkipVerdict.unsafe:
        return widget.blockingSubject == null
            ? '$date, not safe to skip, overall attendance would drop below target'
            : '$date, not safe to skip, ${widget.blockingSubject} would drop below target';
      case SkipVerdict.noClasses:
        return '$date, no classes';
      case SkipVerdict.past:
        return '$date, already passed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final on = theme.textTheme.bodyLarge?.color ?? c.success;
    final day = widget.day;
    final label = widget.label;
    final isToday = widget.isToday;

    final bool isSkippable = day.verdict == SkipVerdict.skippable;
    final bool isPast = day.verdict == SkipVerdict.past;

    // `past` fades via the text/border alpha rather than an Opacity wrapper, so
    // the tile border keeps its own alpha budget independent of the text.
    final double contentAlpha = isPast
        ? 0.35
        : day.verdict == SkipVerdict.noClasses
        ? 0.5
        : 1.0;

    // Skippable days are outlined in green with a whisper of fill; everything
    // else is a plain hairline box, exactly as in the reference.
    final Color fill = isSkippable
        ? c.success.withValues(alpha: 0.10)
        : Colors.transparent;
    final Color border = isSkippable
        ? c.success
        : on.withValues(alpha: isPast ? 0.10 : 0.18);
    final Color dateColor = isSkippable
        ? c.success
        : on.withValues(alpha: contentAlpha);

    // A verdict that rests on a not-yet-happened day going as planned is
    // hairline; one resting only on recorded facts is solid.
    final double borderWidth = day.dependsOnFuture && isSkippable ? 0.8 : 1.2;

    // Circled glyphs matching the legend. Past days show a faded ✗ so the
    // glyph row is never empty and the strip baseline stays even.
    final IconData glyph = switch (day.verdict) {
      SkipVerdict.skippable => Icons.check_circle_outline_rounded,
      SkipVerdict.unsafe || SkipVerdict.past => Icons.cancel_outlined,
      SkipVerdict.noClasses => Icons.remove_circle_outline_rounded,
    };

    return Semantics(
      label: _semanticLabel(),
      button: true,
      child: GestureDetector(
        onTap: _togglePopover,
        // The whole column is the tap target, not just the tile.
        behavior: HitTestBehavior.opaque,
        // Excludes only the visual children — the initial, the date numeral and
        // the glyph, which read as "W / 29 / check mark" and say nothing. It
        // must sit *inside* the GestureDetector so the button stays activatable.
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The tile: weekday name over date number, bordered box.
              // AspectRatio(1) makes it square from the Expanded width.
              // The inner Column must NOT use mainAxisSize.min — that gives
              // children unbounded height and breaks AspectRatio.
              // _tileKey measures this tile so the popover anchors under it.
              AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  key: _tileKey,
                  duration: AppMotion.duration(context, AppMotion.fast),
                  curve: AppMotion.enter,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: AppDimens.brSm,
                    border: Border.all(color: border, width: borderWidth),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: isSkippable
                              ? c.success
                              : on.withValues(alpha: isPast ? 0.35 : 0.55),
                        ),
                      ),
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        '${day.date.day}',
                        style: TextStyle(
                          fontSize: 16,
                          // "You are here", carried by weight alone. A ring or
                          // dash would nest a second outline inside the green
                          // skippable border and read as one thick smudge.
                          fontWeight: isToday
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: dateColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space4),
              Icon(
                glyph,
                size: 14,
                color: isSkippable
                    ? c.success
                    : on.withValues(alpha: contentAlpha * 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A static bubble with an upward beak, shown below a day tile.
///
/// Deliberately plain: it fades in place and does not expand or morph. Colours
/// are theme-adaptive — the app's card surface and border — so it reads as a
/// small card in both light and dark themes. The fill, border and beak are
/// drawn as one unioned path so the outline runs continuously around the beak
/// with no seam across its base.
class _SkipPopoverBubble extends StatelessWidget {
  const _SkipPopoverBubble({
    required this.width,
    required this.beakCenterX,
    required this.message,
  });

  final double width;

  /// Horizontal position (from the bubble's left edge) the beak points from.
  final double beakCenterX;
  final String message;

  static const double _beakW = 16;
  static const double _beakH = 8;
  static const double _borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final Color bg = theme.cardColor;
    final Color fg = theme.textTheme.bodyMedium?.color ?? bg;

    return TweenAnimationBuilder<double>(
      duration: AppMotion.duration(context, AppMotion.fast),
      curve: AppMotion.enter,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: SizedBox(
        width: width,
        child: CustomPaint(
          painter: _PopoverPainter(
            fill: bg,
            border: c.cardBorder,
            borderWidth: _borderWidth,
            radius: AppDimens.radiusMd,
            beakCenterX: beakCenterX,
            beakWidth: _beakW,
            beakHeight: _beakH,
          ),
          // Top inset leaves room for the beak; the rest is the text padding.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.space12,
              _beakH + AppDimens.space10,
              AppDimens.space12,
              AppDimens.space10,
            ),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the popover silhouette — a rounded rect body with an upward beak —
/// as a single unioned path, then fills, shadows and strokes it so the border
/// is continuous and there is no seam where the beak meets the body.
class _PopoverPainter extends CustomPainter {
  const _PopoverPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.radius,
    required this.beakCenterX,
    required this.beakWidth,
    required this.beakHeight,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final double radius;
  final double beakCenterX;
  final double beakWidth;
  final double beakHeight;

  Path _buildPath(Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, beakHeight, size.width, size.height - beakHeight),
          Radius.circular(radius),
        ),
      );
    // Base dips 0.5px into the body so the union merges cleanly.
    final beak = Path()
      ..moveTo(beakCenterX, 0)
      ..lineTo(beakCenterX - beakWidth / 2, beakHeight + 0.5)
      ..lineTo(beakCenterX + beakWidth / 2, beakHeight + 0.5)
      ..close();
    return Path.combine(PathOperation.union, body, beak);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);
    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(_PopoverPainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.radius != radius ||
      old.beakCenterX != beakCenterX ||
      old.beakWidth != beakWidth ||
      old.beakHeight != beakHeight;
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.percent,
    required this.attended,
    required this.total,
    required this.insight,
  });

  final Subject subject;
  final double percent;
  final int attended;
  final int total;
  final Map<String, dynamic> insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final bool isSafe = percent >= subject.requiredPercent;
    final double fraction = total == 0 ? 0.0 : percent / 100;
    final Color color = isSafe ? c.success : c.danger;
    final Color bg = isSafe ? c.successContainer : c.dangerContainer;
    final Color onBg = isSafe ? c.onSuccessContainer : c.onDangerContainer;

    return ContainerTransformAnchor(
      borderRadius: AppDimens.radiusMd,
      child: Pressable(
        borderRadius: AppDimens.brMd,
        onTap: () =>
            context.go('/app/dashboard/subject-detail', extra: subject),
        child: Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppDimens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              // The matching end of this was a Hero flying to
                              // the detail screen's AppBar title. It fought
                              // the container transform, which already
                              // carries the card's contents into place.
                              Expanded(
                                child: Text(
                                  subject.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: AppDimens.space4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: theme.dividerColor,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimens.space8),
                        Text(
                          '${percent.toStringAsFixed(1)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimens.space12),
                    TweenAnimationBuilder<double>(
                      // Fills from empty only on a cold launch — see
                      // [_sweepsPlayed]. On a tab return or a reload the bar
                      // is already at its value on the first frame.
                      tween: Tween(
                        begin: _sweepsPlayed ? fraction : 0.0,
                        end: fraction,
                      ),
                      duration: _sweepsPlayed
                          ? Duration.zero
                          : AppMotion.duration(context, AppMotion.slow),
                      curve: AppMotion.enter,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        color: color,
                        backgroundColor: theme.dividerColor,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '$attended/$total lectures',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: AppDimens.space8),
                        Text(
                          isSafe ? 'Safe' : 'Risk',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
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
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space10,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: AppDimens.rMd,
                      bottomRight: AppDimens.rMd,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSafe
                            ? Icons.lightbulb_outline
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: AppDimens.space6),
                      Expanded(
                        child: Text(
                          insight['text'] as String,
                          style: TextStyle(
                            color: onBg,
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
      ),
    );
  }
}
