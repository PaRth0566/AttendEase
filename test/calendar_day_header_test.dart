// The calendar's selected-day heading, where the two whole-day mark pills live.
//
// The row is a fixed-width pair of pills next to a variable-width date, which is
// the one layout on the screen that can genuinely run out of room: "Wednesday,
// September 30, 2026" is 60% wider than "Sun, 1 Mar", and the pills do not shrink.
// Three things are pinned here:
//
//  * the heading gives way by wrapping, and only after the weekday — never by
//    being cut mid-date, and never by pushing the pills off the row;
//  * the pills stay a fixed size under a large OS font, because the alternative
//    is them eating the date's space;
//  * each pill calls its own action, since the two differ only by colour and one
//    letter and a crossed wire would silently mark a day the wrong way.

import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/widgets/calendar_day_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Wednesday with the longest month name and a two-digit day — the widest
/// heading the calendar can produce.
final DateTime _widestDay = DateTime(2026, 9, 30);

Widget _harness({
  required DateTime day,
  bool showBulkActions = true,
  double width = 360,
  double textScale = 1.0,
  VoidCallback? onPresent,
  VoidCallback? onAbsent,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: CalendarDayHeader(
              day: day,
              showBulkActions: showBulkActions,
              onMarkAllPresent: onPresent ?? () {},
              onMarkAllAbsent: onAbsent ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the heading can only wrap after the weekday', (tester) async {
    await tester.pumpWidget(_harness(day: _widestDay));

    final String heading = tester.widget<Text>(find.byType(Text).first).data!;
    expect(
      heading.split(' '),
      hasLength(2),
      reason: 'exactly one breakable space, right after the weekday — the rest '
          'of the date is joined with U+00A0 so a narrow row cannot strand '
          '"2026" on a line of its own',
    );
    expect(heading, startsWith('Wednesday, '));
    expect(heading, endsWith('2026'));
  });

  testWidgets('both pills sit on the heading line', (tester) async {
    await tester.pumpWidget(_harness(day: _widestDay));

    final Rect heading = tester.getRect(find.byType(Text).first);
    for (final label in [
      CalendarDayHeader.presentLabel,
      CalendarDayHeader.absentLabel,
    ]) {
      final Rect pill = tester.getRect(find.text(label));
      expect(
        pill.center.dy,
        inInclusiveRange(heading.top, heading.bottom),
        reason: '$label must ride the heading, not sit under it',
      );
      expect(
        pill.left,
        greaterThan(heading.left),
        reason: '$label belongs on the right of the date',
      );
    }

    final Rect present = tester.getRect(find.text(CalendarDayHeader.presentLabel));
    final Rect absent = tester.getRect(find.text(CalendarDayHeader.absentLabel));
    expect(
      present.right,
      lessThanOrEqualTo(absent.left),
      reason: 'present first, then absent — the order the legend uses',
    );
  });

  testWidgets('the widest date and both pills fit a narrow phone', (
    tester,
  ) async {
    // 320dp is the narrowest viewport worth supporting, and this is the widest
    // heading — the case that decides whether the row needs to wrap at all.
    await tester.pumpWidget(_harness(day: _widestDay, width: 320));

    expect(tester.takeException(), isNull);
    final Rect row = tester.getRect(find.byType(CalendarDayHeader));
    final Rect absent = tester.getRect(find.text(CalendarDayHeader.absentLabel));
    expect(
      absent.right,
      lessThanOrEqualTo(row.right),
      reason: 'the trailing pill must not be pushed past the row it lives in',
    );
    expect(
      tester.getRect(find.byType(Text).first).left,
      greaterThanOrEqualTo(row.left),
      reason: 'and the heading must not be pushed off the leading edge to make '
          'room for them',
    );
  });

  testWidgets('a large OS font does not let the pills eat the date', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(day: _widestDay, width: 320));
    final double atRest = tester
        .getSize(find.text(CalendarDayHeader.presentLabel))
        .width;

    await tester.pumpWidget(
      _harness(day: _widestDay, width: 320, textScale: 2.0),
    );
    final double scaled = tester
        .getSize(find.text(CalendarDayHeader.presentLabel))
        .width;

    expect(tester.takeException(), isNull);
    expect(
      scaled / atRest,
      lessThanOrEqualTo(1.2),
      reason: 'the pills are clamped to 1.15x; unclamped they would double and '
          'leave the date nothing',
    );
  });

  testWidgets('each pill calls its own action', (tester) async {
    var present = 0;
    var absent = 0;
    await tester.pumpWidget(
      _harness(
        day: _widestDay,
        onPresent: () => present++,
        onAbsent: () => absent++,
      ),
    );

    await tester.tap(find.text(CalendarDayHeader.presentLabel));
    await tester.pumpAndSettle();
    expect([present, absent], [1, 0]);

    await tester.tap(find.text(CalendarDayHeader.absentLabel));
    await tester.pumpAndSettle();
    expect([present, absent], [1, 1]);
  });

  testWidgets('a day that cannot be marked shows no pills', (tester) async {
    // Sundays, future days and days with nothing but "Not Conducted" on them: the
    // heading still renders, the actions do not.
    await tester.pumpWidget(
      _harness(day: _widestDay, showBulkActions: false),
    );

    expect(find.text(CalendarDayHeader.presentLabel), findsNothing);
    expect(find.text(CalendarDayHeader.absentLabel), findsNothing);
    expect(find.textContaining('Wednesday'), findsOneWidget);
  });
}
