import 'package:flutter/widgets.dart';

/// Centralized responsive breakpoints for app + web.
///
/// Before this, width comparisons were inlined per screen (`w < 768` in three
/// separate places in `aura_landing_page.dart` alone, `w < 1024` in the AI
/// dashboard), so the same logical breakpoint drifted between screens. Every
/// width decision now routes through here.
///
/// Two mobile boundaries exist on purpose:
/// * [mobile] (600) — app screens. A 600dp phone/tablet split matches the
///   Material guidance the app layouts were built against.
/// * [webMobile] (768) — web screens. The marketing/web layouts (hero, nav,
///   feature grid) were designed to collapse at 768 and look wrong collapsing
///   earlier, so web keeps its own named constant rather than silently
///   inheriting 600.
///
/// Both numbers live *only* here. Use the helpers, not raw comparisons.
class AppBreakpoints {
  AppBreakpoints._();

  /// App: `< 600` => phone.
  static const double mobile = 600;

  /// Web: `< 768` => phone-width browser window.
  static const double webMobile = 768;

  /// `>= 1024` => desktop / wide web. Shared by app and web.
  static const double tablet = 1024;

  static double widthOf(BuildContext c) => MediaQuery.sizeOf(c).width;

  // ── App-side helpers ──────────────────────────────────────
  static bool isMobile(BuildContext c) => widthOf(c) < mobile;

  static bool isTablet(BuildContext c) {
    final w = widthOf(c);
    return w >= mobile && w < tablet;
  }

  static bool isDesktop(BuildContext c) => widthOf(c) >= tablet;

  // ── Web-side helpers (768 boundary) ───────────────────────
  static bool isWebMobile(BuildContext c) => widthOf(c) < webMobile;

  static bool isWebTablet(BuildContext c) {
    final w = widthOf(c);
    return w >= webMobile && w < tablet;
  }

  /// Same as [isDesktop]; named for symmetry at web call sites.
  static bool isWebDesktop(BuildContext c) => widthOf(c) >= tablet;

  /// Horizontal page gutter that scales with width.
  static double gutter(BuildContext c) => isDesktop(c)
      ? 64
      : isTablet(c)
      ? 32
      : 16;

  /// Gutter for web pages, keyed off the 768 boundary.
  static double webGutter(BuildContext c) => isWebDesktop(c)
      ? 64
      : isWebTablet(c)
      ? 32
      : 20;

  /// Max content width so wide web/tablet doesn't stretch text lines.
  static double contentMaxWidth(BuildContext c) =>
      isDesktop(c) ? 1024 : double.infinity;
}
