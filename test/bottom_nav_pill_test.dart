// Regression: the selection pill vanished for the whole length of a page swipe.
//
// Dragging a page slowly made the light-grey capsule behind the selected tab
// disappear in a single frame, while the icon and label kept their selected
// blue. It came back, animated, only once the page settled. Tapping was fine.
//
// The cause was two different notions of "draw the pill" in the same bar.
// [MaskingQuality.high] paints the pill in two passes — an unconditional
// background chip plus a travelling glass lens — but [MaskingQuality.off]
// carried only ONE indicator, gated on `thickness > 0.05`.
//
// `thickness` is the jelly spring, and it only rises when the pill has catching
// up to do: `tabIsDown || (alignment.x - targetAlignment).abs() > 0.05`. A
// page-driven `alignmentOverride` satisfies neither term. `tabIsDown` is false
// because the finger is on the page, not on the bar; and the override is fed to
// the tracking spring as its *target* with `active: true`, so it tracks with no
// lag and the separation never opens up. So `thickness` sat at 0 for the entire
// gesture — and since RootScreen drops to `.off` the moment the page is more
// than 0.02 off a whole tab, the one gated indicator was simply not built.
//
// That is the asymmetry the bug report measured: out is a `switch` dropping a
// widget (instant, one frame), back in is `.high` returning with its background
// opacity easing up (~700 ms). The icon and label never flickered because they
// come from `selectedIndex`, which never consults `thickness`.
//
// These tests drive a real [PageView] wired exactly as RootScreen wires it, so
// the drag is a genuine page swipe and the `.off`/`.high` swap happens for real.
// Asserting mid-gesture is the whole point: `pumpAndSettle` with the finger
// down would hide the bug (and hang on the drag's own ticker).
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

/// The key carried by the resting pill in both masking modes.
const Key kPill = Key('nav_selection_pill');

final Finder _pill = find.byKey(kPill);

final Finder _travellingGlassPill = find.byWidgetPredicate(
  (widget) => widget is AnimatedGlassIndicator && widget.paintGlass,
);

