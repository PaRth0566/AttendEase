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

GoRouter _buildRouter() {
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
          const Scaffold(
            key: ValueKey('destination'),
            body: Center(child: Text('detail')),
          ),
        ),
      ),
    ],
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
