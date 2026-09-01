import 'package:attend_ease/widgets/app_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(void Function(BuildContext) onPressed) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// [_host] under a `MediaQuery` reporting system insets, as a real device does.
///
/// The override goes in `MaterialApp.builder`, which wraps the `Navigator`
/// itself — a `MediaQuery` around `MaterialApp` would be shadowed by the one
/// `WidgetsApp` installs from the view, and one inside `home` would not be an
/// ancestor of the sheet's route at all.
///
/// `viewPadding` *and* `padding` are both set for the navigation-bar inset —
/// that is what a device reports when nothing has consumed it, and it also
/// proves the sheet reads the value that survives an ancestor `SafeArea`.
Widget _insetHost(
  void Function(BuildContext) onPressed, {
  double navBarInset = 0,
  double keyboardInset = 0,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewPadding: EdgeInsets.only(bottom: navBarInset),
        padding: EdgeInsets.only(bottom: navBarInset),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('showAppDialog opens, scales in, and closes', (tester) async {
    await tester.pumpWidget(_host((context) => showAppDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('body')),
        )));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-transition the dialog is present but still scaled down. getRect (not
    // getSize) is what reflects the ScaleTransition — layout size is constant.
    expect(find.text('body'), findsOneWidget);
    final double midWidth = tester.getRect(find.byType(AlertDialog)).width;

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AlertDialog)).width,
        greaterThan(midWidth));

    // Dismiss via the barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });

  testWidgets('showAppDialog can be non-dismissible', (tester) async {
    await tester.pumpWidget(_host((context) => showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(content: Text('body')),
        )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('showAppModalSheet opens and closes without disposing its '
      'controller mid-animation', (tester) async {
    await tester.pumpWidget(_host((context) => showAppModalSheet<void>(
          context: context,
          builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
        )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    // Closing runs the reverse animation; the controller must outlive it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showAppModalSheet survives being opened and closed repeatedly',
      (tester) async {
    await tester.pumpWidget(_host((context) => showAppModalSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
        )));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  // ── Bottom-sheet system-inset clearance ───────────────────────────────────
  //
  // Regression: the Profile semester picker's last rows (Semester 8) were
  // painted behind Android's 3-button navigation bar. The app renders
  // edge-to-edge, so a sheet's box reaches the physical screen edge and the
  // system bar sits on top of it. showAppModalSheet now lifts its content by
  // max(keyboard, navigation-bar) inset — `viewPadding`, which no ancestor
  // SafeArea can consume, rather than `padding`.
  group('bottom sheet clears the system navigation bar', () {
    /// The bottom edge of the sheet's own content, in logical pixels.
    double contentBottom(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('sheet_content'))).bottom;

    double screenHeight(WidgetTester tester) =>
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    Future<void> openSheet(
      WidgetTester tester, {
      double navBarInset = 0,
      double keyboardInset = 0,
      bool selfSizing = false,
      double contentHeight = 200,
    }) async {
      await tester.pumpWidget(
        _insetHost(
          (context) => showAppModalSheet<void>(
            context: context,
            selfSizing: selfSizing,
            builder: (_) => SizedBox(
              key: const Key('sheet_content'),
              height: contentHeight,
              child: const Text('sheet'),
            ),
          ),
          navBarInset: navBarInset,
          keyboardInset: keyboardInset,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('baseline: no inset (gesture nav) is unchanged',
        (tester) async {
      await openSheet(tester);
      // The sheet sits flush with the screen edge, exactly as before the fix.
      expect(
        contentBottom(tester),
        moreOrLessEquals(screenHeight(tester), epsilon: 1.0),
      );
    });

    testWidgets('3-button nav: content ends above the inset', (tester) async {
      const double inset = 48;
      await openSheet(tester, navBarInset: inset);

      // The regression assertion: before the fix this read screenHeight.
      expect(
        contentBottom(tester),
        lessThanOrEqualTo(screenHeight(tester) - inset),
        reason: 'sheet content must not be painted inside the system nav bar',
      );
    });

    testWidgets('the inset is applied exactly once, across a range',
        (tester) async {
      // Catches an inset that is applied but capped, halved or double-counted.
      for (final double inset in <double>[0, 24, 48, 68]) {
        await openSheet(tester, navBarInset: inset);
        expect(
          contentBottom(tester),
          moreOrLessEquals(screenHeight(tester) - inset, epsilon: 1.0),
          reason: 'wrong clearance at inset=$inset',
        );
        // Dismiss before the next iteration: re-pumping alone leaves the route
        // on the navigator, and the open sheet then swallows the tap that would
        // have opened the next one.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('selfSizing sheets get the same clearance', (tester) async {
      const double inset = 48;
      await openSheet(tester, navBarInset: inset, selfSizing: true);
      expect(
        contentBottom(tester),
        moreOrLessEquals(screenHeight(tester) - inset, epsilon: 1.0),
      );
    });

    testWidgets('keyboard and nav bar overlap rather than stack',
        (tester) async {
      // An open keyboard is drawn *over* the navigation bar, so the sheet is
      // lifted by the larger of the two — summing them would strand the
      // content a nav-bar's height above the keyboard.
      const double keyboard = 300;
      await openSheet(tester, navBarInset: 48, keyboardInset: keyboard);
      expect(
        contentBottom(tester),
        moreOrLessEquals(screenHeight(tester) - keyboard, epsilon: 1.0),
      );
    });

    testWidgets('a sheet taller than the cap still scrolls', (tester) async {
      // The inset comes off the height cap, so overall height still honours
      // maxHeightFactor — and the overflow scrolls instead of throwing.
      await openSheet(tester, navBarInset: 48, contentHeight: 4000);
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);

      final double height = screenHeight(tester);
      expect(
        tester.getRect(find.byType(SingleChildScrollView)).height,
        lessThanOrEqualTo(height * 0.85 + 1.0),
      );
    });
  });
}
