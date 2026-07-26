import 'package:attend_ease/theme/app_page_transition.dart';
import 'package:attend_ease/theme/container_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The destination screen is rendered inside a Material laid out by
/// [ContainerTransformTransition]. Its rect tells us how far the morph has
/// progressed.
Rect _morphRect(WidgetTester tester) {
  final material = find.ancestor(
    of: find.byKey(const ValueKey('destination')),
    matching: find.byType(Material),
  );
  return tester.getRect(material.last);
}

GoRouter _buildRouter({Widget? destination}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ContainerTransformAnchor(
              borderRadius: 12,
              child: SizedBox(
                width: 200,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.push('/detail'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/detail',
        pageBuilder: (context, state) => AppPageTransition.containerPage(
          state,
          destination ??
              const Scaffold(
                key: ValueKey('destination'),
                body: Center(child: Text('detail')),
              ),
        ),
      ),
    ],
  );
}

/// Counts how many times the destination was built from scratch, so the tests
/// can prove the page isn't thrown away when the transition settles.
class _CountingDestination extends StatefulWidget {
  const _CountingDestination();

  static int mounts = 0;

  @override
  State<_CountingDestination> createState() => _CountingDestinationState();
}

class _CountingDestinationState extends State<_CountingDestination> {
  @override
  void initState() {
    super.initState();
    _CountingDestination.mounts++;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        key: ValueKey('destination'),
        body: Center(child: Text('detail')),
      );
}

void main() {
  setUp(ContainerTransformOrigin.resetForTesting);

  testWidgets('destination grows out of the tapped anchor and fills the screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));

    final Rect anchorRect = tester.getRect(find.byType(ElevatedButton));

    await tester.tap(find.text('open'));
    // Two frames: one for GoRouter's delegate notification, one to build the
    // pushed route. Neither advances the clock, so the transition is at t=0.
    await tester.pump();
    await tester.pump();

    // At the very start the incoming page occupies (roughly) the tapped rect,
    // not the whole screen.
    final Rect start = _morphRect(tester);
    expect(start.width, closeTo(anchorRect.width, 1));
    expect(start.height, closeTo(anchorRect.height, 1));
    expect(start.topLeft, offsetMoreOrLessEquals(anchorRect.topLeft, epsilon: 1));

    // Mid-flight it is bigger than the anchor but smaller than the screen.
    await tester.pump(const Duration(milliseconds: 150));
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Rect mid = _morphRect(tester);
    expect(mid.width, greaterThan(anchorRect.width));
    expect(mid.width, lessThan(screen.width));

    // Settled: the page fills the screen.
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('destination'))),
        Rect.fromLTWH(0, 0, screen.width, screen.height));
  });

  testWidgets('the destination scales into the box instead of being clipped',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // The reference lays the page out at its final size and scales it into the
    // box (FittedBox, fitWidth) so its content morphs along with the corners.
    // Revealing a full-size page through a growing clip reads as a wipe.
    final Rect box = _morphRect(tester);
    final Rect page =
        tester.getRect(find.byKey(const ValueKey('destination')));
    expect(page.width, closeTo(box.width, 1));
    expect(page.topLeft, offsetMoreOrLessEquals(box.topLeft, epsilon: 1));
  });

  testWidgets('the tapped card flies inside the box', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // `ContainerTransitionType.fade` keeps the closed builder fully opaque for
    // the whole flight, scaled to the box, with the page fading in over it —
    // that is what makes the card appear to *become* the page. Two copies: the
    // original in the route underneath (covered by the box) and the clone.
    expect(find.text('open'), findsNWidgets(2));
  });

  testWidgets('the scrim ramps across the whole flight, not in a hard step',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    double scrimAlpha() => tester
        .widget<ColoredBox>(find.byKey(ContainerTransformTransition.scrimKey))
        .color
        .a;

    final samples = <double>[];
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 70));
      samples.add(scrimAlpha());
    }

    // Strictly increasing and still short of full strength most of the way
    // through: the reference's ramp-over-the-first-fifth-then-hold is a visible
    // step near the start, which is what we're avoiding.
    expect(samples[0], lessThan(samples[1]));
    expect(samples[1], lessThan(samples[2]));
    expect(samples[1], lessThan(ContainerTransformTransition.scrimColor.a));
  });

  testWidgets('the box stays rounded until it is nearly the full page',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    const double anchorWidth = 200;
    const double anchorRadius = 12;

    // The property that matters, stated independently of the curve and duration:
    // at every point in the flight the corners are rounder than the box's own
    // progress. The reference collapses the radius linearly with the geometry,
    // so it is square through the whole visible part of the growth — the "boxy"
    // failure mode.
    var sampled = 0;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));

      final material = tester.widget<Material>(find.ancestor(
        of: find.byKey(const ValueKey('destination')),
        matching: find.byType(Material),
      ).last);
      final radius = (material.borderRadius! as BorderRadius).topLeft.x;

      // How far the box has grown, read back off the geometry itself.
      final double t = (_morphRect(tester).width - anchorWidth) /
          (screen.width - anchorWidth);
      if (t <= 0.05 || t >= 0.99) continue;

      expect(radius, greaterThan((1 - t) * anchorRadius),
          reason: 'at ${(t * 100).round()}% grown the corners should still be '
              'rounder than a linear collapse');
      sampled++;
    }
    expect(sampled, greaterThan(1), reason: 'need real mid-flight samples');
  });

  testWidgets('the destination is not rebuilt when the transition settles',
      (tester) async {
    _CountingDestination.mounts = 0;
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: _buildRouter(destination: const _CountingDestination())));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The tree shape changes when the transition hands the page through
    // untouched; without a stable key that discards the page's state and runs
    // initState a second time.
    expect(_CountingDestination.mounts, 1);
  });

  testWidgets('falls back to the shared fade + slide with no recorded anchor',
      (tester) async {
    final router = _buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Programmatic navigation — nothing was tapped, so no origin was recorded.
    router.push('/detail');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // The fade+slide fallback lays the page out full-bleed the whole way, so
    // it is already screen-width mid-transition (only opacity/offset differ).
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byKey(const ValueKey('destination'))).width,
        closeTo(screen.width, 0.01));

    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  test('a stale origin is not reused by a later route', () async {
    ContainerTransformOrigin.record(const Rect.fromLTWH(0, 0, 10, 10), 4);
    // Origins older than the freshness window belong to some earlier
    // interaction — a deep link must not inherit them.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(ContainerTransformOrigin.claim('page-key'), isNull);
  });

  test('an origin claimed by a page key is returned again on rebuild', () {
    const rect = Rect.fromLTWH(5, 5, 100, 40);
    ContainerTransformOrigin.record(rect, 12);

    final first = ContainerTransformOrigin.claim('page-key');
    expect(first, isNotNull);
    expect(first!.rect, rect);

    // Same key again (the transitions builder runs every frame) — same origin,
    // and it is not handed to an unrelated page.
    expect(ContainerTransformOrigin.claim('page-key')!.rect, rect);
    expect(ContainerTransformOrigin.claim('other-key'), isNull);
  });

  test('reopening the same page after scrolling uses the new tile position',
      () {
    const first = Rect.fromLTWH(0, 400, 300, 60);
    ContainerTransformOrigin.record(first, 12);
    expect(ContainerTransformOrigin.claim('page-key')!.rect, first);

    // User popped back, scrolled, and tapped the same row again.
    const second = Rect.fromLTWH(0, 120, 300, 60);
    ContainerTransformOrigin.record(second, 12);
    expect(ContainerTransformOrigin.claim('page-key')!.rect, second);
  });
}
