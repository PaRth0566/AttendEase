// Regression: tapping a far tab used to animate the tab it passed through.
//
// `PageView.onPageChanged` fires for *every* page the strip crosses, so a tap
// on Profile from Dashboard reported Calendar on the way. The icons were driven
// off that index, so the animation was spent on a tab the user never asked for
// and the destination's own play landed underneath it. The symptom was "a
// different tab's icon animates, and I have to tap twice" — the second tap hit
// the already-selected replay path, which worked.
//
// RootScreen now separates `_iconIndex` (arrivals) from `_currentIndex` (where
// the strip is), and these tests pin that distinction. They drive the real bar
// with the real icons; a play is only observable through [debugNavIcon],
// because the animation is painted rather than built and leaves nothing in the
// tree for a finder to match.
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:attend_ease/widgets/animated_nav_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const List<String> _names = ['dash', 'cal', 'prof'];

/// The bar as RootScreen configures it. [iconIndex] is RootScreen's
/// `_iconIndex`, [pagePosition] its `_pagePosition`, [epoch] its `_iconEpoch`.
Widget _harness({
  required int iconIndex,
  required double pagePosition,
  int epoch = 1,
}) {
  Widget icon(int i, bool filled) {
    final bool active = iconIndex == i;
    return switch (i) {
      1 => CalendarDaysIcon(filled: filled, active: active, epoch: epoch),
      2 => AvatarLookingAroundIcon(filled: filled, active: active, epoch: epoch),
      _ => DashboardMorphIcon(filled: filled, active: active, epoch: epoch),
    };
  }

  return LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: AdaptiveLiquidGlassLayer(
        settings: GlassNavTheme.settings(Brightness.dark),
        child: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassTabBar.bottom(
            selectedIndex: pagePosition.round(),
            alignmentOverride: (pagePosition / 2).clamp(0.0, 1.0) * 2 - 1,
            onTabSelected: (_) {},
            settings: GlassNavTheme.settings(Brightness.dark),
            barHeight: GlassNavTheme.barHeight,
            barBorderRadius: GlassNavTheme.barRadius,
            horizontalPadding: GlassNavTheme.horizontalInset,
            verticalPadding: GlassNavTheme.verticalInset,
            iconSize: GlassNavTheme.iconSize,
            maskingQuality: MaskingQuality.high,
            enableBlend: false,
            indicatorPinchStrength: 0,
            magnification: 1.0,
            pressScale: 1.0,
            tabs: [
              for (int i = 0; i < 3; i++)
                GlassTab(
                  icon: icon(i, false),
                  activeIcon: icon(i, true),
                  label: _names[i].toUpperCase(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Runs one tab change and returns the labels of the icons that played.
///
/// Mirrors RootScreen: the strip sweeps continuously, but `_iconIndex` moves
/// only on arrival at the destination.
Future<List<String>> _tapFrom(
  WidgetTester tester, {
  required int from,
  required int to,
  required List<String> log,
}) async {
  // Epoch 1 is the from-tab's own arrival; the destination bumps it to 2, as
  // RootScreen bumps _iconEpoch on each real arrival.
  await tester.pumpWidget(
      _harness(iconIndex: from, pagePosition: from.toDouble(), epoch: 1));
  await tester.pumpAndSettle();
  log.clear();

  const int steps = 20;
  for (int s = 1; s <= steps; s++) {
    final double pos = from + (to - from) * (s / steps);
    final bool arrived = pos.round() == to;
    await tester.pumpWidget(
      _harness(
        iconIndex: arrived ? to : from,
        pagePosition: pos,
        epoch: arrived ? 2 : 1,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  // Long enough for the slowest cycle (2.4s) to finish.
  await tester.pump(const Duration(milliseconds: 2600));

  return log
      .where((e) => e.startsWith('play '))
      .map((e) => e.substring(5))
      .toList();
}

void main() {
  final List<String> log = <String>[];
  setUp(() => debugNavIcon = log.add);
  tearDown(() => debugNavIcon = null);

  testWidgets('a tab change animates only the destination', (tester) async {
    for (int from = 0; from < 3; from++) {
      for (int to = 0; to < 3; to++) {
        if (from == to) continue;
        final List<String> played =
            await _tapFrom(tester, from: from, to: to, log: log);

        // Both copies of the destination play: the outline one in the base row
        // and the filled one in the pill-masked row. They must stay in step,
        // since the pill reveals the second as it travels over the first.
        expect(
          played.toSet(),
          {'${_names[to]}/rest', '${_names[to]}/FILL'},
          reason: '${_names[from]} -> ${_names[to]} should animate only '
              '${_names[to]}; a stray entry here is the pass-through bug back.',
        );
      }
    }
  });

  testWidgets('Dashboard to Profile does not animate Calendar in passing',
      (tester) async {
    // The specific reported case, kept as its own test so a failure names it.
    final List<String> played =
        await _tapFrom(tester, from: 0, to: 2, log: log);

    expect(played.where((p) => p.startsWith('cal/')), isEmpty);
    expect(played, contains('prof/FILL'));
  });

  testWidgets('leaving a tab parks its icon rather than letting it run',
      (tester) async {
    await tester.pumpWidget(_harness(iconIndex: 0, pagePosition: 0));
    await tester.pumpAndSettle();

    // Start Calendar playing, then leave 300ms into its 1.6s cycle.
    await tester.pumpWidget(_harness(iconIndex: 1, pagePosition: 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(log.where((e) => e.startsWith('play cal/')), isNotEmpty);

    log.clear();
    await tester.pumpWidget(_harness(iconIndex: 0, pagePosition: 0));
    await tester.pump();

    // Both copies must be parked. Without this the controller kept running,
    // and the outline copy of a tab is on screen the whole time — so an icon
    // you had just left went on animating from a tab you were no longer on.
    expect(
      log.where((e) => e.startsWith('stop cal/')).toList(),
      hasLength(2),
      reason: 'both the outline and the filled copy of Calendar should stop',
    );
  });

  // The `prof -> dash` device failure: the package tears down a tab's filled
  // copy while the pill is away from it and rebuilds it as the pill arrives, so
  // that copy is *born* selected with no live false->true edge to watch. These
  // pin the born-active rule directly, since the exact coalesced frame is not
  // reproducible through the package's own internal alignment animation.
  Future<void> mountFresh(WidgetTester tester,
      {required bool active, required int epoch}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: const IconThemeData(color: Color(0xFFFFFFFF), size: 26),
          child: Center(
            child:
                DashboardMorphIcon(filled: true, active: active, epoch: epoch),
          ),
        ),
      ),
    );
    await tester.pump(); // let the deferred born-active play fire
  }

  testWidgets('an icon born active at a real epoch still plays', (tester) async {
    log.clear();
    await mountFresh(tester, active: true, epoch: 2);
    expect(log.where((e) => e == 'play dash/FILL'), isNotEmpty);
  });

  testWidgets('the cold-start tab (epoch 0) does not play on mount',
      (tester) async {
    log.clear();
    await mountFresh(tester, active: true, epoch: 0);
    expect(log.where((e) => e.startsWith('play')), isEmpty);
  });

  testWidgets('an inactive icon does not play on mount', (tester) async {
    log.clear();
    await mountFresh(tester, active: false, epoch: 2);
    expect(log.where((e) => e.startsWith('play')), isEmpty);
  });
}
