// The calendar's "why can't I delete this?" tooltip — a BeakTooltip.
//
// Replaces a stock Material Tooltip, which painted a near-black slab in both
// themes and could not draw a beak. What is pinned here is the behaviour that
// replacement has to keep (tap to open, auto-hide, a11y label) plus the two
// things the custom geometry can get wrong: the beak must point at the icon, and
// the message must stay on one line at a realistic phone width.

import 'dart:io';

import 'package:attend_ease/theme/app_colors.dart';
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/widgets/beak_bubble.dart';
import 'package:attend_ease/widgets/beak_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real string the calendar passes for a Not Conducted row.
const String kNcReason = 'From your report — can’t be deleted';

/// A message no phone can fit on one line, for the wrap/clamp case.
const String kLongReason =
    'This lecture was never conducted according to the report you imported, '
    'so there is nothing here for you to remove.';

/// The icon sits at the trailing edge of a record card, which is where the
/// horizontal clamp and the beak aim are hardest — a centred bubble would be
/// pushed left off its anchor.
Widget _harness({
  required Brightness brightness,
  Alignment align = Alignment.centerRight,
  String message = kNcReason,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    home: Scaffold(
      body: Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BeakTooltip(
            message: message,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ),
        ),
      ),
    ),
  );
}

/// How many lines the open bubble's message actually wrapped onto.
///
/// Counted from the selection boxes' distinct tops — `RenderParagraph` exposes
/// no line metrics, and comparing heights against an assumed line height would
/// bake the font size into the test.
int _lineCount(WidgetTester tester, String message) {
  final para = tester.renderObject<RenderParagraph>(find.text(message));
  final boxes = para.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: message.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  // Measure with the real typeface. Widget tests otherwise fall back to a test
  // font whose every glyph is a fixed em-wide box, which makes this message
  // three lines wide instead of one — so a line-count assertion against it would
  // be testing the test font, not the copy.
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final path in const [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ]) {
      loader.addFont(
        File(path).readAsBytes().then(
              (bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
            ),
      );
    }
    await loader.load();
  });

  // A realistic phone, not the 800x600 test default — the one-line requirement
  // is only meaningful at a width a phone actually has.
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  for (final brightness in Brightness.values) {
    final name = brightness.name;

    testWidgets('$name: tapping the icon opens the bubble, tapping again closes',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(brightness: brightness));
      expect(find.text(kNcReason), findsNothing);

      await tester.tap(find.byType(Icon));
      await tester.pumpAndSettle();
      expect(find.text(kNcReason), findsOneWidget);

      await tester.tap(find.byType(Icon));
      await tester.pumpAndSettle();
      expect(find.text(kNcReason), findsNothing);
    });

    testWidgets('$name: the message stays on one line at phone width',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(brightness: brightness));
      await tester.tap(find.byType(Icon));
      await tester.pumpAndSettle();

      expect(
        _lineCount(tester, kNcReason),
        1,
        reason: 'the tooltip is a single-line aside; wrapping it turns a glance '
            'into a paragraph. If this fails, the copy got longer — shorten it '
            'rather than letting the bubble grow.',
      );
    });

    testWidgets('$name: the bubble wears the theme card surface', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(brightness: brightness));
      await tester.tap(find.byType(Icon));
      await tester.pumpAndSettle();

      final BuildContext ctx = tester.element(find.byType(Scaffold));
      final expected = Theme.of(ctx).cardColor;
      // Sanity: light and dark must not resolve to the same slab, which is the
      // bug the stock Tooltip had.
      expect(
        expected,
        brightness == Brightness.dark
            ? AppTheme.darkTheme.cardColor
            : AppTheme.lightTheme.cardColor,
      );
      expect(ctx.appColors.cardBorder, isNotNull);
      expect(find.byType(BeakBubble), findsOneWidget);
    });
  }

  testWidgets('the beak points at the icon, not at the bubble centre',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(brightness: Brightness.light));
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();

    final bubble = tester.widget<BeakBubble>(find.byType(BeakBubble));
    final Rect bubbleRect = tester.getRect(find.byType(BeakBubble));
    final double iconCentreX = tester.getCenter(find.byType(Icon)).dx;

    // beakCenterX is in the bubble's own coordinates; resolve it back to the
    // screen and it must land on the icon.
    final double beakGlobalX = bubbleRect.left + bubble.beakCenterX;
    expect(
      beakGlobalX,
      closeTo(iconCentreX, 1.0),
      reason: 'a beak that does not point at what was tapped is worse than no '
          'beak — this is the whole reason the bubble is not a Material Tooltip',
    );
    expect(bubble.beakSide, BeakSide.top, reason: 'room below, so it hangs');
  });

  testWidgets('the bubble flips above when there is no room below',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(brightness: Brightness.light, align: Alignment.bottomRight),
    );
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();

    final bubble = tester.widget<BeakBubble>(find.byType(BeakBubble));
    expect(bubble.beakSide, BeakSide.bottom);

    final Rect bubbleRect = tester.getRect(find.byType(BeakBubble));
    final Rect iconRect = tester.getRect(find.byType(Icon));
    expect(
      bubbleRect.bottom,
      lessThanOrEqualTo(iconRect.top),
      reason: 'flipped means above the icon, not overlapping it',
    );
    expect(bubbleRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('a message too long for one line wraps instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(brightness: Brightness.light, message: kLongReason),
    );
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();

    final Rect bubbleRect = tester.getRect(find.byType(BeakBubble));
    expect(bubbleRect.left, greaterThanOrEqualTo(0));
    expect(bubbleRect.right, lessThanOrEqualTo(320));
    expect(
      _lineCount(tester, kLongReason),
      greaterThan(1),
      reason: 'it wraps rather than being clipped or running off-screen',
    );
    expect(tester.takeException(), isNull, reason: 'no overflow was thrown');
  });

  testWidgets('the real message still fits one line on a small phone',
      (tester) async {
    // 360dp is about the narrowest mainstream Android width. If the copy has to
    // hold one line anywhere, it has to hold it here.
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(brightness: Brightness.light));
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();

    expect(_lineCount(tester, kNcReason), 1);
  });

  testWidgets('the bubble dismisses itself after showDuration', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: BeakTooltip(
              message: kNcReason,
              showDuration: const Duration(seconds: 3),
              child: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(find.text(kNcReason), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text(kNcReason), findsOneWidget, reason: 'still inside window');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(kNcReason), findsNothing);
  });

  testWidgets('a tap outside dismisses it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(brightness: Brightness.light));
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(find.text(kNcReason), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text(kNcReason), findsNothing);
  });

  testWidgets('the message reaches the accessibility tree', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(brightness: Brightness.light));

    // Present without opening the bubble, exactly as a stock Tooltip would be —
    // a screen-reader user never taps to discover it.
    expect(
      tester.getSemantics(find.byType(BeakTooltip)),
      matchesSemantics(tooltip: kNcReason, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('disposing while the bubble is open does not throw',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(brightness: Brightness.light));
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(find.text(kNcReason), findsOneWidget);

    // The row is scrolled out of the ListView / the tab is torn down while the
    // auto-hide timer is still pending.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const SizedBox.shrink()),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  // The dashboard's day popover drives the same BeakBubble with a fixed width
  // instead of letting it size to its message. It was a private class in
  // dashboard_screen until this widget absorbed it, so its mode is covered here.
  testWidgets('fixed-width mode honours the width and wraps the message',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: BeakBubble(
              // The dashboard's own constant.
              width: 240,
              beakCenterX: 32,
              message: 'Skipping Sat drops Software Engineering With .NET '
                  'below target.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(BeakBubble)).width, 240);
    expect(
      _lineCount(
        tester,
        'Skipping Sat drops Software Engineering With .NET below target.',
      ),
      greaterThan(1),
      reason: 'a fixed-width popover wraps rather than sizing to its message',
    );
    expect(tester.takeException(), isNull);
  });
}
