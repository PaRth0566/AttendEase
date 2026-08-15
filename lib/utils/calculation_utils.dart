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
/// suffix) and a `status` (`P` / `A` / `NU` / `NC`). NU rows are ignored for the
/// pass/total maths (handled by [attended] / [total]) but are still used to
/// establish the weekly pattern, since an NU means a lecture was conducted.
/// NC rows are excluded because no lecture occurred.
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
  final weekdayDateCount =
      <int, Map<String, int>>{}; // weekday -> date -> count
  DateTime? latest;
  for (final r in history) {
    if (r['status'] == 'NC') continue;
    final base = ((r['date'] as String?) ?? '').split('_').first;
    final dt = DateTime.tryParse(base);
    if (dt == null) continue; // ignore any pseudo/padding dates
    final wd = dt.weekday;
    (weekdayDates[wd] ??= <String>{}).add(base);
    final counts = (weekdayDateCount[wd] ??= <String, int>{});
    counts[base] = (counts[base] ?? 0) + 1;
    if (latest == null || dt.isAfter(latest)) latest = dt;
  }
  if (latest == null) {
    return SkipPlan(
      maxSkips: maxSkips,
      dates: const [],
      countPerDate: const {},
    );
  }

  // A weekday is "active" if the subject recurs there (>= 2 distinct dates) and
  // was seen within the last 3 weeks of history — dropping stale slots from a
  // schedule that shifted earlier in the semester. Lectures-per-day comes from
  // the most recent occurrence, reflecting the current week.
  final recencyCutoff = latest.subtract(const Duration(days: 21));
  final activeWeekdays = <int, int>{}; // weekday -> lectures per occurrence
  weekdayDates.forEach((wd, dates) {
    if (dates.length < 2) return;
    final sorted = dates.toList()..sort();
    final seenRecently = sorted.any(
      (d) => !DateTime.parse(d).isBefore(recencyCutoff),
    );
    if (!seenRecently) return;
    activeWeekdays[wd] = (weekdayDateCount[wd]?[sorted.last] ?? 1).clamp(1, 8);
  });
  if (activeWeekdays.isEmpty) {
    return SkipPlan(
      maxSkips: maxSkips,
      dates: const [],
      countPerDate: const {},
    );
  }

  // Project forward from tomorrow, banking whole days until the skip budget
  // (in lectures) is spent or we exhaust a sensible horizon.
  final dates = <DateTime>[];
  final countPerDate = <DateTime, int>{};
  var cursor = DateTime(
    today.year,
    today.month,
    today.day,
  ).add(const Duration(days: 1));
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

/// Where a single day of the displayed week stands.
enum SkipVerdict {
  /// Safe to miss every lecture that day.
  skippable,

  /// Classes are scheduled, but skipping them drops something below target.
  unsafe,

  /// Nothing scheduled (e.g. Sunday, or a free weekday).
  noClasses,

  /// Classes were scheduled and every one of them is already marked, so there
  /// is nothing left to decide. Distinct from [noClasses]: the day was in
  /// session. Normally today, once attendance has been taken.
  settled,

  /// Earlier this week — already happened, so it isn't on offer.
  past,
}

/// One day of the current-week skip strip.
class WeekSkipDay {
  final DateTime date;

  /// How many lectures fall on this day. Kept in the model even though the
  /// strip doesn't render it — it distinguishes a cheap skip from an expensive
  /// one, which the summary line may want later.
  final int lectureCount;

  final SkipVerdict verdict;

  /// For [SkipVerdict.unsafe]: which subject's target the skip would break.
  /// Null when the *overall* percentage is what fails, or for other verdicts.
  final int? blockingSubjectId;

  /// True when this verdict was reached only by assuming a not-yet-happened
  /// day was attended as planned — i.e. it is conditional on the rest of the
  /// week going as expected, rather than resting purely on recorded facts.
  final bool dependsOnFuture;

