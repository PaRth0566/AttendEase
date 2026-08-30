// navbar_light_theme_test.dart
//
// Pixel-level regression test for the LIGHT THEME bottom navigation bar.
// Rasterizes the real navbar widget and asserts that nothing in it ever
// goes dark: not the selected-tab indicator, not the bar surface.
//
// Put this at:  test/navbar_light_theme_test.dart
// Run it with:  flutter test test/navbar_light_theme_test.dart
//
// -----------------------------------------------------------------------
// READ THIS FIRST
// -----------------------------------------------------------------------
// Text in `flutter test` is drawn with the test font, where every glyph is
// a solid black box. That is expected and harmless here: every hard
// assertion below probes regions that cannot contain a glyph (the strip
// above the icons, the inner left/right edges, the gutters between tabs),
// and the aggregate checks use thresholds with room for glyph coverage.
//
// A widget test runs on the host, not in a browser, so it catches the
// colour-resolution and layout causes of this bug (which are plain Dart and
// reproduce everywhere) but not renderer-specific behaviour such as
// BackdropFilter being a no-op on web or a hover overlay sticking after
// touch. Verify those in Chrome by hand; see the checklist in the bug doc.
// -----------------------------------------------------------------------

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

// =======================================================================
// ADAPT THIS BLOCK TO THE PROJECT, THEN DELETE THE `throw` LINES
// =======================================================================

/// Number of tabs in the bar.
const int kTabCount = 3;

/// Must return the app's real light ThemeData, not a hand-rolled one.
ThemeData buildLightThemeUnderTest() => AppTheme.lightTheme;

/// Returns the app's real bottom navbar — the same `GlassTabBar.bottom`
/// RootScreen builds, with the light-web treatment RootScreen applies to it:
/// the opaque white capsule pad behind the glass and the glow disabled. The
/// widget test cannot see `kIsWeb` as true on the host, so the light-web path
/// is forced here explicitly; that is exactly the surface this bug is about.
///
/// The bar is wrapped in the same `AdaptiveLiquidGlassLayer` +
/// `LiquidGlassWidgets.wrap` context it lives in inside the app, so it has the
/// glass scope it needs to paint.
Widget buildNavBarUnderTest({
  required int selectedIndex,
  required ValueChanged<int> onTap,
}) {
  return LiquidGlassWidgets.wrap(
    child: AdaptiveLiquidGlassLayer(
      settings: GlassNavTheme.webLightSettings(),
      quality: GlassQuality.standard,
      child: _OpaqueWebNavBar(
        selectedIndex: selectedIndex,
        onTap: onTap,
      ),
    ),
  );
}


