import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/container_transform.dart';
import '../../utils/calculation_utils.dart';
import '../root/tab_page_state.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeleton.dart';

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

class DashboardScreenState extends TabPageState<DashboardScreen> {
  final SubjectDao _subjectDao = SubjectDao();
  final AttendanceDao _attendanceDao = AttendanceDao();
  final TimetableDao _timetableDao = TimetableDao();

  List<Subject> _subjects = [];
  Map<int, Map<String, int>> _attendanceStats = {};

  double _currentOverall = 0.0;
  double _requiredTarget = 75.0;
  int _activeSemester = 1;

  int _totalAttendedOverall = 0;
  int _totalLecturesOverall = 0;
  int _currentStreak = 0;

  List<SkippableDay> _skippableDays = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  Future<void> reloadData() => _loadDashboardData();

  Future<void> _loadDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _requiredTarget = prefs.getDouble('overall_required_attendance') ?? 75.0;
      _activeSemester = prefs.getInt('semester') ?? 1;

      if (widget.overrideSubjects != null && widget.overrideStats != null) {
        _subjects = widget.overrideSubjects!;
        _attendanceStats = widget.overrideStats!;
        _currentStreak = 0;
      } else {
        _subjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
        _attendanceStats = await _attendanceDao.getAttendanceStats(_activeSemester);
        _currentStreak = await _attendanceDao.getCurrentStreak(_activeSemester);
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

      // Which whole upcoming days can be fully skipped while staying on target.
      // Skipped when using override stats (web preview) — no timetable there.
      if (widget.overrideSubjects == null) {
        try {
          final weekly = await _timetableDao.getWeeklyTimetable(_activeSemester);
          _skippableDays = computeSkippableDays(
            subjectStats: _attendanceStats,
            subjectRequired: {
              for (final s in _subjects)
                if (s.id != null) s.id!: s.requiredPercent,
            },
            weeklyTimetable: weekly,
            overallRequired: _requiredTarget,
            today: DateTime.now(),
          );
        } catch (e) {
          debugPrint('Skippable-days calc error: $e');
          _skippableDays = [];
        }
      } else {
        _skippableDays = [];
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncAndReload() async {
    await CloudSyncService().syncBidirectional();
    await _loadDashboardData();
  }

  Map<String, dynamic> _getPredictiveInsight(int attended, int total, double requiredPercent) {
    if (total == 0) return {'text': 'No classes recorded yet.', 'isSafe': true, 'skips': 0};
    double reqFrac = requiredPercent / 100;
    double currentPercent = (attended / total) * 100;
    if (currentPercent >= requiredPercent) {
      int skips = ((attended / reqFrac) - total).floor();
      if (skips <= 0) {
        return {'text': 'On track, but you cannot skip the next lecture.', 'isSafe': true, 'skips': 0};
      }
      return {
        'text': 'You can safely skip the next $skips lecture${skips > 1 ? 's' : ''}.',
        'isSafe': true,
        'skips': skips,
      };
    } else {
      int attends = (((reqFrac * total) - attended) / (1 - reqFrac)).ceil();
      return {
        'text': 'Attend the next $attends lecture${attends > 1 ? 's' : ''} to reach ${requiredPercent.toStringAsFixed(0)}%.',
        'isSafe': false,
        'attends': attends,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Dashboard')),
        body: const SkeletonList(count: 4, padding: EdgeInsets.all(AppDimens.space16)),
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
        actions: [
          if (_currentStreak >= 3)
            Padding(
              padding: const EdgeInsets.only(right: AppDimens.space16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.warningContainer,
                    borderRadius: AppDimens.brXl,
                    border: Border.all(color: c.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_currentStreak',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: c.onWarningContainer,
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
                AppDimens.space16,
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
                  Text(
                    'Semester $_activeSemester Overview',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppDimens.space16),

                  // ── Overall attendance card ──────────────────────────
                  Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppDimens.space20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Overall Attendance', style: theme.textTheme.bodyMedium),
                                  const SizedBox(height: AppDimens.space8),
                                  Text(
                                    '${_currentOverall.toStringAsFixed(1)}%',
                                    style: theme.textTheme.displaySmall?.copyWith(
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  const SizedBox(height: AppDimens.space8),
                                  Text(
                                    'Target: ${_requiredTarget.toStringAsFixed(1)}%',
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    height: 70,
                                    width: 70,
                                    child: TweenAnimationBuilder<double>(
                                      // Sweep from 0 only on the first app-open;
                                      // afterwards jump straight to the value so
                                      // it doesn't re-animate on every tab return.
                                      tween: Tween(
                                        begin: _sweepsPlayed ? _currentOverall / 100 : 0,
                                        end: _currentOverall / 100,
                                      ),
                                      duration: _sweepsPlayed
                                          ? Duration.zero
                                          : AppMotion.duration(context, AppMotion.slow),
                                      curve: AppMotion.enter,
                                      onEnd: () => _sweepsPlayed = true,
                                      builder: (context, value, _) => CircularProgressIndicator(
                                        value: value,
                                        backgroundColor: theme.dividerColor,
                                        color: statusColor,
                                        strokeWidth: 8,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isSafe ? Icons.check_rounded : Icons.close_rounded,
                                    color: statusColor,
                                    size: 34,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_totalLecturesOverall > 0)
                          _InsightFooter(
                            isSafe: overallInsight['isSafe'] as bool,
                            text: overallInsight['text'] as String,
                            roundBottom: _skippableDays.isEmpty,
                          ),
                        if (_skippableDays.isNotEmpty)
                          _SkippableDaysSection(days: _skippableDays),
                      ],
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
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _subjects.length,
                      itemBuilder: (_, i) {
                        final subject = _subjects[i];
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
                      },
                    ),

                  const SizedBox(height: AppDimens.space24),
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
}

// ── Private widgets ──────────────────────────────────────────────────────────

class _InsightFooter extends StatelessWidget {
  const _InsightFooter({required this.isSafe, required this.text, this.roundBottom = true});
  final bool isSafe;
  final String text;
  final bool roundBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final color = isSafe ? c.success : c.danger;
    final bg = isSafe ? c.successContainer : c.dangerContainer;
    final onBg = isSafe ? c.onSuccessContainer : c.onDangerContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.space20, vertical: AppDimens.space12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: roundBottom
            ? const BorderRadius.only(
                bottomLeft: AppDimens.rMd,
                bottomRight: AppDimens.rMd,
              )
            : BorderRadius.zero,
      ),
      child: Row(
        children: [
          Icon(
            isSafe ? Icons.lightbulb_outline : Icons.warning_amber_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: onBg, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists upcoming whole days that can be safely skipped, shown under the
/// overall attendance card.
class _SkippableDaysSection extends StatelessWidget {
  const _SkippableDaysSection({required this.days});
  final List<SkippableDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space20,
        vertical: AppDimens.space12,
      ),
      decoration: BoxDecoration(
        color: c.successContainer,
        borderRadius: const BorderRadius.only(
          bottomLeft: AppDimens.rMd,
          bottomRight: AppDimens.rMd,
        ),
        border: Border(top: BorderSide(color: c.success.withValues(alpha: 0.25))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_rounded, size: 18, color: c.success),
              const SizedBox(width: AppDimens.space8),
              Text(
                'Days you can fully skip',
                style: TextStyle(
                  color: c.onSuccessContainer,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: days.map((d) {
              final label = DateFormat('EEE, MMM d').format(d.date);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Text(
                  d.lectureCount > 1 ? '$label  ·  ${d.lectureCount} lec' : label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
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

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space12),
      child: ContainerTransformAnchor(
        borderRadius: AppDimens.radiusMd,
        child: Pressable(
          borderRadius: AppDimens.brMd,
          onTap: () => context.go('/app/dashboard/subject-detail', extra: subject),
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
                                Text(
                                  subject.name,
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(width: AppDimens.space4),
                                Icon(Icons.chevron_right_rounded, size: 18, color: theme.dividerColor),
                              ],
                            ),
                          ),
                          Text(
                            '${percent.toStringAsFixed(1)}%',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
                          minHeight: AppDimens.space8,
                          borderRadius: BorderRadius.circular(AppDimens.space8 / 2),
                        ),
                      ),
                      const SizedBox(height: AppDimens.space8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$attended/$total lectures',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            isSafe ? 'Safe' : 'Risk',
                            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
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
                          isSafe ? Icons.lightbulb_outline : Icons.warning_amber_rounded,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: AppDimens.space6),
                        Expanded(
                          child: Text(
                            insight['text'] as String,
                            style: TextStyle(color: onBg, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ),
      ),
    );
  }
}
