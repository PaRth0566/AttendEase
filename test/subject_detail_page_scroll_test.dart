// The subject detail page scrolls as a single surface.
//
// It used to be a Column whose last child was an Expanded ListView, so the
// stats card, the skip calculator and the "Attendance History" header were
// pinned to the top of the body and only the timeline moved. On a phone that
// left roughly half the screen frozen: a drag started anywhere but the list
// did nothing, and the header cards permanently ate viewport the timeline
// needed.
//
// The guard below is a drag that *starts on the stats card* — the gesture that
// was a no-op before — plus a drag in the timeline area and a scroll to the
// oldest record, so making the page scroll cannot come at the cost of the list
// scrolling or of rows further down staying reachable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/screens/report/subject_detail_screen.dart';
import 'package:attend_ease/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Subject subject;

  setUp(() async {
    // Fresh database under a name private to this file — test files run
    // concurrently and would otherwise contend for the default one. Reset the
    // cached connection before deleting the file, never after.
    DBHelper.databaseFileName = 'subject_detail_page_scroll_test.db';
    await DBHelper.resetForTest();
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await databaseFactory.deleteDatabase(path);

    final db = await DBHelper.instance.database;
    final subjectId = await db.insert('subjects', {
      'name': 'Computer Science Practical X',
      'required_percent': 70.0,
      'semester': 1,
    });
    // Attendance hangs off the day=0 seed entry, as everywhere else in the app.
    final seedId = await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectId,
      'lecture_order': 0,
    });

    // Enough history that the page is taller than the 800x600 test viewport —
    // otherwise there is nothing to scroll and the assertions pass vacuously.
    final dao = AttendanceDao();
    for (var i = 1; i <= 24; i++) {
      await dao.upsertAttendance(
        timetableId: seedId,
        date: '2026-08-${i.toString().padLeft(2, '0')}',
        status: i % 5 == 0 ? 'A' : 'P',
        source: 'pdf',
        originalStatus: i % 5 == 0 ? 'A' : 'P',
      );
    }

    subject = Subject(
      id: subjectId,
      name: 'Computer Science Practical X',
      requiredPercent: 70,
      semester: 1,
    );
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    // The screen loads its history from sqflite, which is real I/O and so never
    // completes inside the fake-async zone testWidgets runs in. Without
    // runAsync the page stays on its loading spinner — an indeterminate
    // animation — and pumpAndSettle times out instead of waiting for the read.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SubjectDetailScreen(subject: subject),
        ),
      );
      for (
        var i = 0;
        i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    // Settles the fade-in and the progress-bar tween now that the spinner is
    // gone and every remaining animation is finite.
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  /// How far the one scroll view on the page has been scrolled.
  double offset(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('a drag starting on the stats card scrolls the whole page', (
    tester,
  ) async {
    await pumpDetail(tester);

    // skipOffstage: false so the card can still be measured once part of it has
    // been scrolled up past the top of the viewport.
    final statsCard = find.text('Current Attendance', skipOffstage: false);
    final statsBefore = tester.getTopLeft(statsCard).dy;
    expect(offset(tester), 0);

    // Short enough that the card stays laid out, long enough to clear the
    // touch slop: the point is that the gesture reaches a scrollable at all.
    await tester.drag(find.text('Current Attendance'), const Offset(0, -140));
    await tester.pumpAndSettle();

    // The card itself moved up, and the page's scroll view is what moved it.
    expect(offset(tester), greaterThan(0));
    expect(tester.getTopLeft(statsCard).dy, lessThan(statsBefore));
  });

  testWidgets('the section header scrolls away with the cards', (tester) async {
    await pumpDetail(tester);

    final headerBefore = tester.getTopLeft(find.text('Attendance History')).dy;

    await tester.drag(find.text('Attendance History'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(offset(tester), greaterThan(0));
    expect(
      tester.getTopLeft(find.text('Attendance History')).dy,
      lessThan(headerBefore),
    );
  });

  testWidgets('a drag in the timeline area scrolls the page, cards included', (
    tester,
  ) async {
    await pumpDetail(tester);

    final statsBefore = tester.getTopLeft(find.text('Current Attendance')).dy;

    // Low on the screen, i.e. over the history rows rather than the cards.
    await tester.dragFrom(const Offset(400, 520), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(offset(tester), greaterThan(0));
    expect(
      tester.getTopLeft(find.text('Current Attendance')).dy,
      lessThan(statsBefore),
    );
  });

  testWidgets('the oldest record is reachable by scrolling the page', (
    tester,
  ) async {
    await pumpDetail(tester);

    // Aug 1 2026 was a Saturday; it is the last of the 24 seeded rows.
    await tester.scrollUntilVisible(
      find.text('Saturday, Aug 1, 2026'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saturday, Aug 1, 2026'), findsOneWidget);
  });

  testWidgets('there is one scroll view, not a page-plus-list pair', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
  });
}
