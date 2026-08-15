// Where the calendar's "record deleted" SnackBar lands.
//
// The undo bar has to be reachable, which means it must not sit under the
// floating stack at the bottom of the calendar — the glass nav bar and the
// "Add record" pill above it. Getting that right depends on a piece of Flutter
// behaviour that is easy to reason about backwards, so it is pinned here:
//
//   * `ScaffoldMessenger` presents a SnackBar in the **root** Scaffold of a
//     nested set, not the nearest one. The calendar's own Scaffold never
//     renders it — RootScreen's does.
//   * That root Scaffold already subtracts its `bottomNavigationBar`'s height
//     before positioning a floating bar, so the nav bar needs no allowance in
//     the margin. Adding one (the intuitive move) lifts the bar a further ~86px
//     and it floats loose in the middle of the record list.
//   * It knows nothing about the "Add record" pill, which belongs to the inner
//     Scaffold. That is the one thing the margin has to pay for, and it is what
//     `GlassNavTheme.snackBarPillClearance` is.
//
// The assertions below are written against the nav-stack constants rather than
// against the margin, so the two have to agree for the test to pass.

import 'package:attend_ease/theme/app_dimens.dart';
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// RootScreen's nesting, reduced to its geometry: an outer Scaffold carrying the
/// bottom bar, an inner Scaffold carrying the page and its action pill.
Widget _harness({
  required GlobalKey<ScaffoldMessengerState> messengerKey,
  double viewportWidth = 800,
}) {
  return MaterialApp(
    scaffoldMessengerKey: messengerKey,
    theme: AppTheme.withResponsiveOverlays(AppTheme.lightTheme, viewportWidth),
    home: Scaffold(
      // As in RootScreen: content scrolls under the glass rather than being
      // inset above it.
      extendBody: true,
      bottomNavigationBar: const SizedBox(
        // What GlassTabBar.bottom measures: a barHeight-tall bar inside
        // EdgeInsets.symmetric(vertical: verticalInset).
        height: 2 * GlassNavTheme.verticalInset + GlassNavTheme.barHeight,
        width: double.infinity,
      ),
      body: Scaffold(
        body: const SizedBox.expand(),
        // Stands in for the calendar's GlassActionButton. Only its presence
        // matters here: the point of the test is that the *root* Scaffold's
        // layout cannot see it.
        floatingActionButton: SizedBox(
          height: GlassNavTheme.actionHeight,
          child: FloatingActionButton.extended(
            onPressed: () {},
            label: const Text('Add record'),
          ),
        ),
      ),
    ),
  );
}

/// The calendar's undo bar, configured exactly as `_showUndoSnackBar` does.
SnackBar _undoBar() {
  return SnackBar(
    duration: const Duration(seconds: 5),
    margin: const EdgeInsets.only(
      left: AppDimens.space16,
      right: AppDimens.space16,
      bottom: GlassNavTheme.snackBarPillClearance,
    ),
    content: const Text('Software Engineering · Present deleted'),
    action: SnackBarAction(label: 'Undo', onPressed: () {}),
  );
}

void main() {
  testWidgets('the undo bar is presented once, in the root Scaffold', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(_harness(messengerKey: messengerKey));

    messengerKey.currentState!.showSnackBar(_undoBar());
    await tester.pumpAndSettle();

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason:
          'nested Scaffolds must not each render their own copy — two '
          'stacked bars would mean two Undo buttons for one deleted record',
    );
  });

  testWidgets('the undo bar clears the nav bar and the action pill', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(_harness(messengerKey: messengerKey));

    messengerKey.currentState!.showSnackBar(_undoBar());
    await tester.pumpAndSettle();

    final double screenBottom = tester.getSize(find.byType(MaterialApp)).height;
    // The pill's top edge, measured up from the screen edge: the bar floats
    // verticalInset off the edge, then the pill stands actionGap above the
    // bar's glass and is actionHeight tall.
    const double pillTop =
        GlassNavTheme.verticalInset +
        GlassNavTheme.barHeight +
        GlassNavTheme.actionGap +
        GlassNavTheme.actionHeight;

    // The visible bar, not its margin box — SnackBar renders `margin` as padding
    // around itself, so the Material is what the user can actually reach.
    final Rect bar = tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(
      bar.bottom,
      lessThanOrEqualTo(screenBottom - pillTop),
      reason:
          'the bar must sit above the "Add record" pill, or the pill covers '
          'the Undo action it is offering',
    );

    // …and not so far above that it has left the bottom of the screen behind.
    // One pill height of slack is the gap the margin deliberately adds; more
    // than a nav bar on top of that means the nav clearance got double-counted.
    expect(
      bar.bottom,
      greaterThan(screenBottom - pillTop - GlassNavTheme.barHeight),
      reason:
          'the nav bar is already covered by the root Scaffold; adding it '
          'to the margin again strands the bar mid-list',
    );

    // Horizontally the bar is governed by AppTheme.snackBarMaxWidth, not by the
    // margin's left/right. Flutter drops a floating SnackBar's horizontal margin
    // whenever a width is in play — "If width is provided, do not include
    // horizontal margins", snack_bar.dart — and takes that width from
    // `widget.width ?? snackBarTheme.width`, so the theme's cap reaches this bar
    // even though it only ever asked for a margin. The margin's *bottom*, which
    // is the clearance this test exists for, is kept either way and is asserted
    // above.
    //
    // That cap is the point: this bar used to be viewport-minus-32, which on a
    // 1568px desktop browser meant a 1536px navy band across the page rather
    // than an undo chip.
    final double screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    expect(
      bar.width,
      lessThanOrEqualTo(AppTheme.snackBarMaxWidth),
      reason: 'the undo bar must stay a chip, not stretch with the viewport',
    );
    expect(
      bar.left,
      moreOrLessEquals(screenWidth - bar.right, epsilon: 0.01),
      reason: 'a capped bar is centred, so its two side gaps must match',
    );
  });

  testWidgets('the undo bar stays reachable when the OS reserves a nav inset', (
    tester,
  ) async {
    // A 3-button Android nav bar: RootScreen pads the glass bar by viewPadding,
    // and the root Scaffold's floating-bar math has to absorb that too.
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: _harness(messengerKey: messengerKey, viewportWidth: 400),
      ),
    );

    messengerKey.currentState!.showSnackBar(_undoBar());
    await tester.pumpAndSettle();

    final Rect bar = tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(bar.top, greaterThan(0), reason: 'not pushed off the top');
    expect(bar.bottom, lessThan(800), reason: 'not below the screen edge');
  });
}
