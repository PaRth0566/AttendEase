import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';

/// A single step in [PdfSourceHeroCard]'s progress indicator.
class PdfSourceStep {
  const PdfSourceStep(this.label);
  final String label;
}

/// Hero card at the top of the Upload / Sync / (re-skinned) Bug-report screens.
///
/// A circled glyph + heading + two-line subtitle, and — when [steps] is given —
/// a hairline divider followed by a numbered step indicator. Shared so the
/// setup upload flow and the dashboard sync flow are visibly the same screen
/// with different copy (IMPLEMENTATION_SPEC §8).
class PdfSourceHeroCard extends StatelessWidget {
  const PdfSourceHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.steps,
    this.currentStep = 1,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// When null, no step indicator is drawn (e.g. the one-step bug-report form).
  final List<PdfSourceStep>? steps;

  /// 1-based index of the active step.
  final int currentStep;

  /// Glyph tint; defaults to [ColorScheme.primary].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color fg = accent ?? theme.colorScheme.primary;
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: secondary.withAlpha(20),
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Icon(icon, size: 32, color: fg),
              ),
              const SizedBox(width: AppDimens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: secondary, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (steps != null && steps!.isNotEmpty) ...[
            const SizedBox(height: AppDimens.space20),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
            const SizedBox(height: AppDimens.space16),
            _StepIndicator(
              steps: steps!,
              currentStep: currentStep,
              accent: fg,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.steps,
    required this.currentStep,
    required this.accent,
  });

  final List<PdfSourceStep> steps;
  final int currentStep;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color muted = theme.dividerColor;
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final int stepNum = i + 1;
      final bool active = stepNum <= currentStep;
      children.add(
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: active ? accent : muted),
                ),
                child: Text(
                  '$stepNum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : secondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  steps[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: active ? theme.textTheme.bodyLarge?.color : secondary,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (i < steps.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: muted,
            ),
          ),
        );
      }
    }
    return Row(children: children);
  }
}

/// Accent-outlined action card: rounded-square icon tile, title + two-line
/// subtitle, and a circular chevron. Used for both the "Select PDF" (primary /
/// blue) and "Download from SAP" (secondary / amber) actions.
class PdfSourceCard extends StatelessWidget {
  const PdfSourceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    return Material(
      color: accent.withAlpha(theme.brightness == Brightness.dark ? 18 : 12),
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: accent.withAlpha(140), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppDimens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: secondary, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_right_rounded, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain footer card: shield glyph + bold title + subtitle. Reassures the user
/// about the scope of the data operation.
class ReassuranceCard extends StatelessWidget {
  const ReassuranceCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: secondary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined, color: secondary, size: 22),
          ),
          const SizedBox(width: AppDimens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: secondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
