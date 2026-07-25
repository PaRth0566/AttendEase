import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimens.dart';

/// Centralized design tokens for the web "Aura" screens.
///
/// Previously every hex literal was inlined across aura_landing_page,
/// aura_upload_config_web, and aura_ai_dashboard — three files with
/// three slightly different spellings of the same indigo/violet palette.
/// Everything now references these constants so the web UI reads as one
/// system, and semantic status colors route through [AppColors] so they
/// match mobile.
class AuraTokens {
  AuraTokens._();

  // ── Brand gradient ────────────────────────────────────────
  static const Color indigo = Color(0xFF6366F1);
  static const Color indigoDark = Color(0xFF4F46E5);
  static const Color indigoDeep = Color(0xFF4338CA);
  static const Color indigoDeeper = Color(0xFF312E81);
  static const Color indigoDeepest = Color(0xFF1E1B4B);
  static const Color violet = Color(0xFF7C3AED);
  static const Color violet2 = Color(0xFF8B5CF6);

  // ── Tint / container shades ───────────────────────────────
  static const Color indigoTint50 = Color(0xFFEEF2FF);
  static const Color indigoTint100 = Color(0xFFE0E7FF);
  static const Color indigoTint200 = Color(0xFFC7D2FE);
  static const Color indigoTint300 = Color(0xFFA5B4FC);
  static const Color indigoTint400 = Color(0xFF818CF8);
  static const Color violetTint200 = Color(0xFFC4B5FD);
  static const Color violetTint300 = Color(0xFFD8B4FE);

  // ── Slate backgrounds ─────────────────────────────────────
  static const Color slateBg = Color(0xFF020617);
  static const Color slateSurface = Color(0xFF0F172A);
  static const Color slateCard = Color(0xFF1E293B);
  static const Color slateBorder = Color(0xFF334155);
  static const Color slateText = Color(0xFF64748B);
  static const Color slateTextMuted = Color(0xFF94A3B8);
  static const Color slateTextSubtle = Color(0xFF475569);
  static const Color slateDivider = Color(0xFFCBD5E1);
  static const Color slateLightBg = Color(0xFFF1F5F9);
  static const Color slateLightDivider = Color(0xFFE2E8F0);

  // ── Blur sigmas (unified) ─────────────────────────────────
  static const double blurNav = 20;
  static const double blurCard = 20;
  static const double blurCardHeavy = 30;

  // ── Radius (reuses AppDimens) ─────────────────────────────
  static const double radiusCard = AppDimens.radiusLg;   // 16
  static const double radiusCardLg = AppDimens.radiusXl; // 20
  static const double radiusPill = AppDimens.radiusPill;

  // ── Gradients ─────────────────────────────────────────────
  static LinearGradient brandGradient({bool isDark = true}) => LinearGradient(
        colors: isDark
            ? [indigoTint300, indigoTint200]
            : [indigoDark, violet],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient buttonGradient = const LinearGradient(
    colors: [indigoDark, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Semantic status colors (routes through AppColors) ─────
  /// Use these instead of hardcoded green/amber/red so status colors
  /// match the mobile side.
  static Color success(BuildContext context) =>
      context.appColors.success;
  static Color successContainer(BuildContext context) =>
      context.appColors.successContainer;
  static Color warning(BuildContext context) =>
      context.appColors.warning;
  static Color warningContainer(BuildContext context) =>
      context.appColors.warningContainer;
  static Color danger(BuildContext context) =>
      context.appColors.danger;
  static Color dangerContainer(BuildContext context) =>
      context.appColors.dangerContainer;

  // ── Card decoration helpers ───────────────────────────────
  static BoxDecoration cardDecoration({required bool isDark}) => BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1B4B).withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(
          color: isDark
              ? indigoTint300.withValues(alpha: 0.2)
              : indigoTint200.withValues(alpha: 0.5),
        ),
      );

  static List<BoxShadow> cardShadow({required bool isDark}) => [
        BoxShadow(
          color: indigo.withValues(alpha: isDark ? 0.15 : 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