/// The navbar exactly as RootScreen assembles it for the light web build: the
/// opaque `#FFFFFF` capsule pad behind the glass, the glow disabled, everything
/// else the shipping configuration. Kept in step with
/// `lib/screens/root/root_screen.dart`.
class _OpaqueWebNavBar extends StatelessWidget {
  const _OpaqueWebNavBar({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const Brightness brightness = Brightness.light;
    final GlassTabBar tabBar = GlassTabBar.bottom(
      selectedIndex: selectedIndex,
      onTabSelected: onTap,
      settings: GlassNavTheme.webLightSettings(),
      barHeight: GlassNavTheme.barHeight,
      barBorderRadius: GlassNavTheme.barRadius,
      horizontalPadding: GlassNavTheme.horizontalInset,
      verticalPadding: GlassNavTheme.verticalInset,
      iconSize: GlassNavTheme.iconSize,
      indicatorColor: GlassNavTheme.lightIndicatorFill,
      indicatorSettings: GlassNavTheme.travellingPill(brightness),
      enableBlend: false,
      indicatorPinchStrength: 0,
      magnification: 1.0,
      pressScale: 1.0,
      interactionBehavior: GlassInteractionBehavior.none,
      // Light web pins the pill to its resting chip; the travelling glass lens
      // has no shader to render with there and paints as an opaque slab.
      staticIndicator: true,
      // The web renderer has no Impeller shader, so `AdaptiveGlass` never takes
      // its premium path there (`canUsePremiumShader` is `!kIsWeb && …`). Pinning
      // the quality here puts the host on the same non-shader path the browser
      // gets, which is the whole point of this test — on the premium path the
      // capsule's rim refracts the backdrop from *outside* the bar, which is
      // correct glass behaviour on the app and simply does not happen on web.
      quality: GlassQuality.standard,
      selectedIconColor: GlassNavTheme.selectedIcon(brightness),
      selectedLabelColor: GlassNavTheme.selectedLabel(brightness),
      unselectedIconColor: GlassNavTheme.unselectedContent(brightness),
      unselectedLabelColor: GlassNavTheme.unselectedContent(brightness),
      labelFontSize: GlassNavTheme.labelSize,
      selectedLabelStyle: GlassNavTheme.labelStyle(selected: true),
      unselectedLabelStyle: GlassNavTheme.labelStyle(selected: false),
      tabs: const <GlassTab>[
        GlassTab(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard_rounded),
          label: 'DASHBOARD',
        ),
        GlassTab(
          icon: Icon(Icons.calendar_month_outlined),
          activeIcon: Icon(Icons.calendar_month_rounded),
          label: 'CALENDAR',
        ),
        GlassTab(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
          label: 'PROFILE',
        ),
      ],
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GlassNavTheme.horizontalInset,
              vertical: GlassNavTheme.verticalInset,
            ),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(GlassNavTheme.barRadius),
                  border: Border.all(color: const Color(0x14000000)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        tabBar,
      ],
    );
  }
}

// =======================================================================
// THRESHOLDS
// =======================================================================

/// Solid black is painted behind the bar. Any of it visible through the bar
/// surface means the surface is translucent.
const Color kSentinel = Color(0xFF000000);

/// Relative luminance floor for glyph-free probe regions. #DBEAFE sits at
/// about 0.83; the black indicator seen in the bug sat at 0.01 and the
/// mid-grey frame at 0.17.
const double kMinProbeLuminance = 0.55;

/// Mean luminance floor across the bar interior, with headroom for glyphs.
const double kMinMeanLuminance = 0.78;

/// Fraction of the selected tab slot that must still read as light.
const double kMinSelectedSlotLightRatio = 0.45;

const double kLightPixel = 0.60;
const double kDarkPixel = 0.35;

const Size kSurfaceSize = Size(1080, 1920);

// =======================================================================
// HARNESS
// =======================================================================

final GlobalKey _rootKey = GlobalKey();
final GlobalKey _navKey = GlobalKey();

class _Harness extends StatefulWidget {
  const _Harness({required this.initialIndex});

