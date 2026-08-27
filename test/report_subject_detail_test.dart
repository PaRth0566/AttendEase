// Opening a subject from Analytics & Reports.
//
// The breakdown cards used to be inert Cards — a tap did nothing at all. They
// now open the same detail page the Dashboard's subject cards open, through the
// same container transform, but scoped to the period the report was generated
// over. Four things have to hold for that to be true rather than merely to look
// true:
//
//  * **The page counts what the card counted.** A Custom Dates report confines
//    every figure — percentage, attended, total — and every history row to the
//    picked span; a Semester report counts the semester's whole record set,
//    which is exactly what the card's own query counts.
//  * **"Safe to Skip" is withheld.** It projects lectures *after* the period, so
//    it says nothing about a report. The numbers below are deliberately chosen so
//    that section would render if the scope were not what suppressed it.
//  * **The card is an anchor.** Tapping it pushes the detail route and the
//    transform grows out of the card, as on the Dashboard.
//  * **The page still scrolls as one surface**, range-scoped or not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/screens/report/report_screen.dart';
import 'package:attend_ease/screens/report/subject_detail_screen.dart';
import 'package:attend_ease/theme/app_page_transition.dart';
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/container_transform.dart';
import 'package:attend_ease/widgets/pressable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const int semester = 1;

  /// Required percent low enough that the subject sits *above* target in both
  /// scopes. "Safe to Skip" is only offered above target, so this is what makes
  /// its absence in a report scope evidence of the guard rather than of the
  /// maths declining to offer anything.
  const double requiredPercent = 50.0;

  // The Custom Dates span the tests pick, and the report's own label for it.
  const String rangeStart = '2026-03-02';
  const String rangeEnd = '2026-03-13';
  const String rangeLabel = 'Mar 2, 2026 – Mar 13, 2026';

  late AttendanceDao dao;
  late int subjectId;
  late int seedId;
  late Subject subject;

  /// Rebuilds the database with one subject and the record set below.
  ///
  /// Everything sits inside March 2026 so the date pickers — which open on the
  /// record span's month — need no month navigation.
  ///
  /// Inside [rangeStart]–[rangeEnd]:  P A P  + P and a suffixed A on the end
  /// boundary, plus an NU and an NC that carry no weight  ->  3 / 5  (60.00%)
  /// Outside it: a P before, an A and a P after                ->  5 / 8  (62.50%)
  ///
  /// The two totals differ in both parts, so a page that quietly ignores its
  /// range cannot pass, and neither can one that drops the `_2` key on the end
  /// boundary (which sorts lexicographically past it).
  Future<void> resetDatabase() async {
    // Private database file: test files run concurrently in separate isolates
    // and would otherwise contend for the default name. Drop the cached
    // connection before deleting, so DBHelper never caches a dead handle.
    DBHelper.databaseFileName = 'report_subject_detail_test.db';
    await DBHelper.resetForTest();
    await databaseFactory.deleteDatabase(
      '${await getDatabasesPath()}/${DBHelper.databaseFileName}',
    );

    SharedPreferences.setMockInitialValues({'semester': semester});
    ContainerTransformOrigin.resetForTesting();

    final db = await DBHelper.instance.database;
    dao = AttendanceDao();

    subjectId = await db.insert('subjects', {
      'name': 'Data Structures',
      'required_percent': requiredPercent,
      'semester': semester,
    });
    // Attendance always hangs off the day=0 seed entry.
    seedId = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectId,
      'lecture_order': 0,
    });
    subject = Subject(
      id: subjectId,
      name: 'Data Structures',
      requiredPercent: requiredPercent,
      semester: semester,
    );

    Future<void> record(String date, String status) => dao.upsertAttendance(
      timetableId: seedId,
      date: date,
      status: status,
      // Bypasses the baseline lookup so NU/NC are stored as themselves.
      originalStatus: status,
      source: 'pdf',
    );

    // In range.
    await record(rangeStart, 'P'); // Mon 2 Mar
    await record('2026-03-03', 'A');
    await record('2026-03-04', 'P');
    await record('2026-03-05', 'NU'); // no weight in either total
    await record('2026-03-06', 'NC'); // no weight in either total
    await record(rangeEnd, 'P'); // Fri 13 Mar
    await record('${rangeEnd}_2', 'A'); // second lecture, same day

    // Out of range.
    await record('2026-03-01', 'P');
    await record('2026-03-14', 'A');
    await record('2026-03-20', 'P');

    // Never counted anywhere.
    await record('pad_1', 'P');
  }

  /// Settles the tree across the screens' real database and prefs reads.
  ///
  /// Alternates real event-loop time with fake-clock pumps, because doing only
  /// one of the two hangs. `testWidgets` runs its body inside a fake-async zone
  /// where real I/O futures never resume, so the reads need
  /// [WidgetTester.runAsync] — but `runAsync` never advances an animation, so a
  /// route transition sits frozen through it. And `pumpAndSettle` alone never
  /// lets the database answer, so a detail page still on its spinner — which is
  /// indeterminate, and therefore schedules frames forever — makes it time out.
  ///
  /// The spinner is the wait signal; the minimum round count covers the reads
  /// that have no spinner behind them (the report screen's own prefs + bounds
  /// load), where there is nothing to wait for by inspection.
  Future<void> settleIo(WidgetTester tester) async {
    for (var round = 0; round < 60; round++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      // Outside runAsync, so the fake clock actually moves.
      await tester.pump(const Duration(milliseconds: 40));
      if (round >= 6 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  group('range-scoped history read', () {
    setUp(resetDatabase);

    test('returns only the records inside the range, bounds included', () async {
      final rows = await dao.getAttendanceHistoryForSubjectInRange(
        subjectId,
        rangeStart,
        rangeEnd,
      );

      expect(
        rows.map((r) => r['date']).toSet(),
        {
          rangeStart,
          '2026-03-03',
          '2026-03-04',
          '2026-03-05',
          '2026-03-06',
          rangeEnd,
          '${rangeEnd}_2',
        },
      );
    });

    test('a multi-lecture suffix on the end bound is matched on its real date', () async {
      // '2026-03-13_2' > '2026-03-13' lexicographically, so a raw string
      // comparison against the end bound drops it. The stripped 10-char date is
      // what is compared.
      final rows = await dao.getAttendanceHistoryForSubjectInRange(
        subjectId,
        rangeStart,
        rangeEnd,
      );

      expect(rows.map((r) => r['date']), contains('${rangeEnd}_2'));
    });

    test('padding rows and out-of-range records are excluded', () async {
      final rows = await dao.getAttendanceHistoryForSubjectInRange(
        subjectId,
        rangeStart,
        rangeEnd,
      );
      final dates = rows.map((r) => r['date']).toList();

      expect(dates, isNot(contains('pad_1')));
      expect(dates, isNot(contains('2026-03-01')));
      expect(dates, isNot(contains('2026-03-14')));
      expect(dates, isNot(contains('2026-03-20')));
    });

    test('another subject in the same range is not mixed in', () async {
      final db = await DBHelper.instance.database;
      final int otherSubject = await db.insert('subjects', {
        'name': 'Elective',
        'required_percent': requiredPercent,
        'semester': semester,
      });
      final int otherSeed = await db.insert('timetable', {
        'day_of_week': 0,
        'subject_id': otherSubject,
        'lecture_order': 0,
      });
      await dao.upsertAttendance(
        timetableId: otherSeed,
        date: '2026-03-04',
        status: 'A',
        originalStatus: 'A',
        source: 'pdf',
      );

      final rows = await dao.getAttendanceHistoryForSubjectInRange(
        subjectId,
        rangeStart,
        rangeEnd,
      );

      expect(rows.length, 7);
      expect(rows.every((r) => r['timetable_entry_id'] == seedId), isTrue);
    });

    test('the range read and the card query agree on P/A counts', () async {
      // The card's number and the page's number come from two different
      // queries. This is the assertion that they cannot drift apart.
      final stats = await dao.getAttendanceStatsForDateRange(
        rangeStart,
        rangeEnd,
        semester,
      );
      final rows = await dao.getAttendanceHistoryForSubjectInRange(
        subjectId,
        rangeStart,
        rangeEnd,
      );

      final counted = rows.where(
        (r) => r['status'] == 'P' || r['status'] == 'A',
      );
      expect(counted.length, stats[subjectId]!['total']);
      expect(
        counted.where((r) => r['status'] == 'P').length,
        stats[subjectId]!['attended'],
      );
    });
  });

  group('subject detail page', () {
    /// Rebuilds the database in the real zone — a fake-async test body cannot
    /// await database I/O.
    Future<void> seedFor(WidgetTester tester) async {
      await tester.runAsync(resetDatabase);
    }

    Future<void> pumpDetail(
      WidgetTester tester, {
      DateTimeRange? range,
      String? label,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SubjectDetailScreen(
            subject: subject,
            reportRange: range,
            reportLabel: label,
          ),
        ),
      );
      await settleIo(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    testWidgets('a custom-range scope counts only that range', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse(rangeStart),
          end: DateTime.parse(rangeEnd),
        ),
        label: rangeLabel,
      );

      // 3 of 5 weighted lectures inside the span — not 5 of 8, the whole
      // history, and not 2 of 4, the span minus its suffixed end-boundary row.
      expect(find.text('60.00%'), findsOneWidget);
      expect(find.text('3 / 5 Lectures Attended'), findsOneWidget);
      expect(find.text('62.50%'), findsNothing);
    });

    testWidgets('the scoped page names the period it covers', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse(rangeStart),
          end: DateTime.parse(rangeEnd),
        ),
        label: rangeLabel,
      );

      expect(find.text('Attendance in This Period'), findsOneWidget);
      expect(find.text(rangeLabel), findsOneWidget);
      // "Current" would claim these figures are where the subject stands now.
      expect(find.text('Current Attendance'), findsNothing);
    });

    testWidgets('history rows outside the range are not listed', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse(rangeStart),
          end: DateTime.parse(rangeEnd),
        ),
        label: rangeLabel,
      );

      // Descending by date, so a record *after* the range would head the list —
      // the strongest place for an unscoped read to show itself.
      expect(find.text('Friday, Mar 13, 2026'), findsNWidgets(2));
      expect(find.text('Friday, Mar 20, 2026'), findsNothing);
      expect(find.text('Saturday, Mar 14, 2026'), findsNothing);

      // The oldest in-range row is the last one; the record from the day before
      // the range must not be sitting under it.
      await tester.scrollUntilVisible(
        find.text('Monday, Mar 2, 2026'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      expect(find.text('Monday, Mar 2, 2026'), findsOneWidget);
      expect(find.text('Sunday, Mar 1, 2026'), findsNothing);
    });

    testWidgets('no Safe to Skip section in a report scope', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse(rangeStart),
          end: DateTime.parse(rangeEnd),
        ),
        label: rangeLabel,
      );

      expect(find.text('Safe to Skip'), findsNothing);
      // The attendance card hands straight over to the history, with nothing
      // between them.
      expect(find.text('Attendance History'), findsOneWidget);
    });

    testWidgets('a Semester scope counts the whole record set', (tester) async {
      await seedFor(tester);
      // Semester mode carries no range: the report's own query counts every
      // record the semester holds, so the page must too.
      await pumpDetail(tester, range: null, label: 'Semester 1');

      expect(find.text('62.50%'), findsOneWidget);
      expect(find.text('5 / 8 Lectures Attended'), findsOneWidget);
      expect(find.text('Semester 1'), findsOneWidget);
      // Still a report, so still no projection past the period.
      expect(find.text('Safe to Skip'), findsNothing);
    });

    testWidgets('the live view keeps Safe to Skip and its own heading', (
      tester,
    ) async {
      await seedFor(tester);
      // No label -> opened from the Dashboard. Same records, same subject: the
      // only difference is the scope, which is the point. 62.5% against a 50%
      // target leaves lectures in hand, and the two Fridays in the history give
      // the projection a weekday pattern to place them on.
      await pumpDetail(tester);

      expect(find.text('Safe to Skip'), findsOneWidget);
      expect(find.text('Current Attendance'), findsOneWidget);
      expect(find.text('Attendance in This Period'), findsNothing);
    });

    testWidgets('a range with no records says so', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse('2026-05-01'),
          end: DateTime.parse('2026-05-31'),
        ),
        label: 'May 1, 2026 – May 31, 2026',
      );

      expect(find.text('0.00%'), findsOneWidget);
      expect(find.text('0 / 0 Lectures Attended'), findsOneWidget);
      expect(find.text('No lectures recorded in this period.'), findsOneWidget);
    });

    testWidgets('the scoped page is one scroll surface', (tester) async {
      await seedFor(tester);
      await pumpDetail(
        tester,
        range: DateTimeRange(
          start: DateTime.parse(rangeStart),
          end: DateTime.parse(rangeEnd),
        ),
        label: rangeLabel,
      );

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);

      // A drag starting on the attendance card moves the whole page, not just
      // the history list. skipOffstage: false so the card can still be measured
      // once part of it has scrolled up past the top of the viewport.
      final card = find.text('Attendance in This Period', skipOffstage: false);
      final double before = tester.getTopLeft(card).dy;

      await tester.drag(
        find.text('Attendance in This Period'),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      expect(tester.getTopLeft(card).dy, lessThan(before));
    });
  });

  group('opening a breakdown card', () {
    /// Mirrors the two routes the app router declares for this flow, so the tap
    /// goes through a real `push` with a real container-transform page.
    GoRouter buildRouter() => GoRouter(
      initialLocation: '/app/profile/report',
      routes: [
        GoRoute(
          path: '/app/profile/report',
          pageBuilder: (context, state) =>
              AppPageTransition.containerPage(state, const ReportScreen()),
          routes: [
            GoRoute(
              path: 'subject-detail',
              redirect: (context, state) => state.extra is! SubjectReportArgs
                  ? '/app/profile/report'
                  : null,
              pageBuilder: (context, state) {
                final args = state.extra as SubjectReportArgs;
                return AppPageTransition.containerPage(
                  state,
                  SubjectDetailScreen(
                    subject: args.subject,
                    reportRange: args.range,
                    reportLabel: args.label,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );

    /// Pumps the report screen, generates the default Semester report, and
    /// brings the one breakdown card into view.
    ///
    /// The breakdown sits below the fold on the 800x600 test viewport, and both
    /// things these tests do to the card — tapping it, and reading the rect the
    /// transform starts from — need it on screen.
    Future<void> pumpGeneratedReport(WidgetTester tester) async {
      await tester.runAsync(resetDatabase);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: buildRouter(),
        ),
      );
      await settleIo(tester);
      await tester.tap(find.text('Generate Report'));
      await settleIo(tester);
      expect(find.text('Subject Breakdown'), findsOneWidget);

      await tester.ensureVisible(find.text('Data Structures'));
      await tester.pumpAndSettle();
    }

    /// The card as the transform will see it: the anchor's on-screen rect.
    Rect cardRect(WidgetTester tester) => tester.getRect(
      find.ancestor(
        of: find.text('Data Structures'),
        matching: find.byType(ContainerTransformAnchor),
      ),
    );

    /// Picks [day] in the picker behind the [button] date field, then confirms.
    ///
    /// Both pickers open on the record span's month (their initialDate is
    /// clamped into the span), so the day is already on screen and no month
    /// navigation is needed. March 2026 has no ambiguous duplicate day cells.
    Future<void> pickDay(
      WidgetTester tester,
      String button,
      String day,
    ) async {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
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

    /// Scrolls the card into view and opens it.
    Future<void> openCard(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Data Structures'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Data Structures'));
      await settleIo(tester);
    }

    /// Finds [text] on the opened detail page specifically.
    ///
    /// The report stays in the tree behind it and shares some of these strings —
    /// its semester chip also reads "Semester 1", and its card carries the same
    /// percentage — so a bare text finder would not say which screen it found.
    Finder onDetail(String text) => find.descendant(
      of: find.byType(SubjectDetailScreen),
      matching: find.text(text),
    );

    testWidgets('each card is a pressable container-transform anchor', (
      tester,
    ) async {
      await pumpGeneratedReport(tester);

      final card = find.ancestor(
        of: find.text('Data Structures'),
        matching: find.byType(ContainerTransformAnchor),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(Pressable)),
        findsOneWidget,
      );
    });

    testWidgets('tapping a card opens the subject, scoped to the report', (
      tester,
    ) async {
      await pumpGeneratedReport(tester);
      // The card's own figures, for the semester's whole record set.
      expect(find.text('5 / 8 lectures'), findsOneWidget);

      await tester.tap(find.text('Data Structures'));
      await settleIo(tester);

      // The detail page arrived, carrying the report's scope with it.
      expect(onDetail('Attendance in This Period'), findsOneWidget);
      expect(onDetail('Semester 1'), findsOneWidget);
      expect(onDetail('62.50%'), findsOneWidget);
      expect(onDetail('5 / 8 Lectures Attended'), findsOneWidget);
      expect(onDetail('Attendance History'), findsOneWidget);
      expect(find.text('Safe to Skip'), findsNothing);
    });

    testWidgets('a Custom Dates report opens scoped to the picked span', (
      tester,
    ) async {
      await tester.runAsync(resetDatabase);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: buildRouter(),
        ),
      );
      await settleIo(tester);

      await tester.tap(find.text('Custom Dates'));
      await tester.pumpAndSettle();
      await pickDay(tester, 'Start Date', '2');
      await pickDay(tester, 'End Date', '13');

      await tester.tap(find.text('Generate Report'));
      await settleIo(tester);

      // The card counts the span, not the semester — 3 of 5, not 5 of 8.
      expect(find.text('3 / 5 lectures'), findsOneWidget);

      await openCard(tester);

      // ...and so does the page it opens, down to the same label the report
      // used for the span.
      expect(onDetail(rangeLabel), findsOneWidget);
      expect(onDetail('60.00%'), findsOneWidget);
      expect(onDetail('3 / 5 Lectures Attended'), findsOneWidget);
      expect(find.text('Safe to Skip'), findsNothing);
      // Only the span's rows: Fri 13 Mar twice, and nothing from after it.
      expect(onDetail('Friday, Mar 13, 2026'), findsNWidgets(2));
      expect(onDetail('Friday, Mar 20, 2026'), findsNothing);
    });

    testWidgets('the page grows out of the tapped card', (tester) async {
      await pumpGeneratedReport(tester);

      final Rect card = cardRect(tester);
      final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      await tester.tap(find.text('Data Structures'));
      // Part-way into the 440ms flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(ContainerTransformTransition.scrimKey),
        findsOneWidget,
        reason: 'the tap did not start a container transform',
      );

      // The flying box: the Material the transform lays the page out inside.
      // Mid-flight it has grown past the card it came from and has not yet
      // reached the full screen — i.e. the page is morphing out of the card
      // rather than cutting straight in.
      final Rect flying = tester.getRect(
        find
            .ancestor(
              of: find.byType(SubjectDetailScreen),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(flying.height, greaterThan(card.height));
      expect(flying.height, lessThan(screen.height));
      expect(flying.width, greaterThanOrEqualTo(card.width));

      await settleIo(tester);
      // Settled: no scrim, no flying box, just the page.
      expect(find.byKey(ContainerTransformTransition.scrimKey), findsNothing);
      expect(onDetail('Semester 1'), findsOneWidget);
    });

    testWidgets('popping shrinks back and leaves the report on screen', (
      tester,
    ) async {
      await pumpGeneratedReport(tester);

      await tester.tap(find.text('Data Structures'));
      await settleIo(tester);
      expect(onDetail('Attendance in This Period'), findsOneWidget);

      // Back: the reverse of the same transform.
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(ContainerTransformTransition.scrimKey), findsOneWidget);

      await settleIo(tester);
      expect(find.byType(SubjectDetailScreen), findsNothing);
      expect(find.text('Subject Breakdown'), findsOneWidget);
      // Re-read on return, since a record may have been edited on the page that
      // just closed.
      expect(find.text('5 / 8 lectures'), findsOneWidget);
    });
  });
}
