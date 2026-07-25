import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_theme.dart';

/// Glass material and content colours for the bottom navigation bar.
///
/// ## The idea: everything is glass, contrast comes from the ink
///
/// The bar and the selected tab's pill are both genuinely translucent — the
/// pill is a brighter lens sitting on the bar's glass, not a solid fill. That
/// keeps the material honest, but it means nothing guarantees the selected
/// icon a background, so the brand blue is tuned per theme instead: at full
/// strength it measures ~4.1:1 on dark glass, under the 4.5:1 minimum.
///
/// Kept out of the widget so those contrast relationships can be asserted in
/// tests — with a translucent surface, "pick a theme colour and hope" is how
/// you end up with an unreadable bar.
class GlassNavTheme {
  GlassNavTheme._();

  // ── Proportions ───────────────────────────────────────────
  /// Pill height. Shorter than the package's 64 default: three tabs do not
  /// need that much vertical room, and the extra height is what made the bar
  /// read as a slab.
  static const double barHeight = 58;
  static const double barRadius = barHeight / 2;

  /// Inset from the screen edges. Wider than the default 20 so the bar reads
  /// as a deliberate floating object rather than a full-width toolbar.
  static const double horizontalInset = 32;
  static const double verticalInset = 14;

  static const double iconSize = 22;
  static const double labelSize = 10;

  // ── Floating action pill ──────────────────────────────────
  /// Height of a floating action button that wants to read as part of the bar
  /// (the calendar's "Add record"). Deliberately shorter than [barHeight]: at
  /// equal height it stops looking like a companion to the bar and starts
  /// looking like a second, broken-off bar.
  static const double actionHeight = 46;
  static const double actionRadius = actionHeight / 2;

  /// Gap between the action pill's trailing edge and the screen, matched to
  /// [horizontalInset] so the pill and the bar share a right edge. Scaffold's
  /// own FAB margin is 16, so callers make up the difference.
  static const double actionInset = horizontalInset;

  /// Vertical gap between the pill and the bar's glass, deliberately the same
  /// [verticalInset] the bar itself floats off the screen edge by — the pill
  /// stands off the bar exactly as far as the bar stands off the screen.
  ///
  /// Left to itself, Scaffold clears its FAB by `max(16, viewPadding.bottom)`
  /// *on top of* the bar's own inset, which on a gesture-nav device stacked up
  /// to roughly 60px of dead air. Callers subtract that margin back out.
  static const double actionGap = verticalInset;

  /// The nav labels are 10px, which is legible as a caption under an icon but
  /// too quiet for a primary action. 12 keeps the same weight and tracking so
  /// the pill still reads as the same typographic family.
  static const double actionLabelSize = 12;

  /// The glass material — thin and genuinely translucent.
  ///
  /// High blur with *low* tint is what real frosted glass looks like. The
  /// earlier version had that backwards (heavy tint, low blur), which is why
  /// page content stayed legible through the bar while the bar itself went
  /// murky. Blur removes the interference; tint only needs to hint at a
  /// surface.
  ///
  /// `saturation` is held at exactly 1.0 because the package's 1.5 default
  /// over-saturates the refracted backdrop into a colour cast. It used to sit
  /// at 1.05, which is small but points the wrong way: whatever colour leaks
  /// through the veil gets amplified rather than damped.
  static LiquidGlassSettings settings(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    return LiquidGlassSettings(
      thickness: 20,
      blur: 20,
      refractiveIndex: 1.4,
      saturation: 1.0,
      lightIntensity: 0.5,
      glassColor: isDark
          ? const Color(0xFF11131A).withValues(alpha: 0.24)
          : Colors.white.withValues(alpha: 0.22),
      // iOS 26's "legibility veil", ungated in both themes.
      //
      // Light mode used to gate it, on the theory that lifting only bright
      // pixels keeps dark text crisp underneath. The flaw is what the gate
      // does to *mid-tone* colour: a saturated green card is not bright, so it
      // failed the gate, went unveiled, and printed straight through the bar
      // while the white areas beside it got the full 0.45 lift. That is the
      // uneven colour wash at the bar's ends — the veil was strongest exactly
      // where there was nothing to hide.
      //
      // Ungated frosts every pixel by the same amount, so a colour cast can no
      // longer survive in patches. Strength comes down to 0.28 to pay for it:
      // an even veil counts everywhere, where the gated one only ever landed
      // on part of the bar, so matching 0.45 would read as milk.
      whitenStrength: isDark ? 0.08 : 0.28,
      whitenGated: false,
    );
  }

