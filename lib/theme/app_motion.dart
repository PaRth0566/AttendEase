import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Motion tokens for the whole app.
///
/// All durations and curves live here so animation feel is consistent and
/// reduced-motion support is handled in one place.
class AppMotion {
  AppMotion._();

  // ── Durations ─────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration emphasized = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 600);

  /// Container transform (a card growing into a full page).
  ///
  /// Longer than [emphasized] on purpose: the box travels most of the screen,
  /// and at 350ms that distance has to be covered fast enough to read as a
  /// jump. Material's own spec puts large container transforms at ~500ms.
  /// Closing is only slightly quicker — a much shorter reverse (the old 250ms)
  /// makes dismissing feel clipped rather than snappy.
  static const Duration morphOpen = Duration(milliseconds: 450);
  static const Duration morphClose = Duration(milliseconds: 400);

  /// The card→page container transform specifically.
  ///
  /// One duration for both directions — `OpenContainer` has a single
  /// `transitionDuration`, and splitting it (450 open / 400 close) made the pop
  /// read as a different, hastier animation than the push.
  ///
  /// Roughly the budget app's 400ms (475ms on iOS). This was 300/340 for a
  /// while, cut on the reading that the reference pace lingers on a card that
  /// travels most of the screen — but that read the boxiness as slowness. With
  /// the corner collapse and the cross-fade fixed separately (see
  /// `container_transform.dart`), the shorter pace was simply abrupt: the card
  /// arrived before the eye could follow it becoming the page. iOS keeps a
  /// little more room, matching its slower system transitions.
  static Duration get morphContainer =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? const Duration(milliseconds: 480)
          : const Duration(milliseconds: 440);

  /// Easing for [morphContainer].
  ///
  /// `OpenContainer` drives its geometry with `fastOutSlowIn` (and
  /// `fastOutSlowIn.flipped` in reverse), and this followed it for a long time.
  /// It is the wrong curve for a box that crosses most of the screen:
  /// `fastOutSlowIn` is heavily front-loaded — about 80% grown by the timeline
  /// midpoint — so the card leaps almost the whole distance at once and then
  /// creeps the last little way. That leap is what reads as the morph being
  /// "direct", and no amount of extra duration fixes it, because lengthening
  /// the flight only stretches the crawl at the end.
  ///
  /// M3's emphasized easing is slow at both ends and quick through the middle,
  /// so the box eases off the card, covers the distance, and settles onto the
  /// page. **This is a deliberate deviation from the reference port** — revert
  /// to [Curves.fastOutSlowIn] here to get the faithful geometry back.
  static const Curve morphContainerCurve = Curves.easeInOutCubicEmphasized;

  // ── Curves ────────────────────────────────────────────────
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard_ = Curves.easeInOut;

  /// Material 3's emphasized easing — slow at both ends, quick through the
  /// middle.
  ///
  /// This is what makes a morph feel smooth rather than abrupt: [enter]
  /// (easeOutCubic) leaves at maximum velocity, so a box anchored to a tile
  /// appears to snap away from it on the first frame. [exit] has the mirrored
  /// problem on the way back, slamming into the tile at full speed.
  static const Curve morph = Curves.easeInOutCubicEmphasized;

  /// Emphasized easing for things that only ever animate in one direction
  /// (fades, entrances) — decelerating, with a gentler start than [enter].
  static const Curve emphasizedDecelerate = Curves.fastEaseInToSlowEaseOut;

  /// Returns [base] unless the OS has "remove animations" enabled,
  /// in which case it returns [Duration.zero] — the single choke-point
  /// for reduced-motion / battery-saver support.
  static Duration duration(BuildContext context, Duration base) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    return base;
  }
}
