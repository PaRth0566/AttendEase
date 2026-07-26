import 'package:flutter_test/flutter_test.dart';
// Not exported from the package barrel, but it is under `lib/utils/`, not
// `lib/src/`, so importing the file directly is fair game.
import 'package:liquid_glass_widgets/utils/draggable_indicator_physics.dart';

/// Guards the one behavioural change in the vendored copy of
/// `liquid_glass_widgets` — see `third_party/liquid_glass_widgets/README.attendease.md`.
///
/// The patch is five edits inside a 2 MB third-party tree, and the obvious way
/// to lose it is to drop a new upstream release over the top. Nothing else in
/// the app would fail if that happened: the bar would still build, still
/// animate, and still look correct in a screenshot. It would just go back to
/// pinching the selection pill thin as it crosses the bar, which is the bug
/// this was all for. So it gets a test that fails loudly instead.
void main() {
  // Enough velocity to saturate the distortion clamp, which is what the
  // full-width Dashboard→Profile trip does.
  const Offset fast = Offset(40, 0);

  ({double x, double y}) scaleOf(Offset velocity, {required bool along}) {
    final m = DraggableIndicatorPhysics.buildJellyTransform(
      velocity: velocity,
      // The values the bottom bar passes.
      maxDistortion: 0.8,
      velocityScale: 10,
      stretchAlongMotion: along,
    );
    return (x: m.entry(0, 0), y: m.entry(1, 1));
  }

  group('the selection pill deforms along its direction of travel', () {
    test('moving sideways, it gets wider and shorter — never narrower', () {
      final s = scaleOf(fast, along: true);

      // The whole point. A pill that narrows as it crosses the bar reads as
      // receding rather than accelerating, and at this velocity the unpatched
      // package takes it to 0.6x width.
      expect(s.x, greaterThan(1.0),
          reason: 'pill must elongate along its path, not squash');
      expect(s.y, lessThan(1.0),
          reason: 'the squash belongs on the perpendicular axis');
    });

    test('the coefficients are the ones the patch specifies', () {
      final s = scaleOf(fast, along: true);
      // distortion = clamp(40/10, 0, 1) * 0.8 = 0.8
      // along = 1 + 0.3 * 0.8 = 1.24, across = 1 / 1.24
      expect(s.x, closeTo(1.24, 0.001));
      expect(s.y, closeTo(1 / 1.24, 0.001));
    });

    test('it holds its area, so it reads as one object deforming', () {
      // Not decoration. The first attempt just swapped upstream's two
      // coefficients, which put -0.5 on the height and flattened a ~50 px pill
      // to 30 px — short enough that the icon inside it stuck out top and
      // bottom. Conserving area is what keeps a stretch from becoming a band.
      for (final v in [
        const Offset(40, 0),
        const Offset(12, 0),
        const Offset(3, 0),
      ]) {
        final s = scaleOf(v, along: true);
        expect(s.x * s.y, closeTo(1.0, 0.001),
            reason: 'area must be preserved at velocity $v');
      }
    });

    test('the pill never gets short enough to spill its icon', () {
      // The icon is 24 px inside a pill of about 50 px. Anything below ~0.75x
      // height starts to crowd it.
      final s = scaleOf(fast, along: true);
      expect(s.y, greaterThan(0.75));
    });

    test('a slower, shorter hop deforms less', () {
      // Half the speed is half the distortion — the clamp is not saturated, so
      // a neighbouring-tab hop stays visibly calmer than the full-width one.
      final full = scaleOf(fast, along: true);
      final half = scaleOf(const Offset(5, 0), along: true);
      expect(half.x, lessThan(full.x));
      expect(half.x, greaterThan(1.0));
    });

    test('standing still is a no-op', () {
      final s = scaleOf(Offset.zero, along: true);
      expect(s.x, closeTo(1.0, 0.001));
      expect(s.y, closeTo(1.0, 0.001));
    });
  });

  test('the flag defaults off, so upstream callers are untouched', () {
    // GlassSlider and GlassSegmentedControl share this helper and were left
    // alone deliberately. If the default ever flips, they change too.
    final s = scaleOf(fast, along: false);
    expect(s.x, closeTo(0.60, 0.001));
    expect(s.y, closeTo(1.24, 0.001));
  });
}