/// A miniature RootScreen: a real [PageView] whose controller drives the bar's
/// `alignmentOverride` and `maskingQuality` per frame, exactly as RootScreen's
/// `_onPageScroll` / `_pagePosition` do.
class _NavHarness extends StatefulWidget {
  const _NavHarness();

  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  final PageController _controller = PageController();
  final ValueNotifier<double> _pagePosition = ValueNotifier<double>(0);
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final double? page = _controller.page;
      if (page != null) _pagePosition.value = page;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pagePosition.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassWidgets.wrap(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: AdaptiveLiquidGlassLayer(
          settings: GlassNavTheme.settings(Brightness.dark),
          child: Scaffold(
            extendBody: true,
            body: PageView.builder(
              controller: _controller,
              itemCount: 3,
              pageSnapping: true,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => Center(child: Text('page $i')),
            ),
            bottomNavigationBar: ValueListenableBuilder<double>(
              valueListenable: _pagePosition,
              builder: (context, pagePosition, _) {
                // RootScreen's own masking swap, verbatim: `.high` only within
                // 0.02 of a whole tab, `.off` for everything in between. This is
                // what puts the bar in the buggy branch for the whole drag.
                final double offTab =
                    (pagePosition - pagePosition.roundToDouble()).abs();
                return GlassTabBar.bottom(
                  selectedIndex: _currentIndex,
                  alignmentOverride: (pagePosition / 2).clamp(0.0, 1.0) * 2 - 1,
                  onTabSelected: _onTabSelected,
                  settings: GlassNavTheme.settings(Brightness.dark),
                  barHeight: GlassNavTheme.barHeight,
                  barBorderRadius: GlassNavTheme.barRadius,
                  horizontalPadding: GlassNavTheme.horizontalInset,
                  verticalPadding: GlassNavTheme.verticalInset,
                  iconSize: GlassNavTheme.iconSize,
                  iconLabelSpacing: 3,
                  indicatorColor: Colors.white.withValues(alpha: 0.12),
                  maskingQuality: offTab < 0.02
                      ? MaskingQuality.high
                      : MaskingQuality.off,
                  enableBlend: false,
                  indicatorPinchStrength: 0,
                  magnification: 1.0,
                  pressScale: 1.0,
                  selectedIconColor: GlassNavTheme.selectedIcon(
                    Brightness.dark,
                  ),
                  selectedLabelColor: GlassNavTheme.selectedLabel(
                    Brightness.dark,
                  ),
                  unselectedIconColor: GlassNavTheme.unselectedContent(
                    Brightness.dark,
                  ),
                  unselectedLabelColor: GlassNavTheme.unselectedContent(
                    Brightness.dark,
                  ),
                  labelFontSize: GlassNavTheme.labelSize,
                  tabs: const [
                    GlassTab(
                      icon: Icon(Icons.dashboard_outlined),
                      activeIcon: Icon(Icons.dashboard),
                      label: 'DASHBOARD',
                    ),
                    GlassTab(
                      icon: Icon(Icons.calendar_month_outlined),
                      activeIcon: Icon(Icons.calendar_month),
                      label: 'CALENDAR',
                    ),
                    GlassTab(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'PROFILE',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill's horizontal alignment, in the indicator's -1…1 space.
double _pillAlignment(WidgetTester tester) {
  final dynamic indicator = tester.widget(_pill);
  return (indicator.alignment as Alignment).x;
}

void main() {
  testWidgets('1. pill exists at rest on the initial tab', (tester) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();

    expect(_pill, findsOneWidget);
    // Tab 0 of 3 sits at the far left of the alignment space.
    expect(_pillAlignment(tester), closeTo(-1.0, 0.01));
  });

  testWidgets('2. pill still exists mid-drag, finger down', (tester) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();
    expect(_pill, findsOneWidget, reason: 'baseline: pill present at rest');

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset centre = Offset(size.width / 2, size.height / 2);

    final TestGesture gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(-120, 0)); // partial drag, still holding
    await tester.pump(); // one frame — deliberately NOT pumpAndSettle

    expect(
      _pill,
      findsOneWidget,
      reason: 'the pill must not disappear while the page is being dragged',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('2b. slow page drag keeps the glass rim visibly active', (
    tester,
  ) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final TestGesture gesture = await tester.startGesture(centre);

    for (int frame = 0; frame < 40; frame++) {
      await gesture.moveBy(const Offset(-3, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // By frame 10 the page is outside RootScreen's 0.02 resting window,
      // where the low-cost masking branch previously dropped only the rim.
      if (frame >= 10) {
        expect(_pill, findsOneWidget);
        expect(
          _travellingGlassPill,
          findsOneWidget,
          reason: 'the glass rim must remain mounted during a slow page drag',
        );
        final AnimatedGlassIndicator lens = tester
            .widget<AnimatedGlassIndicator>(_travellingGlassPill);
        expect(
          lens.thickness,
          lessThanOrEqualTo(0.05),
          reason: 'the slow-drag fix must not change the interaction spring',
        );
        expect(lens.glassVisibilityOverride, 1.0);
        expect(lens.velocity, 0.0);

        final Finder rimEffect = find.descendant(
          of: _travellingGlassPill,
          matching: find.byType(GlassEffect),
        );
        expect(rimEffect, findsOneWidget);
        final GlassEffect effect = tester.widget<GlassEffect>(rimEffect);
        expect(effect.settings.visibility, 1.0);
        expect(effect.interactionIntensity, lessThanOrEqualTo(0.05));
      }
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('3. pill exists across the whole range of drag offsets', (
    tester,
  ) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final TestGesture gesture = await tester.startGesture(centre);

    // Absolute fractions of the screen width, converted to per-step deltas so
    // the finger walks the drag rather than jumping.
    const List<double> fractions = [0.10, 0.25, 0.50, 0.75];
    double travelled = 0;
    for (final double f in fractions) {
      final double target = size.width * f;
      await gesture.moveBy(Offset(-(target - travelled), 0));
      travelled = target;
      await tester.pump();

      expect(
        _pill,
        findsOneWidget,
        reason:
            'pill missing at ${(f * 100).round()}% of the drag — '
            'there must be no gap at any point in the gesture',
      );
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('4. pill survives the swipe and lands on the new tab', (
    tester,
  ) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();
    expect(_pillAlignment(tester), closeTo(-1.0, 0.01));

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Offset centre = Offset(size.width / 2, size.height / 2);

    // A committing swipe: far enough past the snap threshold to land on tab 1.
    final TestGesture gesture = await tester.startGesture(centre);
    await gesture.moveBy(Offset(-size.width * 0.6, 0));
    await tester.pump();
    expect(_pill, findsOneWidget, reason: 'still present mid-swipe');
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_pill, findsOneWidget, reason: 'still present once settled');
    // Tab 1 of 3 is the centre of the alignment space.
    expect(
      _pillAlignment(tester),
      closeTo(0.0, 0.05),
      reason: 'the pill should have followed the page onto CALENDAR',
    );
    expect(find.text('page 1'), findsOneWidget);
  });

  testWidgets('5. tapping a nav item still selects it and keeps the pill', (
    tester,
  ) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('PROFILE'));
    await tester.pumpAndSettle();

    expect(_pill, findsOneWidget);
    // Tab 2 of 3 sits at the far right.
    expect(
      _pillAlignment(tester),
      closeTo(1.0, 0.05),
      reason: 'tapping PROFILE should move the pill to the last tab',
    );
    expect(find.text('page 2'), findsOneWidget);
  });
}
