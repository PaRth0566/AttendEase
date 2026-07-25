import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

enum CalloutKind { info, success, warning, danger }

/// A single tinted callout / banner box (icon + text + optional trailing).
///
/// Replaces the four divergent warning/info boxes (basic_info amber,
/// signup orange, upload_pdf indigo, refresh_pdf blue) and the dashboard
/// insight banners — all now share one shape and pull color from [AppColors].
class CalloutBox extends StatelessWidget {
  const CalloutBox({
    super.key,
    required this.kind,
    required this.message,
    this.title,
    this.icon,
    this.trailing,
  });

  final CalloutKind kind;
  final String message;
  final String? title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);

    late final Color fg;
    late final Color bg;
    late final Color onBg;
    late final IconData defaultIcon;
    switch (kind) {
      case CalloutKind.info:
        fg = theme.colorScheme.primary;
        bg = theme.colorScheme.primary.withValues(alpha: 0.10);
        onBg = theme.textTheme.bodyLarge?.color ?? fg;
        defaultIcon = Icons.info_outline_rounded;
        break;
      case CalloutKind.success:
        fg = c.success;
        bg = c.successContainer;
        onBg = c.onSuccessContainer;
        defaultIcon = Icons.check_circle_outline_rounded;
        break;
      case CalloutKind.warning:
        fg = c.warning;
        bg = c.warningContainer;
        onBg = c.onWarningContainer;
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case CalloutKind.danger:
        fg = c.danger;
        bg = c.dangerContainer;
        onBg = c.onDangerContainer;
        defaultIcon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppDimens.brLg,
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(fontWeight: FontWeight.bold, color: onBg),
                  ),
                  const SizedBox(height: AppDimens.space4),
                ],
                Text(
                  message,
                  style: TextStyle(fontSize: 13, height: 1.4, color: onBg),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDimens.space8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
