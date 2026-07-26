import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

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
