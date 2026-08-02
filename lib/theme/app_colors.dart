import 'package:flutter/material.dart';

/// Semantic color tokens as a [ThemeExtension].
///
/// Replaces ~50 hardcoded `Colors.green` / `Colors.red` / `Colors.orange`
/// calls and their per-screen `isDark` branching. Access via:
///   `Theme.of(context).extension<AppColors>()!`
/// or the convenience getter:
///   `context.appColors`
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.subtleSurface,
    required this.cardBorder,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color subtleSurface;
  final Color cardBorder;

  static const light = AppColors(
    // Custom brand green/red — the single app-wide status pair. Used for status
    // text, progress bars and ring fills across dashboard, profile, calendar
    // and reports.
    success: Color(0xFF358D3E),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF166534),
    // Calmer amber than the old neon F59E0B — matched in weight to green/red.
    warning: Color(0xFFCB8420),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    danger: Color(0xFFF34032),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF991B1B),
    subtleSurface: Color(0xFFF8FAFC),
    cardBorder: Color(0xFFE2E8F0),
  );

  static const dark = AppColors(
    // Custom brand green/red — the single app-wide status pair (see [light]).
    success: Color(0xFF358D3E),
    // Message-line strips: your deep tones so the band reads as a calm, solid
    // surface rather than a bright tint.
    successContainer: Color(0xFF182719),
    onSuccessContainer: Color(0xFF80C681),
    // Calmer amber than the old neon FBBF24 — the vivid one "glowed" on the
    // calendar's dark tiles. Matched in weight to the green/red pair.
    warning: Color(0xFFD9932B),
    warningContainer: Color(0xFF4A2F0E),
    onWarningContainer: Color(0xFFFDE68A),
    danger: Color(0xFFF34032),
    dangerContainer: Color(0xFF301716),
    onDangerContainer: Color(0xFFCF7A72),
    subtleSurface: Color(0xFF0F0F0F),
    cardBorder: Color(0xFF2A2A2A),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? subtleSurface,
    Color? cardBorder,
  }) {
    return AppColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      cardBorder: cardBorder ?? this.cardBorder,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
