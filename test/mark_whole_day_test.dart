// The calendar's "All P" / "All A" pills, below the widget layer.
//
// The pills themselves only decide *whether* to ask before writing; every rule
// about what a whole-day mark may touch — and what it must leave alone — lives in
// `planDayMark`, and every claim the UI then makes about the result is derived
// from the rows `upsertAttendanceBatch` leaves behind:
//
//  * "Not Conducted" is not attendance the student owns, so a bulk mark must not
//    invent a Present for a lecture the report says never happened.
//  * The PDF baseline (`original_status`) survives the mark. It exists nowhere
//    else, and the "Manual" badge and the revert-to-NU pill are both derived from
//    it — losing it would silently rewrite what the report is remembered as
//    having said.
//  * A confirmation is owed exactly when an already-marked Present/Absent would
//    be flipped, and not otherwise.
//  * Everything downstream — the month heatmap, the report percentages — falls
//    out of the same rows, so it needs no separate bookkeeping.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int semester = 1;
  // A Monday, so the seeded weekday lectures line up with the date.
  const String monday = '2026-08-10';
  // A subject's second lecture that day is keyed with an `_n` suffix — the case
  // that makes (seed id, date) ambiguous if the suffix is ever dropped.
  const String monday2 = '2026-08-10_2';
  const String nextMonday = '2026-08-17';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AttendanceDao dao;
  // Attendance always lives on the day=0 seed entry, which is why both of a
  // subject's lectures on one day share a timetable_entry_id.
  late int seedA;
  late int seedB;

  setUp(() async {
    // Fresh database per test under a name private to this file — test files run
    // concurrently and sharing the default name makes them contend for one
    // SQLite file. Reset before deleting, and await it: releasing the handle
    // after the file is gone leaves DBHelper caching a dead connection.
    DBHelper.databaseFileName = 'mark_whole_day_test.db';
    await DBHelper.resetForTest();
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await databaseFactory.deleteDatabase(path);

    final db = await DBHelper.instance.database;
    dao = AttendanceDao();

    // Subject A has two Monday lectures, subject B has one — three lectures on
    // the day, which is what makes "the whole day" a meaningful unit.
    final int subjectA = await db.insert('subjects', {
      'name': 'Software Engineering',
      'required_percent': 75.0,
      'semester': semester,
    });
    final int subjectB = await db.insert('subjects', {
      'name': 'Operating Systems',
      'required_percent': 75.0,
      'semester': semester,
    });
    seedA = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectA,
      'lecture_order': 0,
    });
    seedB = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectB,
      'lecture_order': 0,
    });
    for (final order in [1, 2]) {
      await db.insert('timetable', {
        'day_of_week': 1, // Monday
        'subject_id': subjectA,
        'lecture_order': order,
      });
    }
    await db.insert('timetable', {
      'day_of_week': 1,
      'subject_id': subjectB,
      'lecture_order': 3,
    });
  });

  /// The one row stored under [dateKey] for [seedId], or null.
  Future<Map<String, Object?>?> recordAt(int seedId, String dateKey) async {
    final db = await DBHelper.instance.database;
    final rows = await db.query(
      'attendance_records',
      where: 'timetable_entry_id = ? AND date = ?',
      whereArgs: [seedId, dateKey],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// What the calendar's row would show as its "Manual" badge: the tag is
  /// derived, never stored.
  bool isManual(Map<String, Object?> row) =>
      row['original_status'] != null && row['status'] != row['original_status'];

  /// What the heatmap sees for [monday] — the raw statuses it reduces to a tile
  /// colour (all_p / all_a / mixed / all_nu).
  Future<List<String>> heatmapStatuses() async {
    final byDate = await dao.getMonthlyAttendanceStatus(
      '2026-08-01',
      '2026-08-31',
      semester,
    );
    return byDate[monday] ?? const [];
  }

  /// Seeds a day the way an imported SAP report leaves it.
  Future<void> seedImportedDay({
    required String aFirst,
    required String aSecond,
    required String b,
    String date = monday,
  }) async {
    await dao.addImportedReportDates(semester, [date]);
    await dao.upsertAttendance(
      timetableId: seedA,
      date: date,
      status: aFirst,
      source: 'pdf',
      originalStatus: aFirst,
    );
    await dao.upsertAttendance(
      timetableId: seedA,
      date: '${date}_2',
      status: aSecond,
      source: 'pdf',
      originalStatus: aSecond,
    );
    await dao.upsertAttendance(
      timetableId: seedB,
      date: date,
      status: b,
      source: 'pdf',
      originalStatus: b,
    );
  }

  /// Exactly what the calendar does on a pill tap: plan from the day it is
  /// showing, then write the plan.
  Future<DayMarkPlan> markWholeDay(String date, String status) async {
    final plan = planDayMark(await dao.getDaySchedule(date, semester), status);
    await dao.upsertAttendanceBatch(plan.entries);
    return plan;
  }

  group('planDayMark', () {
    test('a day of unmarked lectures needs no confirmation', () async {
      // No imported coverage, so getDaySchedule projects the Monday timetable as
      // virtual "Not Updated" rows — the ordinary case, and the one the pills
      // must write straight through without a dialog.
      final plan = planDayMark(
        await dao.getDaySchedule(monday, semester),
        'P',
      );

      expect(plan.markableCount, 3);
      expect(plan.entries, hasLength(3));
      expect(plan.overwriteCount, 0);
      expect(
        plan.overwritesExistingMarks,
        isFalse,
        reason: 'nothing is being overwritten, so there is nothing to ask about',
      );
    });

    test('a day with marked lectures does need one', () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'A', b: 'A');

      final plan = planDayMark(
        await dao.getDaySchedule(monday, semester),
        'P',
      );

      expect(plan.markableCount, 3);
      expect(
        plan.entries,
        hasLength(2),
        reason: 'the lecture already Present is left alone entirely',
      );
      expect(plan.overwriteCount, 2);
      expect(plan.overwritesExistingMarks, isTrue);
    });

    test('a day already all present plans nothing at all', () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'P', b: 'P');

      final plan = planDayMark(
        await dao.getDaySchedule(monday, semester),
        'P',
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.markableCount, 3);
      expect(
        plan.overwriteCount,
        0,
        reason: 'a no-op write is still a write — it would restamp source and '
            'claim the report\'s values were entered by hand',
      );
    });

    test('not-conducted lectures are counted, never marked', () async {
      await seedImportedDay(aFirst: 'NC', aSecond: 'A', b: 'A');

      final plan = planDayMark(
        await dao.getDaySchedule(monday, semester),
        'P',
      );

      expect(plan.notConductedCount, 1);
      expect(
        plan.markableCount,
        2,
        reason: 'NC is not a lecture whose attendance the student can assert',
      );
      expect(
        plan.entries.map((e) => e.date),
        unorderedEquals(<String>[monday2, monday]),
      );
      expect(
        plan.entries.every((e) => e.status == 'P'),
        isTrue,
      );
    });
  });

  group('marking a whole day', () {
    test('flips every marked lecture and keeps each report baseline', () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'A', b: 'A');

      await markWholeDay(monday, 'P');

      final first = (await recordAt(seedA, monday))!;
      final second = (await recordAt(seedA, monday2))!;
      final third = (await recordAt(seedB, monday))!;

      expect(
        [first['status'], second['status'], third['status']],
        <String>['P', 'P', 'P'],
      );
      expect(
        [
          first['original_status'],
          second['original_status'],
          third['original_status'],
        ],
        <String>['P', 'A', 'A'],
        reason: 'the PDF baseline is stored nowhere else — overwriting it would '
            'quietly rewrite what the report is remembered as having said',
      );
      expect(
        [isManual(first), isManual(second), isManual(third)],
        <bool>[false, true, true],
        reason: 'only the two lectures actually changed away from the report '
            'carry the "Manual" badge',
      );
      expect(
        first['source'],
        'pdf',
        reason: 'the untouched lecture is still the report\'s, not the user\'s',
      );
      expect(second['source'], 'manual');
    });

    test('an unmarked day keeps NU as its baseline once marked', () async {
      // The rows are virtual before the mark: there is no stored baseline for the
      // DAO to preserve, so the plan has to supply NU itself. That baseline is
      // what leaves the row's revert-to-NU pill in place afterwards.
      final before = await dao.getDaySchedule(monday, semester);
      expect(before.every((r) => r['is_virtual'] == 1), isTrue);

      await markWholeDay(monday, 'A');

      final rows = await dao.getDaySchedule(monday, semester);
      expect(rows, hasLength(3));
      expect(
        rows.every((r) => r['record_id'] != null),
        isTrue,
        reason: 'the projected slots are real records now',
      );
      expect(rows.every((r) => r['status'] == 'A'), isTrue);
      expect(
        rows.every((r) => r['original_status'] == 'NU'),
        isTrue,
        reason: 'the report never spoke for this day, so NU stays the baseline — '
            'which is what keeps the revert-to-NU pill available',
      );
      expect(
        rows.every((r) => r['source'] == 'manual'),
        isTrue,
      );
    });

    test('a not-conducted lecture survives the mark untouched', () async {
      await seedImportedDay(aFirst: 'NC', aSecond: 'A', b: 'A');

      await markWholeDay(monday, 'P');

      final nc = (await recordAt(seedA, monday))!;
      expect(nc['status'], 'NC');
      expect(nc['original_status'], 'NC');
      expect(
        nc['source'],
        'pdf',
        reason: 'the row is not rewritten at all, so nothing about it moves',
      );
      expect((await recordAt(seedA, monday2))!['status'], 'P');
      expect((await recordAt(seedB, monday))!['status'], 'P');
    });

    test('marking back to the report\'s values clears the Manual badge',
        () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'P', b: 'P');

      await markWholeDay(monday, 'A');
      expect(
        (await recordAt(seedA, monday)).let(isManual),
        isTrue,
        reason: 'every lecture now disagrees with the report',
      );

      await markWholeDay(monday, 'P');
      final rows = await dao.getDaySchedule(monday, semester);
      expect(
        rows.map((r) => r['status']),
        everyElement('P'),
      );
      expect(
        rows.every(
          (r) => r['status'] == r['original_status'],
        ),
        isTrue,
        reason: '"Manual" is derived, so putting the values back has to clear it '
            'without any extra bookkeeping',
      );
    });

    test('only the marked day changes', () async {
      await seedImportedDay(aFirst: 'A', aSecond: 'A', b: 'A');
      await seedImportedDay(
        aFirst: 'A',
        aSecond: 'A',
        b: 'A',
        date: nextMonday,
      );

      await markWholeDay(monday, 'P');

      expect(
        (await dao.getDaySchedule(monday, semester)).map((r) => r['status']),
        everyElement('P'),
      );
      expect(
        (await dao.getDaySchedule(nextMonday, semester)).map((r) => r['status']),
        everyElement('A'),
        reason: 'the same weekday one week on shares every timetable slot and '
            'both seed ids — only the date key separates them',
      );
    });

    test('the heatmap and the report percentages follow the rows', () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'A', b: 'A');

      Future<Map<int, Map<String, int>>> stats() =>
          dao.getAttendanceStatsForDateRange('2026-08-01', '2026-08-31', semester);

      expect(
        await heatmapStatuses(),
        unorderedEquals(<String>['P', 'A', 'A']),
        reason: 'the calendar paints this day "mixed"',
      );
      expect(
        (await stats()).values.map((s) => s['attended']).toList(),
        <int>[1, 0],
      );

      await markWholeDay(monday, 'P');

      expect(
        await heatmapStatuses(),
        <String>['P', 'P', 'P'],
        reason: 'the tile turns green from the database alone',
      );
      final after = await stats();
      expect(
        after.values.every((s) => s['attended'] == s['total']),
        isTrue,
        reason: 'a fully-present day lifts every subject that met on it',
      );
    });

    test('an empty plan writes nothing', () async {
      await seedImportedDay(aFirst: 'P', aSecond: 'P', b: 'P');
      final db = await DBHelper.instance.database;
      final before = await db.query('attendance_records', orderBy: 'id');

      final plan = await markWholeDay(monday, 'P');

      expect(plan.isEmpty, isTrue);
      expect(
        await db.query('attendance_records', orderBy: 'id'),
        before,
        reason: 'not one column moves when there is nothing to change',
      );
    });
  });
}

extension on Map<String, Object?>? {
  /// Applies [f] to a row that must exist — keeps the assertions above readable
  /// without a `!` and a temporary on every line.
  T let<T>(T Function(Map<String, Object?>) f) => f(this!);
}
