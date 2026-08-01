import 'package:flutter/material.dart';

/// Full-width primary action button with an inline loading state.
///
/// Kills the repeated `SizedBox(width: double.infinity, child: ElevatedButton(...))`
/// + inline spinner pattern that appeared in report, auth, setup and bug-report.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
        : (icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));

    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Full-width secondary (outlined) action button.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = icon != null
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          )
        : OutlinedButton(
            onPressed: onPressed,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The Back + Next button pair used across the setup wizard screens.
/// Replaces four near-identical inline `Row(OutlinedButton, ElevatedButton)`.
class SetupNavButtons extends StatelessWidget {
  const SetupNavButtons({
    super.key,
    this.onBack,
    required this.onNext,
    this.nextLabel = 'Next',
    this.backLabel = 'Back',
    this.nextLoading = false,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final String backLabel;
  final bool nextLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: onBack,
              child: Text(backLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: onBack != null ? 1 : 2,
          child: PrimaryButton(
            label: nextLabel,
            loading: nextLoading,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}
