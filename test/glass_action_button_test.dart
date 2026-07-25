import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:attend_ease/widgets/glass_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _harness({required Brightness brightness, required VoidCallback onTap}) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: AdaptiveLiquidGlassLayer(
        settings: GlassNavTheme.settings(brightness),
        child: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          floatingActionButton: GlassActionButton(
            icon: Icons.add_rounded,
            label: 'Add record',
            onPressed: onTap,
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    final String name = brightness.name;

    testWidgets('$name: the action pill renders without throwing',
        (tester) async {
      await tester.pumpWidget(_harness(brightness: brightness, onTap: () {}));
      await tester.pumpAndSettle();

      // Uppercased to match the nav's tab labels, so the sentence-case string
      // passed in is deliberately not what gets painted.
      expect(find.text('ADD RECORD'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('$name: the pill hugs its label instead of filling the slot',
        (tester) async {
      await tester.pumpWidget(_harness(brightness: brightness, onTap: () {}));
      await tester.pumpAndSettle();

      // GlassButton centres its content in a bare Align, which has no
      // widthFactor and so takes every pixel it is offered. In a Scaffold's
      // FAB slot that offer is the whole screen, so without the IntrinsicWidth
      // wrapper this pill renders as a full-width slab.
      final Size pill = tester.getSize(find.byType(GlassActionButton));
      final double screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      expect(pill.width, lessThan(screenWidth / 2));
      expect(pill.height, GlassNavTheme.actionHeight);
    });

    testWidgets('$name: tapping the pill fires its callback', (tester) async {
      int taps = 0;
      await tester
          .pumpWidget(_harness(brightness: brightness, onTap: () => taps++));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GlassActionButton));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });
  }

  test('the pill is shorter than the bar it sits above', () {
    // At equal height it stops reading as a companion to the bar and starts
    // reading as a second, broken-off bar.
    expect(GlassNavTheme.actionHeight, lessThan(GlassNavTheme.barHeight));
    // Fully round, the same way barRadius is derived.
    expect(GlassNavTheme.actionRadius, GlassNavTheme.actionHeight / 2);
  });

  test('the pill shares the bar right edge', () {
    // This is most of why it reads as part of the bar rather than beside it.
    expect(GlassNavTheme.actionInset, GlassNavTheme.horizontalInset);
  });
}