  const WeekSkipDay({
    required this.date,
    required this.lectureCount,
    required this.verdict,
    this.blockingSubjectId,
    this.dependsOnFuture = false,
  });
}

/// A Monday→Sunday verdict for every day of the displayed week.
class WeekSkipPlan {
  /// Monday of the displayed week.
  final DateTime weekStart;

  /// Always length 7, Mon → Sun.
  final List<WeekSkipDay> days;

  /// True when the current week was rolled over (Sunday) and this is the
  /// *coming* week.
  final bool isNextWeek;

  const WeekSkipPlan({
    required this.weekStart,
    required this.days,
    required this.isNextWeek,
  });

  Iterable<WeekSkipDay> get skippableDays =>
      days.where((d) => d.verdict == SkipVerdict.skippable);
}

/// The inferred weekly footprint: weekday (1=Mon … 7=Sun) -> the subject ids
/// with a lecture that day, repeated once per lecture.
///
/// Derived purely from conducted history rather than the reusable weekly
/// timetable, so swaps and replacement lectures stay visible. A weekday slot
/// counts only when the subject recurs there (≥2 distinct dates) and was seen
/// within 21 days of that subject's latest record — stale slots from a
/// schedule that shifted mid-semester drop out. Lectures-per-day comes from the
/// most recent *complete* occurrence: [today] is excluded while it is still in
/// progress, since a partially-marked day would undercount the slot. `NC` rows
/// are excluded because no lecture actually happened.
Map<int, List<int>> _inferWeeklySchedule(
  Map<int, List<Map<String, dynamic>>> subjectHistory, {
  DateTime? today,
}) {
  final latestBySubject = <int, DateTime>{};
  final weekdayDates = <int, Map<int, Set<String>>>{};
  final weekdayCounts = <int, Map<int, Map<String, int>>>{};
  for (final entry in subjectHistory.entries) {
    for (final record in entry.value) {
      if (record['status'] == 'NC') continue;
      final base = ((record['date'] as String?) ?? '').split('_').first;
      final date = DateTime.tryParse(base);
      if (date == null) continue;
      final sid = entry.key;
      if (latestBySubject[sid] == null || date.isAfter(latestBySubject[sid]!)) {
        latestBySubject[sid] = date;
      }
      final datesBySubject = weekdayDates[date.weekday] ??=
          <int, Set<String>>{};
      (datesBySubject[sid] ??= <String>{}).add(base);
      final countsBySubject = weekdayCounts[date.weekday] ??=
          <int, Map<String, int>>{};
      final counts = countsBySubject[sid] ??= <String, int>{};
      counts[base] = (counts[base] ?? 0) + 1;
    }
  }

  final schedule = <int, List<int>>{};
  for (final weekdayEntry in weekdayDates.entries) {
    for (final subjectEntry in weekdayEntry.value.entries) {
      final latest = latestBySubject[subjectEntry.key];
      final dates = subjectEntry.value;
      if (latest == null || dates.length < 2) continue;
      final recentCutoff = latest.subtract(const Duration(days: 21));
      if (!dates.any((d) => !DateTime.parse(d).isBefore(recentCutoff))) {
        continue;
      }
      // Lectures-per-day comes from the most recent *complete* occurrence, so
      // today is skipped while it is still in progress. Reading the count off a
      // partially-marked today undercounts the slot: a twice-on-Monday subject
      // with only its first lecture recorded looked like a once-on-Monday
      // subject, that single slot was then retired as already settled, and the
      // outstanding second lecture disappeared from the week's plan.
      //
      // Falls back to the most recent day when today is the only occurrence —
      // one sample is still better than assuming a single lecture.
      final sortedDates = dates.toList()..sort();
      final todayKey = today == null ? null : _dateKey(today);
      final mostRecent = sortedDates.lastWhere(
        (d) => d != todayKey,
        orElse: () => sortedDates.last,
      );
      final count =
          weekdayCounts[weekdayEntry.key]![subjectEntry.key]![mostRecent] ?? 1;
      schedule
          .putIfAbsent(weekdayEntry.key, () => <int>[])
          .addAll(
            List<int>.filled(count.clamp(1, 8).toInt(), subjectEntry.key),
          );
    }
  }
  return schedule;
}

