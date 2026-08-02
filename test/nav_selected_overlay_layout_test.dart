// Regression: the selected-tab layer must be laid out at the FULL bar width in
// `MaskingQuality.off`, exactly as it is in `.high`.
//
// `tab_bar_bottom_layout._buildSelectedTabs` returns a full-width `Row` of
// `tabCount` `Expanded` children — that is the contract `_buildHighQualityMode`
// consumes, which hands it a `Positioned.fill`. `_buildSimpleMode` instead put
// the same row inside `FractionallySizedBox(widthFactor: 1 / tabCount)`, i.e. a
// third of the bar, so all three tabs were squeezed into one tab's slot: three
// icons and three labels crammed on top of each other inside the pill.
//
// It stayed invisible while RootScreen pinned `maskingQuality` to `.high`. The
// moment it started swapping to `.off` mid-slide, the cram became visible on
// every swipe.
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _harness({
  required double alignmentOverride,
  required MaskingQuality maskingQuality,
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
            onTabSelected: (_) {},
            settings: GlassNavTheme.settings(Brightness.dark),
            barHeight: GlassNavTheme.barHeight,
            barBorderRadius: GlassNavTheme.barRadius,
            horizontalPadding: GlassNavTheme.horizontalInset,
            verticalPadding: GlassNavTheme.verticalInset,
            iconSize: GlassNavTheme.iconSize,
            maskingQuality: maskingQuality,
            tabs: const [
              GlassTab(icon: Icon(Icons.dashboard), label: 'DASHBOARD'),
              GlassTab(icon: Icon(Icons.calendar_month), label: 'CALENDAR'),
              GlassTab(icon: Icon(Icons.person), label: 'PROFILE'),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Widths of every tab item the bar currently has mounted, across both rows.
/// `BottomBarTabItem` is package-internal, so it is matched by runtime type —
/// the same trick `nav_pill_drag_test.dart` uses for `AnimatedGlassIndicator`.
List<double> _tabItemWidths(WidgetTester tester) {
  final Finder items = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'BottomBarTabItem',
  );
  return <double>[
    for (int i = 0; i < items.evaluate().length; i++)
      tester.getSize(items.at(i)).width,
  ];
}

void main() {
  for (final MaskingQuality quality in MaskingQuality.values) {
    testWidgets('every tab item is one full tab slot wide in $quality',
        (tester) async {
      await tester.pumpWidget(
        _harness(alignmentOverride: -1, maskingQuality: quality),
      );
      await tester.pumpAndSettle();

      final List<double> widths = _tabItemWidths(tester);
      // Both rows are mounted (the selected one renders only the tabs near the
      // pill), so there are more than the three unselected items.
      expect(widths.length, greaterThan(3));

      // Every item, in either row, occupies exactly one slot. A selected row
      // laid out at a third of the bar makes its items a third of this.
      final double slot = widths.reduce((a, b) => a > b ? a : b);
      for (final double w in widths) {
        expect(w, moreOrLessEquals(slot, epsilon: 0.5));
      }
    });
  }
}
