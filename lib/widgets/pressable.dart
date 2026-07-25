import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

/// A tappable surface with a subtle press-scale + ink ripple.
///
/// Promoted from the dashboard's private `_PressableCard` so every tappable
/// card/tile across the app shares the same premium press feel. Honors
/// reduced-motion (scale is skipped when animations are disabled).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.borderRadius,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final bool enableFeedback;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.onTap != null || widget.onLongPress != null;
    final double scale = _pressed ? widget.pressedScale : 1.0;

    return AnimatedScale(
      scale: MediaQuery.of(context).disableAnimations ? 1.0 : scale,
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        clipBehavior: widget.borderRadius != null ? Clip.antiAlias : Clip.none,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: interactive ? (_) => _setPressed(true) : null,
          onTapUp: interactive ? (_) => _setPressed(false) : null,
          onTapCancel: interactive ? () => _setPressed(false) : null,
          borderRadius: widget.borderRadius,
          enableFeedback: widget.enableFeedback,
          child: widget.child,
        ),
      ),
    );
  }
}
