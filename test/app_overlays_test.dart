import 'package:attend_ease/widgets/app_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(void Function(BuildContext) onPressed) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('showAppDialog opens, scales in, and closes', (tester) async {
    await tester.pumpWidget(_host((context) => showAppDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('body')),
        )));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-transition the dialog is present but still scaled down. getRect (not
    // getSize) is what reflects the ScaleTransition — layout size is constant.
    expect(find.text('body'), findsOneWidget);
    final double midWidth = tester.getRect(find.byType(AlertDialog)).width;

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AlertDialog)).width,
        greaterThan(midWidth));

    // Dismiss via the barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });

  testWidgets('showAppDialog can be non-dismissible', (tester) async {
    await tester.pumpWidget(_host((context) => showAppDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(content: Text('body')),
        )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('showAppModalSheet opens and closes without disposing its '
      'controller mid-animation', (tester) async {
    await tester.pumpWidget(_host((context) => showAppModalSheet<void>(
          context: context,
          builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
        )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    // Closing runs the reverse animation; the controller must outlive it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showAppModalSheet survives being opened and closed repeatedly',
      (tester) async {
    await tester.pumpWidget(_host((context) => showAppModalSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
        )));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
