import 'package:flutter/material.dart';
import 'theme_crossfade.dart';

/// A custom, ultra-smooth animated theme toggle switch with no inner icons.
///
/// Designed to animate its thumb sliding smoothly on the exact same 300ms
/// timeline as `ThemeCrossfade` using mask clipping, so both the thumb slide
/// and screen theme dissolve start and end together in 100% synchronization.
class SmoothThemeSwitch extends StatelessWidget {
  const SmoothThemeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  void _handleTap(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    Rect? maskRect;
    if (renderBox != null && renderBox.hasSize) {
      final origin = renderBox.localToGlobal(Offset.zero);
      maskRect = origin & renderBox.size;
    }

    final newValue = !value;
    final controller = ThemeCrossfade.maybeOf(context);
    if (controller != null) {
      controller.crossfade(
        () => onChanged(newValue),
        maskRect: maskRect,
        maskBorderRadius: BorderRadius.circular(20),
      );
    } else {
      onChanged(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = value;
    final primary = theme.colorScheme.primary;
    final inactiveColor = const Color(0xFFCBD5E1);

    return GestureDetector(
      onTap: () => _handleTap(context),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isDark ? primary : inactiveColor,
          boxShadow: [
            BoxShadow(
              color: (isDark ? primary : Colors.black).withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
