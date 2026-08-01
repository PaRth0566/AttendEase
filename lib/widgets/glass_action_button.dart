import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/glass_nav_theme.dart';

/// A floating action pill cut from the same glass as the bottom nav bar.
///
/// ## The idea: a tab that floated up out of the bar
///
/// Everything that identifies the bar is reused rather than approximated —
/// [GlassNavTheme.settings] for the material, a fully-round radius, the nav's
/// label treatment, and the same accent ink the selected tab uses. The pill is
/// shorter than the bar and shares its right edge, so it reads as a member of
/// that family sitting above it rather than a control that happens to be
/// nearby.
///
/// The one thing deliberately *not* borrowed is the selected tab's tint. The
/// bar's own thesis is that everything is glass and contrast comes from the
/// ink, so tinting this would make it a different material — the accent
/// colour on the icon and label is what marks it as the actionable one.
///
/// Must be rendered inside an [AdaptiveLiquidGlassLayer] (the app shell
/// provides one) so the glass has a backdrop to refract.
class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// Shown uppercased to match the nav's tab labels. Write it in sentence
  /// case — 'Add record' — and it doubles as the semantic label.
  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color ink = GlassNavTheme.selectedIcon(brightness);

    // GlassButton lays its content out in a bare Align, which has no
    // widthFactor and so grows to whatever width it is offered. A null width
    // therefore *fills* rather than hugs, and in a Scaffold's FAB slot the
    // offer is the whole screen — which is how this ended up a full-width
    // slab. IntrinsicWidth hands it a tight constraint so it wraps the label.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: IntrinsicWidth(
        child: GlassButton.custom(
          onTap: onPressed,
          label: label,
          height: GlassNavTheme.actionHeight,
          shape: const LiquidRoundedSuperellipse(
            borderRadius: GlassNavTheme.actionRadius,
          ),
          settings: GlassNavTheme.settings(brightness),
          // Matches the bar, where the jelly deform and press bounce are both
          // off. A little scale is kept because this pill has no
          // selected/unselected state to change on press — without it there is
          // no feedback at all.
          stretch: 0,
          interactionScale: 1.03,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: GlassNavTheme.iconSize, color: ink),
                const SizedBox(width: 10),
                // Flexible, not bare Text: the 280px cap above clips a long
                // label otherwise instead of ellipsizing it.
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GlassNavTheme.labelStyle(selected: true).copyWith(
                      fontSize: GlassNavTheme.actionLabelSize,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
