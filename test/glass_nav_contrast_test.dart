import 'dart:math' as math;

import 'package:attend_ease/theme/glass_nav_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color fg, Color bg) {
  final double a = _luminance(fg);
  final double b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  // Nav labels render at 10px, so they are "normal text" under WCAG 1.4.3 and
  // need 4.5:1. Icons are graphical objects under 1.4.11 and need 3:1 — the
  // looser bound is what lets the active icon run brighter than its label.
  const double minText = 4.5;
  const double minIcon = 3.0;

  for (final brightness in Brightness.values) {
    final name = brightness.name;

    // The pill is glass, so the selected content has no guaranteed background
    // — it is read against the bar's glass plus the pill's tint.
    test('$name: selected icon clears the 3:1 non-text threshold', () {
      final Color bg = GlassNavTheme.selectionSubstrate(brightness);
      final Color fg =
          Color.alphaBlend(GlassNavTheme.selectedIcon(brightness), bg);
      expect(_contrast(fg, bg), greaterThanOrEqualTo(minIcon));
    });

    test('$name: selected label clears AA on the selection pill', () {
      final Color bg = GlassNavTheme.selectionSubstrate(brightness);
      final Color fg =
          Color.alphaBlend(GlassNavTheme.selectedLabel(brightness), bg);
      expect(_contrast(fg, bg), greaterThanOrEqualTo(minText));
    });

    test('$name: the selected icon stays a saturated blue', () {
      // Guards against brightening by lerping toward white, which lifts
      // luminance but bleeds the colour out into a pale periwinkle. The blue
      // has to still read as blue.
      final hsl = HSLColor.fromColor(GlassNavTheme.selectedIcon(brightness));
      expect(hsl.saturation, greaterThanOrEqualTo(0.8));
      expect(hsl.hue, closeTo(221, 8));
    });

    test('$name: the icon is at least as chromatic as its label', () {
      // The point of splitting the two is that the icon, judged as a graphical
      // object at 3:1, can spend on colour what the label has to spend on
      // contrast to clear 4.5:1.
      //
      // This used to assert brightness instead, which held only while "more
      // vivid" and "brighter" pointed the same way. They stop agreeing once
      // saturation is maxed: past that, sRGB chroma is bought by moving
      // lightness back toward 0.5, so the vivid icon is now the *darker* of
      // the pair in dark mode. Chroma is what the rule was always about.
      double chroma(Color c) {
        final HSLColor h = HSLColor.fromColor(c);
        return (1 - (2 * h.lightness - 1).abs()) * h.saturation;
      }

      expect(
        chroma(GlassNavTheme.selectedIcon(brightness)),
        greaterThanOrEqualTo(chroma(GlassNavTheme.selectedLabel(brightness))),
      );
    });

    // Unselected labels do sit on glass, so they are checked against what the
    // glass composites to over the app background.
    test('$name: unselected content clears AA on the glass', () {
      final Color bg = GlassNavTheme.substrate(brightness);
      final Color fg =
          Color.alphaBlend(GlassNavTheme.unselectedContent(brightness), bg);
      expect(_contrast(fg, bg), greaterThanOrEqualTo(minText));
    });

    test('$name: the selection pill stays a lens, not a chip', () {
      // Enough tint to find, little enough to still read as glass.
      final double alpha = GlassNavTheme.selectionTint(brightness).a;
      expect(alpha, greaterThanOrEqualTo(0.08));
      expect(alpha, lessThanOrEqualTo(0.3));
    });

    test('$name: the pill is findable against the surrounding glass', () {
      // Glass-on-glass: the pill has to be a visible step in brightness, or
      // there is nothing marking which tab is active.
      expect(
        _contrast(GlassNavTheme.selectionSubstrate(brightness),
            GlassNavTheme.substrate(brightness)),
        greaterThan(1.15),
      );
    });

    test('$name: selected and unselected content are distinguishable', () {
      expect(GlassNavTheme.selectedIcon(brightness),
          isNot(GlassNavTheme.unselectedContent(brightness)));
    });

    test('$name: glass stays glass — thin tint, heavy blur', () {
      final s = GlassNavTheme.settings(brightness);
      // Heavy tint is what turned the bar into a slab last time.
      expect(s.glassColor.a, lessThanOrEqualTo(0.3));
      // Blur, not tint, is what stops page text reading through the bar.
      expect(s.blur, greaterThanOrEqualTo(16));
      // The package default of 1.5 casts a colour over the refracted backdrop.
      expect(s.saturation, lessThanOrEqualTo(1.1));
    });
  }

  test('why the selected label is not just AppTheme.primaryBlue', () {
    // Regression anchor. Brand blue at full strength fails the 4.5:1 text
    // threshold on *both* pills — it is too dark on the dark one and, because
    // the light pill has to darken to be visible on white glass, not quite
    // dark enough on that one either. Hence the per-theme adjustment. It does
    // clear the 3:1 icon threshold, which is why the icon can keep it.
    const Color rawBrandBlue = Color(0xFF2563EB);
    for (final brightness in Brightness.values) {
      final Color pill = GlassNavTheme.selectionSubstrate(brightness);
      expect(_contrast(rawBrandBlue, pill), lessThan(4.5),
          reason: '$brightness label would fail AA at full brand strength');
    }
    expect(
      _contrast(rawBrandBlue,
          GlassNavTheme.selectionSubstrate(Brightness.light)),
      greaterThanOrEqualTo(3.0),
    );
    expect(GlassNavTheme.selectedIcon(Brightness.light), rawBrandBlue);
  });
}