  /// Tint of the selected tab's pill.
  ///
  /// Glass-on-glass needs a real step in brightness to be findable at all, but
  /// push the alpha much past this and the pill stops reading as a lens and
  /// starts reading as a solid chip.
  static Color selectionTint(Brightness brightness) {
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.16)
        : AppTheme.primaryBlue.withValues(alpha: 0.12);
  }

  /// The indicator pill: a flat tinted chip with a rim, not a lens.
  ///
  /// It used to refract — blur 6 over a 1.45 index, a second full blur pass
  /// compositing every frame the pill was in motion, on top of the bar's own.
  /// Refraction is also the part that has to resolve as the pill travels,
  /// which is what made a 350 ms move look like it took longer.
  ///
  /// [selectionTint] is doing the real work of marking the selection, so the
  /// pill stays just as findable without it — and the contrast relationships
  /// asserted in the tests are unchanged, since they read the tint, not this.
  /// `lightIntensity` is kept up so the rim highlight still separates the pill
  /// from the bar; a chip with no edge reads as a smudge.
  static LiquidGlassSettings selectionSettings(Brightness brightness) {
    return LiquidGlassSettings(
      thickness: 8,
      blur: 0,
      refractiveIndex: 1.0,
      saturation: 1.0,
      lightIntensity: 0.6,
      glassColor: selectionTint(brightness),
    );
  }

  /// Selected tab icon — the brightest, most saturated blue each theme can
  /// carry.
  ///
  /// Held to WCAG 1.4.11 (3:1, non-text contrast) rather than 1.4.3 (4.5:1),
  /// because an icon is a graphical object, not text. That is what buys the
  /// extra brightness: in light mode the pill has to *darken* to be visible on
  /// white glass, so a brighter icon and a findable pill pull against each
  /// other — under the text threshold the icon had to go deeper than the brand
  /// blue, under the icon threshold it can stay at full strength.
  ///
  /// Dark mode brightens in HSL rather than by lerping toward white. Lerping
  /// pulls chroma out along with the darkness, which lands on a pale
  /// periwinkle; raising lightness while holding saturation keeps it reading
  /// as a *blue* that happens to be bright.
  ///
  /// Lightness sits at 0.62, not the 0.72 it used to. Saturation was already
  /// pinned at 1.0, so lightness was the only chroma left to spend: in sRGB
  /// chroma peaks at L=0.5 and falls off toward white, and 0.72 was far enough
  /// up that slope to cost 36% of it. Coming down to 0.62 buys that back and
  /// still measures 3.6:1 on the pill, clear of the 3:1 icon floor.
  ///
  /// Going further is possible but tight — L=0.58 is 3.08:1, which passes on
  /// paper and leaves nothing for the pill tint to drift.
  static Color selectedIcon(Brightness brightness) {
    if (brightness == Brightness.light) return AppTheme.primaryBlue;
    final HSLColor brand = HSLColor.fromColor(AppTheme.primaryBlue);
    return brand.withLightness(0.62).withSaturation(1.0).toColor();
  }

  /// Selected tab label — the same blue held to the stricter 4.5:1 text
  /// threshold, so it runs a shade quieter than [selectedIcon] in light mode.
  ///
  /// Dark mode used to just alias [selectedIcon], which worked only while that
  /// colour was bright enough to clear the *text* floor too. Now that the icon
  /// has traded brightness for chroma it measures 3.6:1 — fine for a graphical
  /// object, well under the 4.5:1 a label needs — so the label keeps the old
  /// 0.72 and the two part ways. Same hue, so they still read as one accent.
  static Color selectedLabel(Brightness brightness) {
    if (brightness == Brightness.light) {
      return Color.lerp(AppTheme.primaryBlue, Colors.black, 0.16)!;
    }
    final HSLColor brand = HSLColor.fromColor(AppTheme.primaryBlue);
    return brand.withLightness(0.72).withSaturation(1.0).toColor();
  }

  /// Unselected tab icon + label. Deliberately not `onSurfaceVariant`: that is
  /// picked to sit on the opaque theme surface, not on glass.
  static Color unselectedContent(Brightness brightness) {
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF3C4043);
  }

  /// What the bar's glass composites to over the app's own background — the
  /// reference background for the *unselected* labels.
  static Color substrate(Brightness brightness) {
    final Color base =
        brightness == Brightness.dark ? Colors.black : Colors.white;
    return Color.alphaBlend(settings(brightness).glassColor, base);
  }

  /// [substrate] plus the pill's tint — the reference background for the
  /// *selected* icon and label.
  static Color selectionSubstrate(Brightness brightness) {
    return Color.alphaBlend(selectionTint(brightness), substrate(brightness));
  }

  /// Labels are small, so they lean on weight and tracking as much as colour.
  static TextStyle labelStyle({required bool selected}) {
    return TextStyle(
      fontSize: labelSize,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.1,
    );
  }
}
