// The data half of the calendar's delete → undo flow (DELETE_RECORD_UNDO_PLAN).
//
// Three claims the UI rests on, none of which are visible from the widget layer:
//
//  1. `deleteAttendanceById` removes exactly the row the tapped card stands for,
//     even when the same subject has two lectures on the same date sharing one
//     seed `timetable_entry_id`.
//  2. Undo — an upsert of the captured row — restores it *verbatim*, including
//     `original_status`, the PDF baseline that exists nowhere else and so cannot
//     be recovered by re-importing the report.
//  3. Everything derived from that row comes back with it: the dashboard/report
//     percentages and the calendar's month heatmap are re-read from the database,
//     so they need no snapshotting to be correct after an undo.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int semester = 1;
  // A Monday, so the seeded weekday lecture lines up with the date.
  const String date = '2026-08-10';
  // A subject's second lecture in a day is keyed with an `_n` suffix — the case
  // that makes (seed id, date) ambiguous if the suffix is ever dropped.
  const String date2 = '2026-08-10_2';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AttendanceDao dao;
  late int seedId;

  setUp(() async {
    // Fresh database per test under a name private to this file — test files run
    // concurrently and sharing the default name makes them contend for one
    // SQLite file. Reset before deleting, and await it: releasing the handle
    // after the file is gone leaves DBHelper caching a dead connection.
    DBHelper.databaseFileName = 'delete_record_undo_test.db';
    await DBHelper.resetForTest();
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await databaseFactory.deleteDatabase(path);

    final db = await DBHelper.instance.database;
    dao = AttendanceDao();

    final int subjectId = await db.insert('subjects', {
      'name': 'Software Engineering',
      'required_percent': 75.0,
      'semester': semester,
    });
    // Attendance always lives on the day=0 seed entry, which is why both of the
    // day's lectures share a timetable_entry_id.
    seedId = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectId,
      'lecture_order': 0,
    });
    await db.insert('timetable', {
      'day_of_week': 1, // Monday
      'subject_id': subjectId,
      'lecture_order': 1,
    });

    // Two lectures on one day: the first Present, the second Absent and carrying
    // an NU baseline (the report left it blank and the user marked it), so the
    // heatmap reads "mixed" and the baseline is something a restore can lose.
    await dao.upsertAttendance(
      timetableId: seedId,
      date: date,
      status: 'P',
      source: 'pdf',
      originalStatus: 'P',
    );
    await dao.upsertAttendance(
      timetableId: seedId,
      date: date2,
      status: 'A',
      source: 'manual',
      originalStatus: 'NU',
    );
  });

  /// The one record stored under [dateKey], or null.
  Future<Map<String, Object?>?> recordAt(String dateKey) async {
    final db = await DBHelper.instance.database;
    final rows = await db.query(
      'attendance_records',
      where: 'timetable_entry_id = ? AND date = ?',
      whereArgs: [seedId, dateKey],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// What the calendar's heatmap sees for [date] — the raw statuses it reduces
  /// to a tile colour (all_p / all_a / mixed / all_nu).
  Future<List<String>> heatmapStatuses() async {
    final byDate = await dao.getMonthlyAttendanceStatus(
      '2026-08-01',
      '2026-08-31',
      semester,
    );
    return byDate[date] ?? const [];
  }

  test(
    'deleting one of two same-day lectures by id leaves the other untouched',
    () async {
      final int deletedId = (await recordAt(date2))!['id']! as int;
      final int survivorId = (await recordAt(date))!['id']! as int;

      await dao.deleteAttendanceById(deletedId);

      expect(
        await recordAt(date2),
        isNull,
        reason: 'the tapped record is gone',
      );
      final survivor = await recordAt(date);
      expect(
        survivor,
        isNotNull,
        reason: 'the subject\'s other lecture on the same date must survive — '
            'it shares the seed timetable_entry_id, so only the row id tells '
            'the two apart',
      );
      expect(survivor!['id'], survivorId);
      expect(survivor['status'], 'P');
    },
  );

  test('deleting by an id that is not there changes nothing', () async {
    final db = await DBHelper.instance.database;
    final int before =
        (await db.query('attendance_records')).length;

    await dao.deleteAttendanceById(999999);

    expect((await db.query('attendance_records')).length, before);
  });

  test('undo restores the row verbatim, PDF baseline included', () async {
    final deleted = (await recordAt(date2))!;

    await dao.deleteAttendanceById(deleted['id']! as int);
    expect(await recordAt(date2), isNull);

    // Exactly what _undoLastDelete does: re-upsert the captured values.
    await dao.upsertAttendance(
      timetableId: deleted['timetable_entry_id']! as int,
      date: deleted['date']! as String,
      status: deleted['status']! as String,
      source: deleted['source']! as String,
      originalStatus: deleted['original_status'] as String?,
    );

    final restored = (await recordAt(date2))!;
    expect(restored['status'], 'A');
    expect(restored['source'], 'manual');
    expect(
      restored['original_status'],
      'NU',
      reason: 'the PDF baseline is stored nowhere else — losing it would strip '
          'the "Manual" badge and the revert-to-NU pill from the restored row',
    );
  });

  test('report percentages fall on delete and return on undo', () async {
    Future<Map<String, int>> stats() async {
      final byRange = await dao.getAttendanceStatsForDateRange(
        '2026-08-01',
        '2026-08-31',
        semester,
      );
      // One subject in this fixture, and it always has at least one record.
      return byRange.values.single;
    }

    expect(
      await stats(),
      {'total': 2, 'attended': 1},
      reason: 'one Present, one Absent',
    );

    final deleted = (await recordAt(date2))!;
    await dao.deleteAttendanceById(deleted['id']! as int);

    expect(
      await stats(),
      {'total': 2 - 1, 'attended': 1},
      reason: 'deleting the Absent drops the total, not the attended count — '
          'which is exactly the report change the dialog warns about',
    );

    await dao.upsertAttendance(
      timetableId: deleted['timetable_entry_id']! as int,
      date: deleted['date']! as String,
      status: deleted['status']! as String,
      source: deleted['source']! as String,
      originalStatus: deleted['original_status'] as String?,
    );

    expect(
      await stats(),
      {'total': 2, 'attended': 1},
      reason: 'undo puts the percentage back where it was',
    );
  });

  test('the month heatmap flips on delete and flips back on undo', () async {
    expect(
      await heatmapStatuses(),
      unorderedEquals(<String>['P', 'A']),
      reason: 'a Present and an Absent — the calendar paints this "mixed"',
    );

    final deleted = (await recordAt(date2))!;
    await dao.deleteAttendanceById(deleted['id']! as int);

    expect(
      await heatmapStatuses(),
      <String>['P'],
      reason: 'the day is now all-Present, so its tile colour changes',
    );

    await dao.upsertAttendance(
      timetableId: deleted['timetable_entry_id']! as int,
      date: deleted['date']! as String,
      status: deleted['status']! as String,
      source: deleted['source']! as String,
      originalStatus: deleted['original_status'] as String?,
    );

    expect(
      await heatmapStatuses(),
      unorderedEquals(<String>['P', 'A']),
      reason: 'the tile comes back to "mixed" from the database alone — no '
          'pre-delete snapshot of the heatmap is needed, and one would be '
          'wrong if the user paged to another month during the undo window',
    );
  });

  test('the restored row is the one the calendar renders for that day',
      () async {
    // getDaySchedule is what the day's cards are built from. Without imported
    // report coverage it projects the weekday timetable, so the two real records
    // must still come through as real (non-virtual) rows after a delete + undo.
    final deleted = (await recordAt(date2))!;
    await dao.deleteAttendanceById(deleted['id']! as int);

    var rows = await dao.getDaySchedule(date, semester);
    expect(
      rows.where((r) => r['record_id'] != null).map((r) => r['record_date']),
      <String>[date],
      reason: 'only the surviving record is real; the freed slot falls back to '
          'a virtual NU row from the timetable',
    );

    await dao.upsertAttendance(
      timetableId: deleted['timetable_entry_id']! as int,
      date: deleted['date']! as String,
      status: deleted['status']! as String,
      source: deleted['source']! as String,
      originalStatus: deleted['original_status'] as String?,
    );

    rows = await dao.getDaySchedule(date, semester);
    final real = rows.where((r) => r['record_id'] != null).toList();
    expect(real.map((r) => r['record_date']), <String>[date, date2]);
    expect(real.map((r) => r['status']), <String>['P', 'A']);
  });

  test('delete and undo survive the imported-report path through getDaySchedule',
      () async {
    // The common case for a real user: the date is covered by an imported SAP
    // report, so getDaySchedule treats stored records as authoritative and does
    // *not* backfill the freed slot from the timetable. Different branch from
    // the test above, and the one a delete is most likely to be used on.
    await dao.addImportedReportDates(semester, const [date]);

    expect(
      (await dao.getDaySchedule(date, semester)).map((r) => r['status']),
      <String>['P', 'A'],
    );

    final deleted = (await recordAt(date2))!;
    await dao.deleteAttendanceById(deleted['id']! as int);

    final afterDelete = await dao.getDaySchedule(date, semester);
    expect(
      afterDelete.map((r) => r['status']),
      <String>['P'],
      reason: 'on an imported date the row simply goes — no virtual NU takes '
          'its place, because the report is the authority for that day',
    );
    expect(
      afterDelete.every((r) => r['record_id'] != null),
      isTrue,
      reason: 'nothing virtual leaks into an imported day',
    );

    await dao.upsertAttendance(
      timetableId: deleted['timetable_entry_id']! as int,
      date: deleted['date']! as String,
      status: deleted['status']! as String,
      source: deleted['source']! as String,
      originalStatus: deleted['original_status'] as String?,
    );

    final afterUndo = await dao.getDaySchedule(date, semester);
    expect(afterUndo.map((r) => r['record_date']), <String>[date, date2]);
    expect(afterUndo.map((r) => r['status']), <String>['P', 'A']);
    expect(
      afterUndo.last['original_status'],
      'NU',
      reason: 'the restored row still knows the report left it blank, so the '
          'calendar keeps offering its revert-to-NU pill',
    );
  });
}
