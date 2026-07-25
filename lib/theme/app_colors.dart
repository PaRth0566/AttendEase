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
    // Softer, friendlier emerald/rose tones (brighter than the old 16A34A/DC2626).
    success: Color(0xFF22C55E),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF166534),
    warning: Color(0xFFF59E0B),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    danger: Color(0xFFEF4444),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF991B1B),
    subtleSurface: Color(0xFFF8FAFC),
    cardBorder: Color(0xFFE2E8F0),
  );

  static const dark = AppColors(
    // Lighter containers so banners read as soft tints, not heavy dark blocks.
    success: Color(0xFF4ADE80),
    successContainer: Color(0xFF16432B),
    onSuccessContainer: Color(0xFFBBF7D0),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF5A3A12),
    onWarningContainer: Color(0xFFFDE68A),
    danger: Color(0xFFF87171),
    dangerContainer: Color(0xFF5A1D1D),
    onDangerContainer: Color(0xFFFECACA),
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