  final int initialIndex;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _rootKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightThemeUnderTest(),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: <Widget>[
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 260,
                child: ColoredBox(color: kSentinel),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: KeyedSubtree(
                  key: _navKey,
                  child: buildNavBarUnderTest(
                    selectedIndex: _index,
                    onTap: (int i) => setState(() => _index = i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================================
// RASTER HELPERS
// =======================================================================

double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

class _Shot {
  _Shot(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  bool contains(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height;

  int _offset(int x, int y) => (y * width + x) * 4;

  double luminanceAt(int x, int y) {
    final int i = _offset(x, y);
    return 0.2126 * _toLinear(rgba[i] / 255.0) +
        0.7152 * _toLinear(rgba[i + 1] / 255.0) +
        0.0722 * _toLinear(rgba[i + 2] / 255.0);
  }

  int channelDelta(_Shot other, int x, int y) {
    final int a = _offset(x, y);
    final int b = other._offset(x, y);
    int worst = 0;
    for (int c = 0; c < 3; c++) {
      final int d = (rgba[a + c] - other.rgba[b + c]).abs();
      if (d > worst) worst = d;
    }
    return worst;
  }
}

Future<_Shot> _capture(WidgetTester tester) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
  _Shot? shot;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    shot = _Shot(image.width, image.height, data!.buffer.asUint8List());
    image.dispose();
  });
  expect(shot, isNotNull, reason: 'RepaintBoundary.toImage() returned nothing');
  return shot!;
}

// =======================================================================
// GEOMETRY
// =======================================================================

/// The painted bar, found by looking for everything inside the navbar
/// widget's box that is not the black sentinel behind it. This is narrower
/// than the widget box whenever the bar has outer margin, which is exactly
/// what we want to probe.
Rect _visibleBarRect(_Shot shot, Rect navBox) {
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  for (int y = navBox.top.floor(); y < navBox.bottom.ceil(); y++) {
    for (int x = navBox.left.floor(); x < navBox.right.ceil(); x++) {
      if (!shot.contains(x, y)) continue;
      if (shot.luminanceAt(x, y) <= 0.15) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  expect(
    maxX >= 0 && maxY >= 0,
    isTrue,
    reason: 'The whole navbar rasterized dark. Nothing light was found inside '
        '$navBox, which means the bar is painting black over the sentinel.',
  );
  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX + 1.0,
    maxY + 1.0,
  );
}

/// Horizontal inset that clears the bar's rounded corners, so probes never
/// sample the transparent area outside the shape.
double _cornerInset(Rect bar) => math.max(12.0, bar.height * 0.6);

/// Region guaranteed to be inside the shape on every row.
Rect _interior(Rect bar) {
  final double ci = _cornerInset(bar);
  return Rect.fromLTRB(bar.left + ci, bar.top + 2, bar.right - ci, bar.bottom - 2);
}

/// Slot occupied by tab [i], inset away from the rounded ends.
Rect _slotRect(Rect bar, int i) {
  final double slot = bar.width / kTabCount;
  final double ci = _cornerInset(bar);
  double left = bar.left + slot * i + 4;
  double right = bar.left + slot * (i + 1) - 4;
  if (i == 0) left = math.max(left, bar.left + ci);
  if (i == kTabCount - 1) right = math.min(right, bar.right - ci);
  return Rect.fromLTRB(left, bar.top + 3, right, bar.bottom - 3);
}

/// Regions that cannot contain an icon or a label glyph, so any dark pixel
/// found in them is either a bad indicator fill or the sentinel bleeding
/// through a translucent surface.
List<MapEntry<String, Rect>> _probes(Rect bar) {
  final double ci = _cornerInset(bar);
  final double topBand = math.max(5.0, bar.height * 0.13);
  final double midHalf = math.max(4.0, bar.height * 0.14);
  final double cy = bar.center.dy;
  final List<MapEntry<String, Rect>> out = <MapEntry<String, Rect>>[
    MapEntry<String, Rect>(
      'strip above the icons',
      Rect.fromLTRB(bar.left + ci, bar.top + 2, bar.right - ci, bar.top + topBand),
    ),
    MapEntry<String, Rect>(
      'inner left edge',
      Rect.fromLTRB(bar.left + 3, cy - midHalf, bar.left + 11, cy + midHalf),
    ),
    MapEntry<String, Rect>(
      'inner right edge',
      Rect.fromLTRB(bar.right - 11, cy - midHalf, bar.right - 3, cy + midHalf),
    ),
  ];
  for (int i = 1; i < kTabCount; i++) {
    final double gx = bar.left + bar.width * i / kTabCount;
    out.add(MapEntry<String, Rect>(
      'gutter between tab ${i - 1} and tab $i',
      Rect.fromLTRB(gx - 4, bar.top + 4, gx + 4, bar.bottom - 4),
    ));
  }
  return out;
}

// =======================================================================
// ASSERTIONS
// =======================================================================

String _describePixel(_Shot s, int x, int y) {
  final int i = (y * s.width + x) * 4;
  return 'rgb(${s.rgba[i]},${s.rgba[i + 1]},${s.rgba[i + 2]}) '
      'luminance=${s.luminanceAt(x, y).toStringAsFixed(3)} at ($x,$y)';
}

void _assertBarIsLight(_Shot shot, Rect bar, String when) {
  for (final MapEntry<String, Rect> probe in _probes(bar)) {
    double worst = 1.0;
    int wx = -1, wy = -1;
    for (int y = probe.value.top.round(); y < probe.value.bottom.round(); y++) {
      for (int x = probe.value.left.round(); x < probe.value.right.round(); x++) {
        if (!shot.contains(x, y)) continue;
        final double l = shot.luminanceAt(x, y);
        if (l < worst) {
          worst = l;
          wx = x;
          wy = y;
        }
      }
    }
    if (wx < 0) continue;
    expect(
      worst,
      greaterThanOrEqualTo(kMinProbeLuminance),
      reason: 'Dark pixel inside the ${probe.key} ($when).\n'
          '  darkest: ${_describePixel(shot, wx, wy)}\n'
          '  This region holds no icon and no label, so a dark pixel here is '
          'either the selected-tab indicator resolving to a black-based '
          'colour, or the black sentinel behind the bar showing through a '
          'translucent surface. Bar rect: $bar',
    );
  }

  final Rect inner = _interior(bar);
  double sum = 0;
  int count = 0;
  for (int y = inner.top.round(); y < inner.bottom.round(); y++) {
    for (int x = inner.left.round(); x < inner.right.round(); x++) {
      if (!shot.contains(x, y)) continue;
      sum += shot.luminanceAt(x, y);
      count++;
    }
  }
  expect(count, greaterThan(0), reason: 'Empty bar interior ($when): $bar');
  expect(
    sum / count,
    greaterThanOrEqualTo(kMinMeanLuminance),
    reason: 'The light-theme bar interior averages '
        '${(sum / count).toStringAsFixed(3)} luminance ($when), below '
        '$kMinMeanLuminance. Something large and dark is being painted in '
        'the bar. Bar rect: $bar',
  );
}

/// The selected tab must still read as an icon and a label sitting on a light
/// fill. If the indicator paints over them, or paints opaque, the slot loses
/// its light pixels and this fails.
void _assertSelectedSlotShowsContent(_Shot shot, Rect bar, int index) {
  final Rect slot = _slotRect(bar, index);
  int light = 0, dark = 0, total = 0;
  for (int y = slot.top.round(); y < slot.bottom.round(); y++) {
    for (int x = slot.left.round(); x < slot.right.round(); x++) {
      if (!shot.contains(x, y)) continue;
      final double l = shot.luminanceAt(x, y);
      if (l >= kLightPixel) light++;
      if (l <= kDarkPixel) dark++;
      total++;
    }
  }
  expect(total, greaterThan(0), reason: 'Empty slot rect for tab $index: $slot');
  expect(
    light / total,
    greaterThanOrEqualTo(kMinSelectedSlotLightRatio),
    reason: 'Only ${(100 * light / total).toStringAsFixed(1)}% of the selected '
        'tab slot (tab $index) reads as light. The indicator fill is too dark, '
        'or it is painted on top of the icon and label instead of behind '
        'them. Slot: $slot',
  );
  expect(
    dark,
    greaterThan(0),
    reason: 'No dark pixels at all in the selected tab slot (tab $index). The '
        'icon and label are not visible above the indicator. Slot: $slot',
  );
}

void _assertShotsMatch(_Shot a, _Shot b, Rect region, String reason) {
  // Starts below zero so the first compared pixel always wins, even when the
  // two shots match exactly. With this seeded at 0 a *perfect* match left
  // `wx`/`wy` at -1, and `reason:` is built eagerly by `expect` whether or not
  // the matcher fails — so `_describePixel` indexed out of bounds and the
  // passing case threw a RangeError.
  int worst = -1, wx = -1, wy = -1;
  double sum = 0;
  int count = 0;
  for (int y = region.top.round(); y < region.bottom.round(); y++) {
    for (int x = region.left.round(); x < region.right.round(); x++) {
      if (!a.contains(x, y) || !b.contains(x, y)) continue;
      final int d = a.channelDelta(b, x, y);
      sum += d;
      count++;
      if (d > worst) {
        worst = d;
        wx = x;
        wy = y;
      }
    }
  }
  expect(count, greaterThan(0), reason: 'Empty comparison region: $region');
  expect(
    worst,
    lessThanOrEqualTo(24),
    reason: '$reason\n  worst pixel delta $worst at ($wx,$wy)\n'
        '  after tap: ${_describePixel(a, wx, wy)}\n'
        '  reference: ${_describePixel(b, wx, wy)}',
  );
  expect(sum / count, lessThanOrEqualTo(1.5), reason: reason);
}

// =======================================================================
// TESTS
// =======================================================================

Future<void> _pumpHarness(WidgetTester tester, int index) async {
  await tester.binding.setSurfaceSize(kSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_Harness(initialIndex: index));
  // If this times out, the bar has an animation that never ends (a looping
  // shimmer or pulse). Replace pumpAndSettle with a fixed pump in that case.
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (int index = 0; index < kTabCount; index++) {
    testWidgets('light theme: settled bar stays light with tab $index selected',
        (WidgetTester tester) async {
      await _pumpHarness(tester, index);

      final _Shot shot = await _capture(tester);
      final Rect navBox = tester.getRect(find.byKey(_navKey));
      final Rect bar = _visibleBarRect(shot, navBox);

      _assertBarIsLight(shot, bar, 'settled, tab $index selected');
      _assertSelectedSlotShowsContent(shot, bar, index);
    });
  }

  testWidgets('light theme: bar stays light through every animation frame',
      (WidgetTester tester) async {
    await _pumpHarness(tester, 0);

    _Shot shot = await _capture(tester);
    final Rect navBox = tester.getRect(find.byKey(_navKey));
    // Measured once, from the settled state, and then held fixed. If it were
    // re-measured every frame a dark indicator would shrink the detected bar
    // and the probes would move with it.
    final Rect bar = _visibleBarRect(shot, navBox);
    final double slotWidth = bar.width / kTabCount;

    for (final int target in <int>[1, 2 % kTabCount, 0]) {
      await tester.tapAt(
        Offset(bar.left + slotWidth * (target + 0.5), bar.center.dy),
      );
      await tester.pump();

      // Walk the transition one frame at a time. The reported bug only shows
      // its worst state mid-animation, so a settled-only check misses it.
      for (int frame = 0; frame < 45; frame++) {
        shot = await _capture(tester);
        _assertBarIsLight(
          shot,
          bar,
          'frame $frame of the transition to tab $target',
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pumpAndSettle();
    }
  });

  testWidgets('light theme: a tap leaves no lingering overlay behind',
      (WidgetTester tester) async {
    // Reach tab 1 by tapping, then let everything settle.
    await _pumpHarness(tester, 0);
    final Rect navBox = tester.getRect(find.byKey(_navKey));
    final _Shot probeShot = await _capture(tester);
    final Rect bar = _visibleBarRect(probeShot, navBox);
    final double slotWidth = bar.width / kTabCount;

    await tester.tapAt(Offset(bar.left + slotWidth * 1.5, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final _Shot afterTap = await _capture(tester);

    // Now render tab 1 from a cold start, with no pointer history at all.
    await _pumpHarness(tester, 1);
    final _Shot reference = await _capture(tester);

    _assertShotsMatch(
      afterTap,
      reference,
      navBox,
      'The bar does not look the same after tapping tab 1 as it does when tab 1 '
      'is selected from a cold start. Something from the gesture is still '
      'painted: a splash, a highlight, or a hover overlay that was never '
      'cleared. On web this is the grey disc that stays behind after a touch.',
    );
  });
}
