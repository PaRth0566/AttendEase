// Regression test for IMPLEMENTATION_SPEC §4 (the re-upload bug).
//
// The data-layer half of the core case: a future, in-range date must project
// the weekday's timetable as virtual "Not Updated" rows — the rows the calendar
// then renders read-only. getDaySchedule is keyed purely on weekday and is
// oblivious to past/future, so a future Tuesday returns the Tuesday timetable
// with no records stored. (The UI gate that used to hide these was removed in
// §4; that half is a widget concern verified on device.)

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Fresh database per test so seeded rows do not leak between runs, under a
    // name private to this file — test files run concurrently and sharing the
    // default name makes them contend for one SQLite file.
    //
    // Reset before deleting, and await it: releasing the handle after the file
    // is gone leaves DBHelper caching a connection to a deleted database.
    DBHelper.databaseFileName = 'calendar_future_day_test.db';
    await DBHelper.resetForTest();
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await databaseFactory.deleteDatabase(path);
  });

  test('a future in-range date projects the weekday timetable as virtual NU rows',
      () async {
    const int semester = 1;
    final db = await DBHelper.instance.database;

    // One subject with a Tuesday (weekday 2) lecture, plus its day=0 seed slot
    // (attendance lives on the seed entry — without it a virtual row is skipped).
    final int subjectId = await db.insert('subjects', {
      'name': 'Operating Systems',
      'required_percent': 75.0,
      'semester': semester,
    });
    await db.insert('timetable', {
      'day_of_week': 0, // seed slot
      'subject_id': subjectId,
      'lecture_order': 0,
    });
    await db.insert('timetable', {
      'day_of_week': 2, // Tuesday
      'subject_id': subjectId,
      'lecture_order': 1,
    });

    // A Tuesday comfortably in the future, with no records stored for it.
    DateTime future = DateTime.now().add(const Duration(days: 60));
    while (future.weekday != DateTime.tuesday) {
      future = future.add(const Duration(days: 1));
    }
    final String dateKey =
        '${future.year.toString().padLeft(4, '0')}-'
        '${future.month.toString().padLeft(2, '0')}-'
        '${future.day.toString().padLeft(2, '0')}';

    final rows = await AttendanceDao().getDaySchedule(dateKey, semester);

    expect(rows, hasLength(1), reason: 'the Tuesday timetable has one lecture');
    final row = rows.single;
    expect(row['subject_name'], 'Operating Systems');
    expect(row['status'], 'NU', reason: 'projected, not marked');
    expect(row['is_virtual'], 1, reason: 'no stored record for a future day');
    expect(row['record_id'], isNull);
  });
}
