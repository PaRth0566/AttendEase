import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';

/// A single, consistent empty-state block (icon + message + optional action).
///
/// Generalizes the calendar's `_emptyState` so the dashboard, report,
/// subject-detail, add-subjects and web dashboard all show the same thing
/// instead of a bare `Text`.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String message;
  final String? title;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? AppDimens.space16 : AppDimens.space20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 32 : 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppDimens.space16),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppDimens.space8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
            if (action != null) ...[
              const SizedBox(height: AppDimens.space20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
