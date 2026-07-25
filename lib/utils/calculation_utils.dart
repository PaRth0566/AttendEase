double calculatePercentage(int attended, int total) {
  if (total == 0) return 0.0;
  return (attended / total) * 100;
}

/// The result of a "safe to skip" projection for a single subject.
class SkipPlan {
  /// How many future lectures can be skipped while staying at or above the
  /// required percentage.
  final int maxSkips;

  /// Upcoming calendar dates (soonest first) on which this subject recurs and
  /// which fall within the skip budget.
  final List<DateTime> dates;

  /// How many lectures of this subject fall on each date in [dates].
  final Map<DateTime, int> countPerDate;

  const SkipPlan({
    required this.maxSkips,
    required this.dates,
    required this.countPerDate,
  });

  static const empty = SkipPlan(maxSkips: 0, dates: [], countPerDate: {});
}

/// Works out, for one subject, how many upcoming lectures can be safely skipped
/// and *which days* those are.
///
/// The recurring weekly pattern is derived purely from the subject's own
/// attendance [history] (real, reliable data) rather than any manually
/// configured or globally inferred timetable — so the answer stays correct even
/// when the timetable is empty or approximate.
///
/// [history] items must contain a `date` (`yyyy-MM-dd`, optionally with a `_n`
/// suffix) and a `status` (`P` / `A` / `NU`). NU rows are ignored for the
/// pass/total maths (handled by [attended] / [total]) but are still used to
/// establish the weekly pattern, since an NU means a lecture was scheduled.
SkipPlan computeSkipPlan({
  required List<Map<String, dynamic>> history,
  required int attended,
  required int total,
  required double requiredPercent,
  required DateTime today,
}) {
  if (total == 0) return SkipPlan.empty;

  final reqFrac = requiredPercent / 100;
  if (reqFrac <= 0) return SkipPlan.empty;

  final currentPercent = (attended / total) * 100;
  if (currentPercent < requiredPercent) return SkipPlan.empty;

  // Skipping a lecture leaves `attended` unchanged while `total` grows by 1.
  // Largest x with attended / (total + x) >= reqFrac  ->  attended/reqFrac - total.
  final maxSkips = ((attended / reqFrac) - total).floor();
  if (maxSkips <= 0) return SkipPlan.empty;

  // Build the subject's weekly footprint from its history.
  final weekdayDates = <int, Set<String>>{}; // weekday -> distinct base dates
  final weekdayDateCount = <int, Map<String, int>>{}; // weekday -> date -> count
  DateTime? latest;
  for (final r in history) {
    final base = ((r['date'] as String?) ?? '').split('_').first;
    final dt = DateTime.tryParse(base);
    if (dt == null) continue; // ignore any pseudo/padding dates
    final wd = dt.weekday;
    (weekdayDates[wd] ??= <String>{}).add(base);
    final counts = (weekdayDateCount[wd] ??= <String, int>{});
    counts[base] = (counts[base] ?? 0) + 1;
    if (latest == null || dt.isAfter(latest)) latest = dt;
  }
  if (latest == null) return SkipPlan(maxSkips: maxSkips, dates: const [], countPerDate: const {});

  // A weekday is "active" if the subject recurs there (>= 2 distinct dates) and
  // was seen within the last 3 weeks of history — dropping stale slots from a
  // schedule that shifted earlier in the semester. Lectures-per-day comes from
  // the most recent occurrence, reflecting the current week.
  final recencyCutoff = latest.subtract(const Duration(days: 21));
  final activeWeekdays = <int, int>{}; // weekday -> lectures per occurrence
  weekdayDates.forEach((wd, dates) {
    if (dates.length < 2) return;
    final sorted = dates.toList()..sort();
    final seenRecently =
        sorted.any((d) => !DateTime.parse(d).isBefore(recencyCutoff));
    if (!seenRecently) return;
    activeWeekdays[wd] = (weekdayDateCount[wd]?[sorted.last] ?? 1).clamp(1, 8);
  });
  if (activeWeekdays.isEmpty) {
    return SkipPlan(maxSkips: maxSkips, dates: const [], countPerDate: const {});
  }

  // Project forward from tomorrow, banking whole days until the skip budget
  // (in lectures) is spent or we exhaust a sensible horizon.
  final dates = <DateTime>[];
  final countPerDate = <DateTime, int>{};
  var cursor = DateTime(today.year, today.month, today.day)
      .add(const Duration(days: 1));
  final horizon = cursor.add(const Duration(days: 70));
  var budget = maxSkips;
  while (budget > 0 && cursor.isBefore(horizon) && dates.length < 20) {
    final lectures = activeWeekdays[cursor.weekday];
    if (lectures != null) {
      final take = lectures <= budget ? lectures : budget;
      dates.add(cursor);
      countPerDate[cursor] = take;
      budget -= take;
    }
    cursor = cursor.add(const Duration(days: 1));
  }

  return SkipPlan(maxSkips: maxSkips, dates: dates, countPerDate: countPerDate);
}

