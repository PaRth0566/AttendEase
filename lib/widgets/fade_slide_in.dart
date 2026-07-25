import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

/// A one-shot fade-in entrance, optionally staggered by [index].
///
/// Replaces the copy-pasted `TweenAnimationBuilder` translate+opacity blocks
/// that appeared in the dashboard and calendar. Honors reduced-motion (renders
/// the child immediately when animations are disabled).
///
/// The upward slide this used to pair with the fade is gone, along with the
/// `offsetY` that controlled it. It was the most visible motion on a tab
/// switch: the shell rebuilds each tab's page on selection, so every card
/// replayed its entrance every time you came back to a tab, staggered.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration,
    this.staggerStep = const Duration(milliseconds: 55),
  });

  final Widget child;
  final int index;
  final Duration? duration;
  final Duration staggerStep;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? AppMotion.emphasized,
    );
    _curved = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.status == AnimationStatus.dismissed) {
      if (MediaQuery.of(context).disableAnimations) {
        _controller.value = 1;
      } else {
        Future.delayed(widget.staggerStep * widget.index, () {
          if (mounted) _controller.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        return Opacity(opacity: _curved.value, child: child);
      },
      child: widget.child,
    );
  }
}

/// Animated count-up number. Unifies the count-up used on the dashboard ring
/// and subject-detail percentage. Honors reduced-motion (jumps to [value]).
class CountUpText extends StatelessWidget {
  const CountUpText(
    this.value, {
    super.key,
    this.suffix = '',
    this.fractionDigits = 1,
    this.style,
    this.duration,
  });

  final double value;
  final String suffix;
  final int fractionDigits;
  final TextStyle? style;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final d = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : (duration ?? AppMotion.slow);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: d,
      curve: AppMotion.enter,
      builder: (context, v, _) => Text(
        '${v.toStringAsFixed(fractionDigits)}$suffix',
        style: style,
      ),
    );
  }
}
