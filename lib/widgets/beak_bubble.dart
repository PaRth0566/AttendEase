import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_motion.dart';

/// Which edge the beak sits on — i.e. whether the bubble hangs below its anchor
/// (beak on top, pointing up) or sits above it (beak on the bottom).
enum BeakSide { top, bottom }

/// A small card-surfaced speech bubble with a beak pointing at its anchor.
///
/// Deliberately plain: it fades in place and does not expand or morph. Colours
/// are theme-adaptive — the app's own card surface and border — so it reads as a
/// small card in both themes rather than as the near-black slab a stock Material
/// tooltip paints in light mode. The fill, border and beak are drawn as one
/// unioned path, so the outline runs continuously around the beak with no seam
/// across its base.
///
/// Two shapes of caller, both of which live in the app:
///  * a **fixed** [width] (the dashboard's day popover, 240) — the message wraps
///    inside a column of known width;
///  * `width: null` (the calendar's "why can't I delete this" tooltip) — the
///    bubble takes its natural one-line width, and the caller bounds it with a
///    [ConstrainedBox] so a long message on a narrow phone wraps instead of
///    running off-screen.
class BeakBubble extends StatelessWidget {
  const BeakBubble({
    super.key,
    required this.beakCenterX,
    required this.message,
    this.width,
    this.beakSide = BeakSide.top,
  });

  /// Horizontal position of the beak's tip, measured from the bubble's left
  /// edge. Callers compute this *after* clamping the bubble on-screen, so the
  /// beak keeps pointing at the anchor even when the body has been pushed
  /// sideways.
  final double beakCenterX;

  final String message;

  /// Fixed body width, or null to size to the message.
  final double? width;

  final BeakSide beakSide;

  static const double beakWidth = 16;
  static const double beakHeight = 8;
  static const double _borderWidth = 1;

  /// Padding between the body's edge and the message.
  ///
  /// Public because a caller that has to know the bubble's size *before* laying
  /// it out — [BeakTooltip], which positions and aims the bubble itself — must
  /// measure the message with the same padding and style this paints it with.
  /// Two copies of those numbers is how a beak ends up pointing at nothing.
  static const double horizontalPadding = AppDimens.space12;
  static const double verticalPadding = AppDimens.space10;

  /// The message's text style, resolved against [context]'s theme.
  static TextStyle textStyle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: theme.textTheme.bodyMedium?.color ?? theme.cardColor,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final bool beakOnTop = beakSide == BeakSide.top;
    final dialogShape = theme.dialogTheme.shape;
    final border = dialogShape is RoundedRectangleBorder
        ? dialogShape.side.color
        : c.cardBorder;

    final Widget body = CustomPaint(
      painter: _BeakBubblePainter(
        fill: theme.dialogTheme.backgroundColor ?? theme.cardColor,
        border: border,
        borderWidth: _borderWidth,
        radius: AppDimens.radiusMd,
        beakCenterX: beakCenterX,
        beakWidth: beakWidth,
        beakHeight: beakHeight,
        beakOnTop: beakOnTop,
      ),
      // The beak's side gets its height added to the text padding, so the copy
      // is optically centred in the body rather than in the whole silhouette.
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          (beakOnTop ? beakHeight : 0) + verticalPadding,
          horizontalPadding,
          (beakOnTop ? 0 : beakHeight) + verticalPadding,
        ),
        child: Text(message, style: textStyle(context)),
      ),
    );

    return TweenAnimationBuilder<double>(
      duration: AppMotion.duration(context, AppMotion.fast),
      curve: AppMotion.enter,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: width == null
          // IntrinsicWidth so the bubble hugs a one-line message. The parent's
          // max width still applies, so an over-long message wraps rather than
          // overflowing.
          ? IntrinsicWidth(child: body)
          : SizedBox(width: width, child: body),
    );
  }
}

/// Paints the bubble silhouette — a rounded rect body with a beak on one edge —
/// as a single unioned path, then shadows, fills and strokes it, so the border
/// is continuous and there is no seam where the beak meets the body.
class _BeakBubblePainter extends CustomPainter {
  const _BeakBubblePainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.radius,
    required this.beakCenterX,
    required this.beakWidth,
    required this.beakHeight,
    required this.beakOnTop,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final double radius;
  final double beakCenterX;
  final double beakWidth;
  final double beakHeight;
  final bool beakOnTop;

  Path _buildPath(Size size) {
    final Rect bodyRect = beakOnTop
        ? Rect.fromLTWH(0, beakHeight, size.width, size.height - beakHeight)
        : Rect.fromLTWH(0, 0, size.width, size.height - beakHeight);
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(bodyRect, Radius.circular(radius)));

    // The beak's base dips 0.5px into the body so the union merges cleanly
    // instead of leaving a hairline where the two paths meet.
    final double tipY = beakOnTop ? 0 : size.height;
    final double baseY = beakOnTop
        ? beakHeight + 0.5
        : size.height - beakHeight - 0.5;
    // Kept clear of the rounded corners, or the beak would grow out of the arc.
    final double cx = beakCenterX.clamp(
      radius + beakWidth / 2,
      (size.width - radius - beakWidth / 2).clamp(
        radius + beakWidth / 2,
        size.width,
      ),
    );
    final beak = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - beakWidth / 2, baseY)
      ..lineTo(cx + beakWidth / 2, baseY)
      ..close();

    return Path.combine(PathOperation.union, body, beak);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(_BeakBubblePainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.radius != radius ||
      old.beakCenterX != beakCenterX ||
      old.beakWidth != beakWidth ||
      old.beakHeight != beakHeight ||
      old.beakOnTop != beakOnTop;
}