/// Two-digit zero padding for a `yyyy-MM-dd` key.
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Builds a Monday→Sunday verdict for every day of the current week.
///
/// A day is [SkipVerdict.skippable] if being absent for *every* lecture that
/// day — on top of skipping all earlier days already marked skippable this
/// week — keeps every subject at or above its own required percentage AND the
/// overall attendance at or above [overallRequired].
///
/// The accounting is **cumulative**: two green days mean "you can take both
/// off", not two independent offers that quietly conflict. Unlike the older
/// forward-running projection, an unsafe day does *not* abort the walk — its
/// hypothetical is rolled back and the remaining days are still evaluated, so a
/// cheap Friday can show green after an expensive Wednesday shows red.
///
/// Days earlier than [today] are marked [SkipVerdict.past] and not evaluated.
/// No extra bookkeeping is needed for them: their real outcomes are already
/// baked into [subjectStats], so a Monday you actually bunked automatically
/// makes Saturday's verdict harsher.
///
/// **Today:** lectures already marked `P`/`A`/`NC` are retired from today's
/// hypothetical — the first two are already inside [subjectStats] and `NC` never
/// happened. If that retires every lecture, today is [SkipVerdict.settled], not
/// [SkipVerdict.noClasses]: the day was in session, there is just nothing left
/// to decide.
///
/// **Rollover:** on Sunday the whole current week is spent (Sunday is a holiday
/// in this app), so the *coming* week is returned instead and [
/// WeekSkipPlan.isNextWeek] is true.
///
/// Returns null when no weekly schedule can be inferred at all (a new user with
/// no history) — there is nothing meaningful to show, as distinct from a week
/// where simply no day is skippable.
///
/// [subjectStats] maps subjectId -> {'attended', 'total'}.
/// [subjectRequired] maps subjectId -> required percent (e.g. 75.0).
/// [subjectHistory] contains the persisted records for each subject.
WeekSkipPlan? computeWeekSkipPlan({
  required Map<int, Map<String, int>> subjectStats,
  required Map<int, double> subjectRequired,
  required Map<int, List<Map<String, dynamic>>> subjectHistory,
  required double overallRequired,
  required DateTime today,
}) {
  final schedule = _inferWeeklySchedule(subjectHistory, today: today);
  if (schedule.isEmpty) return null;

  final todayDate = DateTime(today.year, today.month, today.day);

  // Monday of this week; on Sunday roll over to the coming week, since the
  // current one has nothing left to offer.
  final isNextWeek = todayDate.weekday == DateTime.sunday;
  final weekStart = todayDate
      .subtract(Duration(days: todayDate.weekday - 1))
      .add(Duration(days: isNextWeek ? 7 : 0));

  // Running hypothetical totals (start from the real current state).
  final attended = <int, int>{};
  final total = <int, int>{};
  for (final entry in subjectStats.entries) {
    attended[entry.key] = entry.value['attended'] ?? 0;
    total[entry.key] = entry.value['total'] ?? 0;
  }

  /// Per-subject count of today's lectures that are already settled, so they
  /// aren't weighed a second time in the hypothetical.
  ///
  /// Only `P`/`A` (already inside [subjectStats], which counts exactly those two)
  /// and `NC` (the lecture never happened, so it carries no attendance weight)
  /// settle a slot. `NU` is deliberately excluded: it means conducted but not yet
  /// marked, so it is still an unaccounted lecture the projection must weigh.
  ///
  /// Counted rather than a per-subject flag: on a day with two lectures of the
  /// same subject, marking one must retire one slot, not both.
  final settledToday = <int, int>{};
  final todayKey = _dateKey(todayDate);
  for (final entry in subjectHistory.entries) {
    for (final record in entry.value) {
      final base = ((record['date'] as String?) ?? '').split('_').first;
      if (base != todayKey) continue;
      final status = record['status'] as String?;
      if (status != 'P' && status != 'A' && status != 'NC') continue;
      settledToday[entry.key] = (settledToday[entry.key] ?? 0) + 1;
    }
  }

  /// Returns the offending subject id, or -1 for an overall-percentage
  /// failure, or null when everything still holds.
  int? firstBreach(List<int> lectures) {
    for (final sid in lectures) {
      final t = total[sid] ?? 0;
      if (t == 0) continue; // nothing recorded yet -> don't block on it
      final req = subjectRequired[sid] ?? overallRequired;
      if ((attended[sid] ?? 0) / t * 100 < req - 1e-9) return sid;
    }
    var a = 0, t = 0;
    total.forEach((sid, tt) {
      a += attended[sid] ?? 0;
      t += tt;
    });
    if (t != 0 && (a / t) * 100 < overallRequired - 1e-9) return -1;
    return null;
  }

  final days = <WeekSkipDay>[];
  // Once a not-yet-happened day has been banked into the running totals, every
  // later verdict is conditional on that day going as assumed.
  var consumedFutureDay = false;

  for (var i = 0; i < 7; i++) {
    final date = weekStart.add(Duration(days: i));

    if (date.isBefore(todayDate)) {
      days.add(
        WeekSkipDay(
          date: date,
          lectureCount: 0,
          verdict: SkipVerdict.past,
        ),
      );
      continue;
    }

    // A one-off future holiday isn't knowable from weekday-pattern history, so
    // a declared-holiday Friday still shows as a class day. That errs
    // conservative (fewer skips offered than reality), which is the safe way
    // to be wrong.
    var lectures = schedule[date.weekday] ?? const <int>[];

    // Today's already-settled lectures are accounted for already; re-adding
    // them would double-count. Retires one slot per settled record so a
    // twice-a-day subject with one lecture marked keeps the other in play.
    var settledCount = 0;
    if (date == todayDate && settledToday.isNotEmpty) {
      final remaining = {...settledToday};
      final kept = <int>[];
      for (final sid in lectures) {
        final left = remaining[sid] ?? 0;
        if (left > 0) {
          remaining[sid] = left - 1;
          settledCount++;
        } else {
          kept.add(sid);
        }
      }
      lectures = kept;
    }

    if (lectures.isEmpty) {
      days.add(
        WeekSkipDay(
          date: date,
          lectureCount: 0,
          // A day whose lectures are all already marked *did* have classes —
          // calling it "not in session" would be a plain falsehood, and on
          // today that is the common case rather than an edge one. There is
          // nothing left to offer, so it is not skippable either.
          verdict: settledCount > 0
              ? SkipVerdict.settled
              : SkipVerdict.noClasses,
        ),
      );
      continue;
    }

    // Tentatively mark every lecture that day absent (total+1, attended+0).
    final snapshot = {...total};
    for (final sid in lectures) {
      total[sid] = (total[sid] ?? 0) + 1;
    }
    final breach = firstBreach(lectures);

    if (breach == null) {
      days.add(
        WeekSkipDay(
          date: date,
          lectureCount: lectures.length,
          verdict: SkipVerdict.skippable,
          dependsOnFuture: consumedFutureDay,
        ),
      );
      // Keep the hypothetical — later days are judged as if this one is off.
      if (date.isAfter(todayDate)) consumedFutureDay = true;
    } else {
      total
        ..clear()
        ..addAll(snapshot);
      days.add(
        WeekSkipDay(
          date: date,
          lectureCount: lectures.length,
          verdict: SkipVerdict.unsafe,
          blockingSubjectId: breach == -1 ? null : breach,
          dependsOnFuture: consumedFutureDay,
        ),
      );
    }
  }

  return WeekSkipPlan(
    weekStart: weekStart,
    days: days,
    isNextWeek: isNextWeek,
  );
}
