// Regression: dragging the pill along the bar must move it.
//
// The AttendEase `alignmentOverride` patch drives the pill from RootScreen's
// PageController, and it was written as `alignmentOverride ?? tabXAlign` — so
// once RootScreen passes an override (which it always does), the override wins
// unconditionally and the bar's own drag gesture, which only ever writes
// `tabXAlign`, can no longer move the pill. The pill stayed frozen under the
// finger and only snapped at release.
//
// The fix gives an in-progress bar drag precedence over the override, handing
// control back once the page position has caught up to the released tab.
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The bar as RootScreen configures it, but in `off` masking mode so the pill
/// is a plain [AnimatedGlassIndicator] whose `alignment` is readable. The
/// override/drag precedence under test is shared by both masking modes.
Widget _harness({
  required double alignmentOverride,
  required ValueChanged<int> onTabSelected,
}) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: AdaptiveLiquidGlassLayer(
        settings: GlassNavTheme.settings(Brightness.dark),
        child: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassTabBar.bottom(
            selectedIndex: 0,
            alignmentOverride: alignmentOverride,
            onTabSelected: onTabSelected,
            settings: GlassNavTheme.settings(Brightness.dark),
            barHeight: GlassNavTheme.barHeight,
            barBorderRadius: GlassNavTheme.barRadius,
            horizontalPadding: GlassNavTheme.horizontalInset,
            verticalPadding: GlassNavTheme.verticalInset,
            iconSize: GlassNavTheme.iconSize,
            maskingQuality: MaskingQuality.off,
            tabs: const [
              GlassTab(icon: Icon(Icons.dashboard), label: 'A'),
              GlassTab(icon: Icon(Icons.calendar_month), label: 'B'),
              GlassTab(icon: Icon(Icons.person), label: 'C'),
            ],
          ),
        ),
      ),
    ),
  );
}

double _pillX(WidgetTester tester) {
  final dynamic indicator = tester
      .widgetList(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'AnimatedGlassIndicator'))
      .first;
  return (indicator.alignment as Alignment).x;
}

void main() {
  testWidgets('dragging the bar moves the pill off the override position',
      (tester) async {
    // Override pins the pill to tab 0 (alignment -1). A bar drag must still win.
    await tester.pumpWidget(_harness(alignmentOverride: -1, onTabSelected: (_) {}));
    await tester.pumpAndSettle();

    final Rect bar = tester.getRect(find.byType(GlassTabBar));
    // Grab near the left (tab 0, where the pill is) and drag toward tab 2.
    final gesture = await tester.startGesture(
      Offset(bar.left + bar.width * 0.2, bar.center.dy),
    );
    await tester.pump();
    await gesture.moveBy(Offset(bar.width * 0.55, 0));
    // Successive frames so the pill's tracking spring can travel from the
    // override position toward the finger.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      _pillX(tester),
      greaterThan(-0.5),
      reason: 'the pill should follow the finger, not stay pinned at -1',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('releasing a drag selects the dragged-to tab', (tester) async {
    int? selected;
    await tester
        .pumpWidget(_harness(alignmentOverride: -1, onTabSelected: (i) => selected = i));
    await tester.pumpAndSettle();

    final Rect bar = tester.getRect(find.byType(GlassTabBar));
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.2, bar.center.dy),
      Offset(bar.width * 0.6, 0),
    );
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected, greaterThan(0));
  });
}
