import 'package:flutter/widgets.dart';

/// Central spacing & radius scale for the whole app.
///
/// Before this, screens used an ad-hoc mix of 8/12/14/16/20/24 for both
/// padding and corner radius. Everything now references these constants so the
/// UI reads as one system.
class AppDimens {
  AppDimens._();

  // ── Spacing scale ─────────────────────────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  // ── Corner radius scale ───────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusPill = 100;

  static const Radius rSm = Radius.circular(radiusSm);
  static const Radius rMd = Radius.circular(radiusMd);
  static const Radius rLg = Radius.circular(radiusLg);
  static const Radius rXl = Radius.circular(radiusXl);

  static const BorderRadius brSm = BorderRadius.all(rSm);
  static const BorderRadius brMd = BorderRadius.all(rMd);
  static const BorderRadius brLg = BorderRadius.all(rLg);
  static const BorderRadius brXl = BorderRadius.all(rXl);

  // ── Content width caps (already used ad-hoc across screens) ─
  static const double maxContentNarrow = 540;
  static const double maxContentMedium = 600;
  static const double maxContentWide = 700;
}
