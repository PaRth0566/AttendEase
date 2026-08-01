import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Dialogs and bottom sheets that open with the same motion language as the
/// app's container-transform page transitions.
///
/// Flutter's stock `showDialog` uses a fixed 150ms fade + 0.7→1.0 scale that
/// reads noticeably snappier and springier than the rest of AttendEase. These
/// helpers route everything through [AppMotion] so durations, curves and
/// reduced-motion handling live in one place.

/// Drop-in replacement for `showDialog` with the app's scale + fade motion.
///
/// Also clamps text scaling inside the dialog. `AlertDialog` lays its `content`
/// out at intrinsic height with no scroll view of its own, so at large OS font
/// scales a content Column can exceed the viewport and overflow. Clamping the
/// upper bound keeps dialogs legible without letting them grow unbounded;
/// individual dialogs with genuinely long content should still pass a
/// `SingleChildScrollView` as their `content`.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  double maxTextScaleFactor = 1.4,
}) {
  final bool reduceMotion = MediaQuery.of(context).disableAnimations;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    barrierColor: barrierColor ?? Colors.black54,
    // Dialogs keep the shorter duration — a dialog is small and often
    // dismissed in a hurry, so the smoothness here comes from the easing, not
    // from stretching the timing out. (RawDialogRoute reuses this for the
    // reverse; there is no separate close duration to set.)
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.standard,
    pageBuilder: (context, animation, secondaryAnimation) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScaleFactor,
      child: builder(context),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.morph,
        reverseCurve: AppMotion.morph,
      );
      return FadeTransition(
        // Opacity leads the scale slightly, so the dialog is already legible
        // as it settles instead of popping into place at the last moment.
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.7, curve: AppMotion.emphasizedDecelerate),
          reverseCurve: AppMotion.exit,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Drop-in replacement for `showModalBottomSheet` whose slide-up is timed with
/// [AppMotion] instead of Flutter's default 250ms/200ms pair.
///
/// By default the sheet is height-capped at [maxHeightFactor] of the viewport
/// and its content is wrapped in a scroll view, so a tall sheet — or a short one
/// that grows past the viewport at large OS font scales — scrolls instead of
/// overflowing. The wrapper also lifts content above the soft keyboard, so call
/// sites should *not* add their own `viewInsets.bottom` padding.
///
/// Pass `selfSizing: true` for sheets that manage their own height and expect a
/// bounded constraint — e.g. a frame whose child is `Flexible` around a
/// `ListView`. Those break under the scroll view, which offers infinite height.
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  EdgeInsets? padding,
  double maxHeightFactor = 0.85,
  bool selfSizing = false,
}) {
  final bool reduceMotion = MediaQuery.of(context).disableAnimations;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    // Retimed via sheetAnimationStyle rather than by handing in our own
    // transitionAnimationController: the route disposes controllers it creates
    // itself, whereas one we supply would be ours to dispose — and the only
    // hook for that (the future below) fires when the pop *starts*, so
    // disposing there kills the slide-down and strands the sheet on screen.
    sheetAnimationStyle: AnimationStyle(
      duration: reduceMotion ? Duration.zero : AppMotion.morphOpen,
      reverseDuration: reduceMotion ? Duration.zero : AppMotion.morphClose,
    ),
    builder: (context) {
      final Widget content = padding == null
          ? builder(context)
          : Padding(padding: padding, child: builder(context));
      if (selfSizing) return content;
      // Cap at a fraction of the viewport and scroll the overflow. The
      // ConstrainedBox alone is not enough — without the scroll view a Column
      // taller than the cap still throws.
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: SingleChildScrollView(
          // Lift content above the soft keyboard when a sheet contains inputs.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: content,
        ),
      );
    },
  );
}
