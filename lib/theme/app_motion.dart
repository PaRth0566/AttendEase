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

  // ── Curves ────────────────────────────────────────────────
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard_ = Curves.easeInOut;

  /// Returns [base] unless the OS has "remove animations" enabled,
  /// in which case it returns [Duration.zero] — the single choke-point
  /// for reduced-motion / battery-saver support.
  static Duration duration(BuildContext context, Duration base) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    return base;
  }
}
