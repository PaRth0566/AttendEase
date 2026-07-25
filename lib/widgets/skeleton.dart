import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';

/// A lightweight shimmer skeleton block. Replaces the bare `CircularProgressIndicator`
/// on data screens so loading feels intentional rather than blank.
///
/// The shimmer pauses automatically under reduced-motion (renders a static
/// muted block).
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE9EDF5);
    final highlight = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F7FB);
    final radius = widget.borderRadius ?? AppDimens.brSm;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1 - _controller.value * 2, 0),
              end: Alignment(1 - _controller.value * 2, 0),
            ),
          ),
        );
      },
    );
  }
}

/// A card-shaped skeleton placeholder used in list loading states.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 92});

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: AppDimens.brMd,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Skeleton(width: 140, height: 16),
          SizedBox(height: AppDimens.space12),
          Skeleton(height: 10, borderRadius: AppDimens.brSm),
          SizedBox(height: AppDimens.space8),
          Skeleton(width: 90, height: 10),
        ],
      ),
    );
  }
}

/// A column of [SkeletonCard]s for full-list loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding ?? const EdgeInsets.all(AppDimens.space16),
      children: List.generate(count, (_) => const SkeletonCard()),
    );
  }
}
