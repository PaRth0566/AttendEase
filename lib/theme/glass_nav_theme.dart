import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_dimens.dart';
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

  /// Roomier than the 22 the Material icons sat at. The nav icons are now
  /// hand-drawn (see `widgets/animated_nav_icons.dart`) and the calendar's is a
  /// twelve-dot grid on a 2.25-unit pitch in a 24-unit box; at 22px those dots
  /// land 2.06px apart with a 1.75px diameter and read as a smudge rather than
  /// as days.
  static const double iconSize = 26;
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

  /// Bottom margin a floating `SnackBar` needs on a screen that also floats an
  /// action pill (the calendar's "Add record").
  ///
  /// Measured from Scaffold's *own* bottom clearance, not from the screen edge —
  /// which is the whole subtlety. `ScaffoldMessenger` presents a SnackBar in the
  /// **root** Scaffold of a nested set, and that Scaffold already subtracts its
  /// `bottomNavigationBar`'s full height (`2 * verticalInset + barHeight`) plus
  /// the system inset before positioning a floating bar. So the nav bar is
  /// covered for free, and a margin that added it back would push the bar a bar
  /// height and a half up the screen.
  ///
  /// What is *not* covered is the action pill: it is the inner Scaffold's
  /// floating action button, invisible to the root Scaffold's layout. The pill's
  /// bottom edge lands exactly on the nav bar's reserved region — it stands
  /// [actionGap] off the bar's glass, and the region extends [verticalInset]
  /// above that glass, and the two are equal by construction — so clearing the
  /// pill costs exactly its own height, plus a gap to sit in.
  static const double snackBarPillClearance =
      actionHeight + AppDimens.space12;

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
          // Light mode carries more tint than dark. Dark glass gets its edge for
          // free — anything lighter than the page reads as a surface — but on a
          // white page a 0.22 white veil is indistinguishable from the
          // background, so the bar had no visible body and the tab content
          // floated loose on the page. 0.36 is enough to seat it without
          // turning the glass opaque — and 0.30 is the ceiling the "glass stays
          // glass" test holds both themes to, so this sits right on it.
          : Colors.white.withValues(alpha: 0.30),
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

  /// The bar's material for the **light theme on web**, over the opaque white
  /// capsule the web build seats it on.
  ///
  /// Identical to [settings] except that the rim is a hairline and the blur is
  /// off — the two things a wide, blurring glass does wrong once it is sitting
  /// on an opaque backer instead of on live page content.
  ///
  /// `thickness` is the width of the shader's inner bevel band, and 20 is tuned
  /// for a dark, translucent bar where a wide bevel reads as depth. 2 keeps the
  /// same specular rim and iridescent fringe drawn as a hairline, which is what
  /// bug item 5 asks the light bar's edge to be.
  ///
  /// `blur` goes to 0 because on web there is no glass shader — `AdaptiveGlass`
  /// falls back to a `BackdropFilter` clipped to the bar's shape, and a blur
  /// reads its source from the layer *underneath*, which near the capsule's edge
  /// is whatever is beside the bar rather than the capsule. At sigma 20 that
  /// smeared the page inward as a grey ramp about 24px wide just inside the
  /// edge, measured falling to `rgb(184,184,184)` (luminance 0.53) against a
  /// black backdrop — the "bar has a dirty inner outline" half of the light-web
  /// bar looking wrong. Over an opaque capsule the blur has nothing legitimate
  /// left to do: everything it is meant to obscure is already hidden by the
  /// backer, so all it can contribute is the bleed.
  ///
  /// Light-web-only by construction. It is a separate value rather than an edit
  /// to [settings] because [settings] is shared with the app build and with the
  /// dark theme, where the wide bevel and the blur are correct and are what the
  /// app ships.
  static LiquidGlassSettings webLightSettings() {
    return settings(Brightness.light).copyWith(thickness: 2, blur: 0);
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
  /// `lightIntensity` is kept up so the rim highlight still separates the pill
  /// from the bar; a chip with no edge reads as a smudge.
  ///
  /// ## Why the tint goes in at full alpha here and 0.16 next door
  ///
  /// These settings only ever describe the pill **in motion**. The bar paints
  /// the pill twice: at rest it is `indicatorColor` — [selectionTint], alpha
  /// and all — as a plain rectangle, and the moment it starts travelling that
  /// rectangle is cross-faded out and the glass pass takes over for the trip.
  /// The two have to look the same or the handover reads as the pill blinking
  /// out and back, which is indistinguishable from it teleporting.
  ///
  /// The catch is that alpha means something different on each. On
  /// `indicatorColor` it is opacity. Here it is the mix factor on the shader's
  /// tint lift, and the moving body's opacity is pinned at 0.70 by the package
  /// regardless — so passing [selectionTint]'s own 0.16 reads as "barely tint
  /// this at all" and the pill crosses the bar as an empty outline. At full
  /// alpha the lift lands within a couple of points of the resting chip's 16%,
  /// and the two ends of the cross-fade match.
  ///
  /// Dark mode is the case that matches cleanly, because the lift is additive
  /// and the chip is white. Light mode's chip *darkens* — a shader that can
  /// only add cannot reproduce that — so there the travelling pill reads as a
  /// faint blue brightening rather than a blue chip.
  static LiquidGlassSettings selectionSettings(Brightness brightness) {
    return LiquidGlassSettings(
      thickness: 8,
      blur: 0,
      refractiveIndex: 1.0,
      saturation: 1.0,
      lightIntensity: 0.6,
      glassColor: selectionTint(brightness).withValues(alpha: 1.0),
    );
  }

  /// The opaque, blue-tinted fill the resting selection pill wears in the
  /// **light theme**.
  ///
  /// `#DBEAFE` is Tailwind's `blue-100` — the brand's own hue at a very light
  /// tint. It is deliberately opaque and constant: the earlier light-mode pill
  /// was `Color(0xFF1F2126)` at a low alpha, which composited through the glass
  /// shader to a faint grey on Impeller but, on web where that shader is
  /// dropped, painted straight through as a near-black slab whose alpha
  /// animated black→grey→light across a tab change. Nothing here resolves from
  /// the `on*` family and nothing animates its alpha, so it can never come out
  /// dark. The selected icon ([selectedIcon]) and label ([selectedLabel]) read
  /// cleanly on it — brand blue `#2563EB` measures ~4.7:1 against this fill.
  ///
  /// Light-theme-only by construction: dark mode keeps its white lift.
  static const Color lightIndicatorFill = Color(0xFFDBEAFE);

  /// The material the pill wears **while it travels**, for light mode.
  ///
  /// The material the pill wears **while it travels**, for light mode.
  ///
  /// The package's default indicator material is a near-transparent white lift,
  /// invisible over light glass, so on a light bar the pill vanished for the
  /// length of every trip and reappeared on arrival. This changes the tint and
  /// *only* the tint.
  ///
  /// That is what the single field buys. `AnimatedGlassIndicator` merges these
  /// settings over its own `baseIndicatorSettings` and treats any field left at
  /// the `LiquidGlassSettings()` constructor default as "not overridden", so
  /// everything the rim is made of — `lightIntensity`, `lightAngle`,
  /// `refractiveIndex`, `chromaticAberration`, thickness — comes through from
  /// the base untouched, which is the same base dark mode gets by passing null.
  /// The two themes' pills therefore have an identical edge by construction
  /// rather than by two sets of numbers that have to be kept in sync. An
  /// earlier version spelled out a flat chip here (index 1.0, lightIntensity
  /// 0.6) and lost the rim highlight and the iridescent fringe with it.
  ///
  /// The tint goes in at full alpha deliberately. Here alpha is the shader's
  /// mix factor, not opacity, and the travelling body's opacity is pinned at
  /// 0.70 by the package regardless — so handing it the resting chip's own 0.10
  /// would read as "barely tint this" and the pill would cross as an outline.
  ///
  /// Dark mode deliberately has no equivalent: the package lens already lifts
  /// off dark glass correctly, so [GlassTabBar.indicatorSettings] is left null
  /// there rather than given a value that happens to match.
  static LiquidGlassSettings travellingPill(Brightness brightness) {
    assert(brightness == Brightness.light,
        'Dark mode keeps the package indicator material; pass null instead.');
    // `thickness` is the width of the rim band: the base's 20 is the whole
    // reason the edge reads as a fat bevel. 3 keeps the same highlight and
    // fringe, drawn as a hairline. It is the one field deliberately *not* inherited
    // from the base — a dark bar can carry a wide bevel, a white one shows
    // every pixel of it.
    //
    // The tint is [lightIndicatorFill] — the same light blue the resting chip
    // wears — so the cross-fade from resting chip to travelling lens has
    // nothing to give away. It used to be `Color(0xFF1F2126)` (near-black),
    // which on web (no glass shader) meant the pill turned into a dark slab the
    // instant it started moving.
    return const LiquidGlassSettings(
      glassColor: lightIndicatorFill,
      thickness: 3,
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
  /// periwinkle; raising lightness while holding hue and saturation keeps it
  /// reading as a *blue* that happens to be bright.
  ///
  /// ## Why the lift is as small as it is
  ///
  /// Every other blue icon in the app — the profile tiles especially, which
  /// sit directly above this bar — is `colorScheme.primary`, i.e.
  /// [AppTheme.primaryBlue] unmodified in both themes. Light mode returns that
  /// value, so the two already match there. Dark mode cannot: brand blue on
  /// the selection pill measures 2.68:1, under the 3:1 floor.
  ///
  /// So the *only* thing changed is lightness, and only by as much as the
  /// floor demands. Saturation used to be pinned at 1.0, above brand's own
  /// 0.832 — that made the nav blue more vivid than every other blue on
  /// screen, which is a second way to not match. Inheriting brand's saturation
  /// leaves lightness as the single axis of difference.
  ///
  /// L=0.57 is the lowest step that clears the floor, at 3.07:1. The margin is
  /// thin by construction: anything wider is a blue further from the one the
  /// rest of the app uses. It is deterministic — these are constants, not
  /// runtime values — and the contrast test recomputes it, so a drift in the
  /// pill tint fails there rather than shipping.
  static const double _darkIconLightness = 0.57;

  static Color selectedIcon(Brightness brightness) {
    if (brightness == Brightness.light) return AppTheme.primaryBlue;
    final HSLColor brand = HSLColor.fromColor(AppTheme.primaryBlue);
    return brand.withLightness(_darkIconLightness).toColor();
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
  ///
  /// [AppTheme.fontFamily] is spelled out rather than inherited. This style is
  /// handed straight to `GlassTabBar`, not merged into a `DefaultTextStyle`, so
  /// with `fontFamily` left null it resolved to Roboto — which CanvasKit fetches
  /// from fonts.gstatic.com instead of shipping, so a blocked or slow fetch left
  /// the nav labels laid out and unpainted.
  static TextStyle labelStyle({required bool selected}) {
    return TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: labelSize,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.1,
    );
  }
}
