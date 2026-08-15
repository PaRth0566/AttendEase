// Regression: the desktop web build painted no text in buttons, dialogs,
// snackbars, chips or the app bar, and stretched its overlays across the whole
// viewport.
//
// Both failure modes are invisible to a phone-sized test, which is why they
// shipped: cause A only bites where Roboto is not a system font (CanvasKit),
// and cause B only bites above ~700 px of width.
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/widgets/app_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The font family actually handed to the rasteriser for [text].
///
/// Asserting on the *painted* style rather than on the theme is deliberate: the
/// bug was entirely about styles that look correct in `ThemeData` and then lose
/// `fontFamily` on the way down through a component theme.
String? paintedFamily(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text))
    .text
    .style
    ?.fontFamily;

void useDesktopViewport(WidgetTester tester, {Size size = const Size(1568, 900)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // ── §4.1  Cause A: every component slot must resolve to the bundled font ──
  for (final entry in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('${entry.key}: component text styles all carry the bundled font',
        (tester) async {
      useDesktopViewport(tester);
      final theme = entry.value;

      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('AppBarTitle')),
          body: Builder(
            builder: (context) => Column(children: [
              const Text('PlainBody'),
              ElevatedButton(
                onPressed: () {},
                // A call site with its own raw TextStyle, as refresh_pdf_screen
                // and the logout dialog both have — this must still inherit.
                child: const Text('ElevatedLabel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              OutlinedButton(
                  onPressed: () {}, child: const Text('OutlinedLabel')),
              TextButton(onPressed: () {}, child: const Text('TextLabel')),
              const Chip(label: Text('ChipLabel')),
              const TextField(
                  decoration: InputDecoration(hintText: 'HintText')),
              ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SnackText'))),
                child: const Text('snack'),
              ),
              ElevatedButton(
                onPressed: () => showAppDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('DialogTitle'),
                    content: const Text('DialogBody'),
                    actions: [
                      TextButton(
                        onPressed: () {},
                        // Mirrors profile_screen.dart's 'Log Out' button.
                        child: const Text('DialogAction',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                child: const Text('dialog'),
              ),
            ]),
          ),
        ),
      ));

      for (final slot in [
        'PlainBody',
        'AppBarTitle',
        'ElevatedLabel',
        'OutlinedLabel',
        'TextLabel',
        'ChipLabel',
        'HintText',
      ]) {
        expect(paintedFamily(tester, slot), AppTheme.fontFamily,
            reason: '$slot resolved to a font the web build does not bundle, '
                'so CanvasKit would fetch Roboto and paint nothing');
      }

      await tester.tap(find.text('snack'));
      await tester.pumpAndSettle();
      expect(paintedFamily(tester, 'SnackText'), AppTheme.fontFamily);

      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
      expect(paintedFamily(tester, 'DialogTitle'), AppTheme.fontFamily);
      expect(paintedFamily(tester, 'DialogBody'), AppTheme.fontFamily);
      expect(paintedFamily(tester, 'DialogAction'), AppTheme.fontFamily);
    });
  }

  // ── §4.2  Cause B: overlays stay chip-sized on a desktop viewport ─────────
  testWidgets('snackbar does not span the desktop viewport', (tester) async {
    useDesktopViewport(tester);

    // The cap is a responsive overlay, not a property of the static theme, so
    // the theme has to arrive the way `main.dart` builds it. Handing the raw
    // `darkTheme` to `MaterialApp` here tests a configuration the app never
    // runs and can never pass.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.withResponsiveOverlays(AppTheme.darkTheme, 1568),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('SnackText'))),
            child: const Text('snack'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('snack'));
    await tester.pumpAndSettle();

    final surface = find
        .descendant(
            of: find.byType(SnackBar), matching: find.byType(Material))
        .first;
    // Measured 1538.0 before the fix, on a 1568 px viewport.
    expect(tester.getSize(surface).width, lessThanOrEqualTo(560));
  });

  testWidgets('snackbar is unchanged at phone width', (tester) async {
    // The width cap is global, so this proves it is a no-op on mobile rather
    // than a mobile regression traded for a desktop fix.
    useDesktopViewport(tester, size: const Size(411, 866));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.withResponsiveOverlays(AppTheme.darkTheme, 411),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('SnackText'))),
            child: const Text('snack'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('snack'));
    await tester.pumpAndSettle();

    final surface = find
        .descendant(
            of: find.byType(SnackBar), matching: find.byType(Material))
        .first;
    expect(tester.getSize(surface).width, lessThanOrEqualTo(411));
  });

  testWidgets('a dialog with unbounded content is capped on desktop',
      (tester) async {
    useDesktopViewport(tester, size: const Size(1080, 900));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppDialog(
              context: context,
              // The delete-account dialog's shape: a bare TextField, which has
              // unbounded intrinsic width and dragged the dialog to 1000 px.
              builder: (_) => AlertDialog(
                title: const Text('Delete Account?'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('This action is irreversible.'),
                      TextField(controller: TextEditingController()),
                    ],
                  ),
                ),
              ),
            ),
            child: const Text('dialog'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();

    final surface = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(Material))
        .first;
    expect(tester.getSize(surface).width, lessThanOrEqualTo(560),
        reason: 'measured 1000 px at a 1080 px viewport before the fix');
  });

  // ── §4.3  The dropdown case the theme fix cannot reach ───────────────────
  testWidgets('dropdown items inherit the bundled font', (tester) async {
    final theme = AppTheme.darkTheme;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: DropdownButtonFormField<int>(
          initialValue: 1,
          // Must derive from the theme, not construct a bare TextStyle.
          style: theme.textTheme.bodyLarge,
          items: const [
            DropdownMenuItem(value: 1, child: Text('Semester 1')),
          ],
          onChanged: (_) {},
        ),
      ),
    ));

    expect(paintedFamily(tester, 'Semester 1'), AppTheme.fontFamily);
  });
}
