import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';
import 'beak_bubble.dart';

/// A tap-triggered tooltip that shows a [BeakBubble] aimed at its child.
///
/// Why not a themed Material [Tooltip]: a tooltip's decoration is a
/// [Decoration], which cannot draw a beak, and its position delegate does not
/// report where the bubble ended up after clamping — so the beak could not be
/// aimed. This keeps the parts of `Tooltip` that matter (tap to open, auto-hide,
/// a screen-reader label) and does the anchoring itself, the same way the
/// dashboard's day popover does.
///
/// Tap-triggered on purpose. On touch there is no hover, and a long-press-only
/// tooltip is undiscoverable — an explanation nobody can find is not an
/// explanation. It also dismisses on a tap anywhere outside it.
class BeakTooltip extends StatefulWidget {
  const BeakTooltip({
    super.key,
    required this.message,
    required this.child,
    this.showDuration = const Duration(seconds: 3),
  });

  final String message;
  final Widget child;

  /// How long the bubble stays up before dismissing itself.
  final Duration showDuration;

  @override
  State<BeakTooltip> createState() => _BeakTooltipState();
}

class _BeakTooltipState extends State<BeakTooltip> {
  /// Measures the child, so the bubble can be anchored and aimed at it.
  final GlobalKey _anchorKey = GlobalKey();

  /// Ties the anchor and the open bubble into one [TapRegion] group.
  ///
  /// Without this, a tap on the anchor while the bubble is open is "outside" the
  /// bubble's region, so `onTapOutside` closes it and the anchor's own handler
  /// then reopens it in the same gesture — the tooltip could be opened but never
  /// closed by tapping it again. Grouping makes that tap "inside", so only the
  /// toggle runs. (A full-screen tap barrier is the other fix, and a worse one:
  /// it wins the gesture arena and eats the first tap on anything else.)
  final Object _groupId = Object();

  OverlayEntry? _bubble;
  Timer? _hideTimer;

  /// Gap between the anchor and the beak's tip.
  static const double _gap = 6;

  /// Minimum breathing room from the left and right screen edges.
  static const double _edgePad = AppDimens.space8;

  @override
  void didUpdateWidget(covariant BeakTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never leave stale text floating: a ListView recycles rows, so this widget
    // can be handed a different record's message while its bubble is open.
    if (oldWidget.message != widget.message) _hide();
  }

  @override
  void dispose() {
    // Cancel before removing, so a firing timer cannot reach into a disposed
    // State and touch an overlay entry that is already gone.
    _hideTimer?.cancel();
    _hideTimer = null;
    _bubble?.remove();
    _bubble = null;
    super.dispose();
  }

  void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _bubble?.remove();
    _bubble = null;
  }

  void _toggle() {
    if (_bubble != null) {
      _hide();
      return;
    }

    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(context);
    // Measured in the overlay's coordinate space rather than the screen's: an
    // overlay nested inside a padded or offset ancestor does not start at (0,0).
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;

    final Offset anchor = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Size anchorSize = box.size;
    final Size space = overlayBox.size;

    // ── Size the bubble up front ──────────────────────────────────────
    //
    // Everything below — the horizontal clamp, the beak's offset, the decision
    // to hang below or flip above — needs the bubble's box before it exists. So
    // the message is measured with the same style and padding BeakBubble paints
    // it with, rather than laid out and inspected afterwards. Reading geometry
    // back out of a render object during build is the alternative, and on the
    // first frame it reads a box that has not been positioned yet.
    final double maxBubbleWidth = space.width - _edgePad * 2;
    final double maxTextWidth =
        maxBubbleWidth - BeakBubble.horizontalPadding * 2;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.message, style: BeakBubble.textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxTextWidth < 0 ? 0 : maxTextWidth);

    final double bubbleWidth =
        (painter.width + BeakBubble.horizontalPadding * 2)
            .clamp(0.0, maxBubbleWidth);
    final double bubbleHeight = painter.height +
        BeakBubble.verticalPadding * 2 +
        BeakBubble.beakHeight;
    painter.dispose();

    // ── Place it ──────────────────────────────────────────────────────
    final double anchorCenterX = anchor.dx + anchorSize.width / 2;
    final double belowTop = anchor.dy + anchorSize.height + _gap;

    // Hang below when it fits, flip above when it does not — a bubble clipped by
    // the bottom of the screen explains nothing. Now an exact test, not an
    // estimate, because the height is measured.
    final bool below = belowTop + bubbleHeight <= space.height - _edgePad;

    // Centre on the anchor, then clamp on-screen. maxLeft can fall below
    // _edgePad on a very narrow screen, so the lo <= hi order is guarded.
    final double maxLeft = space.width - _edgePad - bubbleWidth;
    final double left = maxLeft <= _edgePad
        ? _edgePad
        : (anchorCenterX - bubbleWidth / 2).clamp(_edgePad, maxLeft);
    // Keep the beak on the anchor after clamping. BeakBubble clamps this clear
    // of its own corners too; this bound just keeps it inside the body.
    final double beakCenterX =
        (anchorCenterX - left).clamp(0.0, bubbleWidth);

    _bubble = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: below ? belowTop : null,
        // Anchored to the overlay's bottom when flipped, so the bubble's lower
        // edge — where its beak now is — lands _gap above the child.
        bottom: below ? null : space.height - anchor.dy + _gap,
        width: bubbleWidth,
        child: TapRegion(
          groupId: _groupId,
          onTapOutside: (_) => _hide(),
          child: BeakBubble(
            message: widget.message,
            width: bubbleWidth,
            beakSide: below ? BeakSide.top : BeakSide.bottom,
            beakCenterX: beakCenterX,
          ),
        ),
      ),
    );
    overlay.insert(_bubble!);

    _hideTimer = Timer(widget.showDuration, _hide);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // What a stock Tooltip contributes to the accessibility tree; the bubble
      // itself is decorative once this is here.
      tooltip: widget.message,
      child: TapRegion(
        groupId: _groupId,
        child: GestureDetector(
          key: _anchorKey,
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: widget.child,
        ),
      ),
    );
  }
}