/// A single upcoming day that can be fully skipped.
class SkippableDay {
  final DateTime date;
  final int lectureCount; // how many lectures fall on this day
  const SkippableDay({required this.date, required this.lectureCount});
}

/// Works out which upcoming whole days can be safely skipped.
///
/// A day is "skippable" if being absent for *every* lecture that day — on top
/// of skipping all earlier listed days — keeps every subject at or above its
/// own required percentage AND the overall attendance at or above
/// [overallRequired]. The projection is cumulative and greedy: it walks forward
/// from tomorrow and stops at the first class day that would drop any subject
/// (or the overall) below target, since skipping is only "safe" while every
/// constraint still holds.
///
/// [subjectStats] maps subjectId -> {'attended', 'total'}.
/// [subjectRequired] maps subjectId -> required percent (e.g. 75.0).
/// [weeklyTimetable] maps weekday (1=Mon … 7=Sun) -> list of subjectIds that
/// occur that weekday (one entry per lecture, so duplicates are expected).
List<SkippableDay> computeSkippableDays({
  required Map<int, Map<String, int>> subjectStats,
  required Map<int, double> subjectRequired,
  required Map<int, List<int>> weeklyTimetable,
  required double overallRequired,
  required DateTime today,
  int horizonDays = 60,
  int maxDays = 14,
}) {
  // Running hypothetical totals (start from the real current state).
  final attended = <int, int>{};
  final total = <int, int>{};
  for (final entry in subjectStats.entries) {
    attended[entry.key] = entry.value['attended'] ?? 0;
    total[entry.key] = entry.value['total'] ?? 0;
  }

  bool subjectOk(int sid) {
    final t = total[sid] ?? 0;
    if (t == 0) return true; // nothing recorded yet -> don't block on it
    final req = subjectRequired[sid] ?? overallRequired;
    return (attended[sid]! / t) * 100 >= req - 1e-9;
  }

  bool overallOk() {
    var a = 0, t = 0;
    total.forEach((sid, tt) {
      a += attended[sid] ?? 0;
      t += tt;
    });
    if (t == 0) return true;
    return (a / t) * 100 >= overallRequired - 1e-9;
  }

  final result = <SkippableDay>[];
  var cursor = DateTime(today.year, today.month, today.day)
      .add(const Duration(days: 1));
  final horizon = cursor.add(Duration(days: horizonDays));

  while (cursor.isBefore(horizon) && result.length < maxDays) {
    final lectures = weeklyTimetable[cursor.weekday] ?? const <int>[];
    if (lectures.isNotEmpty) {
      // Tentatively mark every lecture that day absent (total+1, attended+0).
      final snapshotTotal = {...total};
      for (final sid in lectures) {
        total[sid] = (total[sid] ?? 0) + 1;
      }
      final stillSafe =
          lectures.every(subjectOk) && overallOk();
      if (stillSafe) {
        result.add(SkippableDay(date: cursor, lectureCount: lectures.length));
      } else {
        // Roll back this day and stop — further days can't make it safer.
        total
          ..clear()
          ..addAll(snapshotTotal);
        break;
      }
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return result;
}
