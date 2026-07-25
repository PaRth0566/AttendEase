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
