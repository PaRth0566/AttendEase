import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The nav bar lives inside RootScreen, which pulls in three database-backed
/// tab screens. These tests exercise the bar in isolation with the exact
/// configuration RootScreen gives it — enough to catch the package failing to
/// build, paint, or report taps under this Flutter version.
Widget _harness({
  required int selectedIndex,
  required ValueChanged<int> onTabSelected,
  Brightness brightness = Brightness.light,
}) {
  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          return AdaptiveLiquidGlassLayer(
            settings: GlassNavTheme.settings(brightness),
            child: Scaffold(
              extendBody: true,
              body: ListView(
                children: List.generate(
                  30,
                  (i) => ListTile(title: Text('row $i')),
                ),
              ),
              bottomNavigationBar: GlassTabBar.bottom(
                selectedIndex: selectedIndex,
                onTabSelected: onTabSelected,
                settings: GlassNavTheme.settings(brightness),
                selectedIconColor: GlassNavTheme.selectedIcon(brightness),
                selectedLabelColor: GlassNavTheme.selectedLabel(brightness),
                unselectedIconColor:
                    GlassNavTheme.unselectedContent(brightness),
                unselectedLabelColor:
                    GlassNavTheme.unselectedContent(brightness),
                indicatorColor: GlassNavTheme.selectionTint(brightness),
                indicatorSettings:
                    GlassNavTheme.selectionSettings(brightness),
                barHeight: GlassNavTheme.barHeight,
                barBorderRadius: GlassNavTheme.barRadius,
                horizontalPadding: GlassNavTheme.horizontalInset,
                verticalPadding: GlassNavTheme.verticalInset,
                iconSize: GlassNavTheme.iconSize,
                tabs: [
                  GlassTab(
                    icon: const Icon(Icons.dashboard_outlined),
                    activeIcon: const Icon(Icons.dashboard_rounded),
                    label: 'DASHBOARD',
                  ),
                  GlassTab(
                    icon: const Icon(Icons.calendar_month_outlined),
                    activeIcon: const Icon(Icons.calendar_month_rounded),
                    label: 'CALENDAR',
                  ),
                  GlassTab(
                    icon: const Icon(Icons.person_outline_rounded),
                    activeIcon: const Icon(Icons.person_rounded),
                    label: 'PROFILE',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  // The bar cross-fades between selected and unselected variants, so a label
  // can be mounted once or twice depending on the tab. That count is package
  // internals — assert only that each label is present.

  testWidgets('glass nav bar renders all three tabs without throwing',
      (tester) async {
    await tester.pumpWidget(_harness(selectedIndex: 0, onTabSelected: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsWidgets);
    expect(find.text('CALENDAR'), findsWidgets);
    expect(find.text('PROFILE'), findsWidgets);
    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    // The shader pipeline compiling and painting is the real risk here.
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark theme too', (tester) async {
    await tester.pumpWidget(_harness(
      selectedIndex: 2,
      onTabSelected: (_) {},
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE'), findsWidgets);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      _harness(selectedIndex: 0, onTabSelected: taps.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CALENDAR').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROFILE').first);
    await tester.pumpAndSettle();

    expect(taps, [1, 2]);
  });

  testWidgets('extendBody reports the bar height as body bottom padding',
      (tester) async {
    late double bottomPadding;
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: AdaptiveLiquidGlassLayer(
            child: Scaffold(
              extendBody: true,
              body: Builder(builder: (context) {
                bottomPadding = MediaQuery.paddingOf(context).bottom;
                return const SizedBox.shrink();
              }),
              bottomNavigationBar: GlassTabBar.bottom(
                selectedIndex: 0,
                onTabSelected: (_) {},
                tabs: const [
                  GlassTab(icon: Icon(Icons.home), label: 'A'),
                  GlassTab(icon: Icon(Icons.search), label: 'B'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // This is what the three tab screens add to their scroll padding, so if it
    // ever came back as zero their last row would sit under the glass.
    expect(bottomPadding, greaterThan(0));
  });
}
