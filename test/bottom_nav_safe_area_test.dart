// Regression: the floating nav capsule was painted *inside* the Android
// 3-button system navigation bar.
//
// The app renders edge-to-edge, so on a device with a transparent system bar
// the window extends behind the buttons and the Scaffold's bottom edge is the
// physical screen edge. `GlassTabBar`'s `verticalPadding`
// (`GlassNavTheme.verticalInset`) is a fixed design margin measured from that
// edge, so the capsule sat over the back / home / recents glyphs — 44 px into a
// 68 px inset on the reported device. On gesture-nav and opaque-bar devices
// `viewPadding.bottom` is 0 (the OS shrinks the window itself), so the same
// constant happened to land correctly and nothing looked wrong there.
//
// The fix wraps the bar in a `Padding` of `MediaQuery.viewPaddingOf(context)
// .bottom` in `RootScreen`. `viewPadding` rather than `padding` because
// `padding` is consumed by ancestor `SafeArea`s and collapses when the keyboard
// is up, while `viewPadding` is the raw OS inset no ancestor can eat.
//
// ## Why this pumps the bar rather than `RootScreen`
//
// `RootScreen` constructs `CloudSyncService` (Firebase) in `initState`, and its
// three tab pages each open the sqflite database, neither of which exists in a
// widget test. Every other nav test in this suite (`nav_pill_drag_test.dart`,
// `nav_selected_overlay_layout_test.dart`, ...) takes the same approach: pump
// the real `Scaffold` + `GlassTabBar` composition with the exact arguments
// `RootScreen` passes. What is under test here is the *layout arithmetic*
// around the bar, and that arithmetic is reproduced verbatim below — including
// the `Padding` the fix adds and the `Key('bottom_nav_bar')` it carries.
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The nav bar as `RootScreen` builds it, under a `MediaQuery` that reports
/// [bottomInset] as the system navigation-bar inset.
///
/// `viewPadding` *and* `padding` are both set, as a real device reports them
/// when nothing has consumed the inset — that also proves the fix reads the
/// value that survives an ancestor `SafeArea`.
Widget _harness({
  required double bottomInset,
  required int selectedIndex,
  required ValueChanged<int> onTabSelected,
}) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(411, 866),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
          padding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Builder(
          builder: (context) => AdaptiveLiquidGlassLayer(
            settings: GlassNavTheme.settings(Brightness.dark),
            child: Scaffold(
              extendBody: true,
              body: const SizedBox.expand(),
              // ── The composition under test, mirroring RootScreen ──────
              bottomNavigationBar: Padding(
                key: const Key('bottom_nav_bar'),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: GlassTabBar.bottom(
                  selectedIndex: selectedIndex,
                  onTabSelected: onTabSelected,
                  settings: GlassNavTheme.settings(Brightness.dark),
                  barHeight: GlassNavTheme.barHeight,
                  barBorderRadius: GlassNavTheme.barRadius,
                  horizontalPadding: GlassNavTheme.horizontalInset,
                  verticalPadding: GlassNavTheme.verticalInset,
                  iconSize: GlassNavTheme.iconSize,
                  maskingQuality: MaskingQuality.off,
                  tabs: const [
                    GlassTab(icon: Icon(Icons.dashboard), label: 'DASHBOARD'),
                    GlassTab(
                      icon: Icon(Icons.calendar_month),
                      label: 'CALENDAR',
                    ),
                    GlassTab(icon: Icon(Icons.person), label: 'PROFILE'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The bottom edge of the visible glass capsule.
///
/// Deliberately **not** `find.byType(GlassTabBar)`: the bar's own
/// `verticalPadding` is applied *inside* it
/// (`tab_bar_bottom_layout.dart:204`), so the `GlassTabBar` element's rect is
/// the full-width layout box and its bottom edge is the screen edge on every
/// device — it would read 600.0 whether the capsule floats correctly or not.
/// Nor the `Key('bottom_nav_bar')` wrapper, which by design extends *into* the
/// inset; that extension is what lifts its child.
///
/// The capsule is the `SizedBox(height: barHeight)` the package builds just
/// inside that padding. It is package-internal, so it is located by its
/// resolved height — matching by runtime type is the convention the rest of
/// this suite uses for internals (see `nav_selected_overlay_layout_test.dart`).
double _capsuleBottom(WidgetTester tester) {
  final Finder capsule = find.descendant(
    of: find.byType(GlassTabBar),
    matching: find.byWidgetPredicate(
      (w) => w is SizedBox && w.height == GlassNavTheme.barHeight,
    ),
  );
  expect(
    capsule,
    findsWidgets,
    reason: 'the barHeight-tall capsule box should be mounted',
  );
  return tester.getRect(capsule.first).bottom;
}

/// Logical screen height, matching the harness `MediaQuery.size`.
double _screenHeight(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio;

void main() {
  testWidgets('baseline: no inset (gesture nav / opaque bar) is unchanged',
      (tester) async {
    await tester.pumpWidget(
      _harness(bottomInset: 0, selectedIndex: 0, onTabSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    // With no inset the capsule floats GlassNavTheme.verticalInset off the
    // screen edge, exactly as it does today. The fix must not move it here.
    expect(
      _capsuleBottom(tester),
      moreOrLessEquals(
        _screenHeight(tester) - GlassNavTheme.verticalInset,
        epsilon: 1.0,
      ),
    );
  });

  testWidgets('3-button nav: the capsule clears the system inset',
      (tester) async {
    const double inset = 48;
    await tester.pumpWidget(
      _harness(bottomInset: inset, selectedIndex: 0, onTabSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    // The regression assertion: the capsule must end at or above the top of
    // the system inset. Before the fix it ended at screenHeight - 14.
    expect(
      _capsuleBottom(tester),
      lessThanOrEqualTo(_screenHeight(tester) - inset),
      reason: 'the nav capsule must not be painted inside the system nav bar',
    );
  });

  testWidgets('the capsule moves up by exactly the inset', (tester) async {
    const double inset = 48;

    await tester.pumpWidget(
      _harness(bottomInset: 0, selectedIndex: 0, onTabSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    final double withoutInset = _capsuleBottom(tester);

    await tester.pumpWidget(
      _harness(bottomInset: inset, selectedIndex: 0, onTabSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    final double withInset = _capsuleBottom(tester);

    // Proportional to the inset, not a hard-coded shove: the design margin is
    // preserved and the inset is added on top of it, once.
    expect(
      withoutInset - withInset,
      moreOrLessEquals(inset, epsilon: 1.0),
    );
  });

  testWidgets('the capsule clears a range of insets', (tester) async {
    // Catches an inset that is applied but capped, halved or double-counted.
    for (final double inset in <double>[0, 24, 48, 64]) {
      await tester.pumpWidget(
        _harness(bottomInset: inset, selectedIndex: 0, onTabSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(
        _capsuleBottom(tester),
        lessThanOrEqualTo(_screenHeight(tester) - inset),
        reason: 'capsule intrudes into the system inset at inset=$inset',
      );
      // Applied exactly once — a double-count would lift it by 2 * inset.
      expect(
        _capsuleBottom(tester),
        moreOrLessEquals(
          _screenHeight(tester) - inset - GlassNavTheme.verticalInset,
          epsilon: 1.0,
        ),
        reason: 'the design margin must survive alongside the inset',
      );
    }
  });

  testWidgets('tab targets are still hit-testable at the lifted position',
      (tester) async {
    const double inset = 48;
    int? selected;
    await tester.pumpWidget(
      _harness(
        bottomInset: inset,
        selectedIndex: 0,
        onTabSelected: (i) => selected = i,
      ),
    );
    await tester.pumpAndSettle();

    // The hit region moved with the paint: tapping CALENDAR where it now sits
    // selects it, rather than the tap falling through to where it used to be.
    //
    // `.first` because the bar mounts the label twice — the unselected row and
    // the selected row that gets clipped to the pill are both in the tree, at
    // the same position. Either copy is over the same tap target.
    await tester.tap(find.text('CALENDAR').first);
    await tester.pumpAndSettle();

    expect(selected, 1);
  });
}
