// The report screen's Custom Dates range, at both layers that constrain it.
//
// Two separate rules are asserted, because two separate things used to go wrong:
//
//  * **An inverted range is refused in either order.** Only the End picker
//    validated against the other bound, so picking End first and then a *later*
//    Start slipped through silently — the screen kept a Start after its End, and
//    Generate Report ran on it and reported "No attendance data" as if the range
//    were merely empty.
//  * **The pickers are bounded by the records themselves**, not by the profile's
//    semester start/end and not by a hardcoded 2020–2030 window. The span runs
//    from the first date carrying any record to the last — P, A, NU and NC all
//    count, and a record dated past today extends the end rather than being
//    clipped to today.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/screens/report/report_screen.dart';
import 'package:attend_ease/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const int semester = 1;

  // A span deliberately in the past: the Start picker opens on
  // clamp(DateTime.now()), so a span that cannot contain "today" pins the
  // displayed month to the span's end no matter when the suite runs.
  const String spanStart = '2020-03-02';
  const String spanEnd = '2020-03-27';

  late AttendanceDao dao;
  late int seedId;

  /// Recreates the database and the one subject whose seed slot holds every
  /// record these tests write. Called directly by the DAO tests, and via
  /// [WidgetTester.runAsync] by the widget tests.
  Future<void> resetDatabase() async {
    // Private database file: test files run concurrently in separate isolates
    // and would otherwise contend for the default name. Drop the cached
    // connection before deleting, so DBHelper never caches a dead handle.
    DBHelper.databaseFileName = 'report_custom_date_range_test.db';
    await DBHelper.resetForTest();
    await databaseFactory.deleteDatabase(
      '${await getDatabasesPath()}/${DBHelper.databaseFileName}',
    );

    SharedPreferences.setMockInitialValues({'semester': semester});

    final db = await DBHelper.instance.database;
    dao = AttendanceDao();

    final int subjectId = await db.insert('subjects', {
      'name': 'Software Engineering',
      'required_percent': 75.0,
      'semester': semester,
    });
    // Attendance always lives on the day=0 seed entry.
    seedId = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectId,
      'lecture_order': 0,
    });
  }

  /// Writes one record, bypassing the baseline lookup so NU/NC are stored as-is.
  Future<void> record(String date, String status) async {
    await dao.upsertAttendance(
      timetableId: seedId,
      date: date,
      status: status,
      source: 'pdf',
      originalStatus: status,
    );
  }

  /// Seeds the span: an NU at the first date and an NC at the last, so the
  /// bounds can only be right if statuses that carry no weight in a percentage
  /// still count as "there is a record on this day".
  Future<void> seedSpan() async {
    await record(spanStart, 'NU');
    await record('2020-03-09', 'P');
    await record('2020-03-16', 'A');
    await record(spanEnd, 'NC');
  }

  /// Gives the screen's real database and prefs reads room to complete, then
  /// settles the tree. See [pumpCustomDates] for why `runAsync` is unavoidable.
  Future<void> settleAfterIo(WidgetTester tester) async {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
  }

  /// Pumps the report screen with Custom Dates already selected.
  ///
  /// The screen reads prefs and the database from `initState`, and both are real
  /// async I/O — `testWidgets` runs the body inside a fake-async zone where such
  /// futures never resume, so the reads are given real event-loop time via
  /// [WidgetTester.runAsync] before the tree is settled. Without it the first
  /// `pumpAndSettle` waits forever on a screen still showing "Loading…".
  Future<void> pumpCustomDates(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        // A Scaffold ancestor is what gives ScaffoldMessenger somewhere to put
        // the validation SnackBars these tests assert on.
        home: const Scaffold(body: ReportScreen()),
      ),
    );
    await settleAfterIo(tester);
    await tester.tap(find.text('Custom Dates'));
    await tester.pumpAndSettle();
  }

  /// Taps [day] in the open date picker's grid, then confirms.
  ///
  /// The picker opens on the record span's month (its initialDate is clamped
  /// into the span), so the day is already on screen and no month navigation is
  /// needed. Both bounds sit in March 2020, which has no ambiguous duplicate day
  /// cells.
  Future<void> pickDay(WidgetTester tester, String day) async {
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text(day),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  group('record date bounds', () {
    setUp(resetDatabase);

    test('span runs from the first record to the last, NU and NC included', () async {
      await seedSpan();

      final bounds = await dao.getAttendanceDateBoundsForSemester(semester);

      expect(bounds.firstDate, DateTime.parse(spanStart));
      expect(bounds.lastDate, DateTime.parse(spanEnd));
    });

    test('a record dated after today extends the end instead of being clipped', () async {
      await seedSpan();
      final DateTime future = DateTime.now().add(const Duration(days: 30));
      final String futureKey =
          '${future.year.toString().padLeft(4, '0')}-'
          '${future.month.toString().padLeft(2, '0')}-'
          '${future.day.toString().padLeft(2, '0')}';
      await record(futureKey, 'NU');

      final bounds = await dao.getAttendanceDateBoundsForSemester(semester);

      expect(bounds.firstDate, DateTime.parse(spanStart));
      expect(bounds.lastDate, DateTime.parse(futureKey));
    });

    test('multi-lecture suffixes are compared on the real date', () async {
      // '2020-03-27_2' sorts lexicographically past every plain date, so a
      // MAX() over the raw column would report the suffix key itself and fail to
      // parse. The bound is taken from the stripped 10-char date instead.
      await seedSpan();
      await record('${spanEnd}_2', 'P');

      final bounds = await dao.getAttendanceDateBoundsForSemester(semester);

      expect(bounds.lastDate, DateTime.parse(spanEnd));
    });

    test('padding rows and other semesters are excluded', () async {
      await seedSpan();
      await record('pad_1', 'P');
      final db = await DBHelper.instance.database;
      final int otherSubject = await db.insert('subjects', {
        'name': 'Elective',
        'required_percent': 75.0,
        'semester': 2,
      });
      final int otherSeed = await db.insert('timetable', {
        'day_of_week': 0,
        'subject_id': otherSubject,
        'lecture_order': 0,
      });
      await dao.upsertAttendance(
        timetableId: otherSeed,
        date: '2019-01-01',
        status: 'P',
        source: 'pdf',
        originalStatus: 'P',
      );

      final bounds = await dao.getAttendanceDateBoundsForSemester(semester);

      expect(bounds.firstDate, DateTime.parse(spanStart));
      expect(bounds.lastDate, DateTime.parse(spanEnd));
    });

    test('no records leaves both bounds null', () async {
      final bounds = await dao.getAttendanceDateBoundsForSemester(semester);

      expect(bounds.firstDate, isNull);
      expect(bounds.lastDate, isNull);
    });
  });

  group('custom date pickers', () {
    /// Rebuilds the database and seeds the span, all in the real zone — the
    /// widget tests cannot await database I/O from the fake-async body.
    Future<void> seedFor(WidgetTester tester, {bool withRecords = true}) async {
      await tester.runAsync(() async {
        await resetDatabase();
        if (withRecords) await seedSpan();
      });
    }

    testWidgets('both pickers are bounded by the record span', (tester) async {
      await seedFor(tester);
      await pumpCustomDates(tester);

      for (final label in ['Start Date', 'End Date']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        final dialog = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(dialog.firstDate, DateTime.parse(spanStart));
        expect(dialog.lastDate, DateTime.parse(spanEnd));

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('picking a Start after an already-picked End is refused', (
      tester,
    ) async {
      await seedFor(tester);
      await pumpCustomDates(tester);

      // End first — the order that used to skip validation entirely.
      await tester.tap(find.text('End Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '10');
      expect(find.text('Mar 10, 2020'), findsOneWidget);

      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '20');

      expect(find.text('Start date cannot be after End date'), findsOneWidget);
      // Refused means unchanged: the button still shows no start date, so
      // Generate Report cannot run on an inverted range.
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('Mar 20, 2020'), findsNothing);
      expect(find.text('Mar 10, 2020'), findsOneWidget);
    });

    testWidgets('picking an End before an already-picked Start is refused', (
      tester,
    ) async {
      await seedFor(tester);
      await pumpCustomDates(tester);

      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '20');
      expect(find.text('Mar 20, 2020'), findsOneWidget);

      await tester.tap(find.text('End Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '10');

      expect(find.text('End date cannot be before Start date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      expect(find.text('Mar 10, 2020'), findsNothing);
    });

    testWidgets('a valid range in either order is accepted', (tester) async {
      await seedFor(tester);
      await pumpCustomDates(tester);

      await tester.tap(find.text('End Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '20');

      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();
      await pickDay(tester, '10');

      expect(find.text('Mar 10, 2020'), findsOneWidget);
      expect(find.text('Mar 20, 2020'), findsOneWidget);
      expect(find.textContaining('cannot be'), findsNothing);
    });

    testWidgets('a semester with no records opens no picker at all', (
      tester,
    ) async {
      await seedFor(tester, withRecords: false);
      await pumpCustomDates(tester);

      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(
        find.textContaining('no date range to pick from'),
        findsOneWidget,
      );
    });
  });
}
