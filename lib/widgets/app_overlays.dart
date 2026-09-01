import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Dialogs and bottom sheets that open with the same motion language as the
/// app's container-transform page transitions.
///
/// Flutter's stock `showDialog` uses a fixed 150ms fade + 0.7→1.0 scale that
/// reads noticeably snappier and springier than the rest of AttendEase. These
/// helpers route everything through [AppMotion] so durations, curves and
/// reduced-motion handling live in one place.

/// Max width of a dialog, matching Material's own dialog maximum.
///
/// Flutter's `Dialog` enforces a *minimum* width of 280 and no maximum, so a
/// dialog whose content has unbounded intrinsic width grows to fill the
/// viewport. Phone viewports are narrower than this, so the cap is a no-op
/// there.
const double maxDialogWidth = 560;

/// Drop-in replacement for `showDialog` with the app's scale + fade motion.
///
/// Also clamps text scaling inside the dialog. `AlertDialog` lays its `content`
/// out at intrinsic height with no scroll view of its own, so at large OS font
/// scales a content Column can exceed the viewport and overflow. Clamping the
/// upper bound keeps dialogs legible without letting them grow unbounded;
/// individual dialogs with genuinely long content should still pass a
/// `SingleChildScrollView` as their `content`.
///
/// Width is capped at [maxDialogWidth] for every dialog in the app. This is the
/// single funnel for all of them, so the cap belongs here rather than on each
/// `AlertDialog`.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  double maxTextScaleFactor = 1.4,
}) {
  final bool reduceMotion = MediaQuery.of(context).disableAnimations;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    barrierColor:
        barrierColor ??
        (isDark
            ? Colors.black.withValues(alpha: 0.72)
            : const Color(0x730F172A)),
    // Dialogs keep the shorter duration — a dialog is small and often
    // dismissed in a hurry, so the smoothness here comes from the easing, not
    // from stretching the timing out. (RawDialogRoute reuses this for the
    // reverse; there is no separate close duration to set.)
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.standard,
    pageBuilder: (context, animation, secondaryAnimation) =>
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScaleFactor,
          // Flutter's Dialog has no max width. A dialog whose content has unbounded
          // intrinsic width — the delete-account confirmation's bare TextField, for
          // one — therefore grows to the viewport minus insetPadding: measured
          // 1000 px wide at a 1080 px viewport, overlapping the page behind it.
          // [maxDialogWidth] is Material's dialog max; below that this is a no-op,
          // so phone layouts are untouched.
          //
          // The Center is load-bearing: without it the ConstrainedBox inherits the
          // route's tight constraints and the dialog pins to the left edge.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxDialogWidth),
              child: builder(context),
            ),
          ),
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
/// overflowing. The wrapper also lifts content above the soft keyboard *and*
/// above the Android 3-button navigation bar, so call sites should *not* add
/// their own `viewInsets.bottom` or safe-area padding.
///
/// Pass `selfSizing: true` for sheets that manage their own height and expect a
/// bounded constraint — e.g. a frame whose child is `Flexible` around a
/// `ListView`. Those break under the scroll view, which offers infinite height.
/// They still get the same bottom inset applied.
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  EdgeInsets? padding,
  double maxHeightFactor = 0.85,
  bool selfSizing = false,
}) {
  final bool reduceMotion = MediaQuery.of(context).disableAnimations;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    barrierColor:
        barrierColor ??
        (isDark
            ? Colors.black.withValues(alpha: 0.72)
            : const Color(0x730F172A)),
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

      // How much of the sheet's own bottom edge the system covers.
      //
      // The app renders edge-to-edge, so a bottom sheet's box extends to the
      // *physical* screen edge — underneath Android's 3-button navigation bar
      // where one is present. Without this the last rows of a sheet (Semester 8
      // in the Profile semester picker) were painted behind the back / home /
      // recents glyphs.
      //
      // `viewPadding`, not `padding`: `padding` is consumed by ancestor
      // `SafeArea`s and collapses to 0 while the keyboard is up, whereas
      // `viewPadding` is the raw inset the OS reports and nothing can eat it.
      // It is 0 on gesture-navigation and opaque-bar devices — there the OS
      // shrinks the window itself — so this is a no-op and those layouts are
      // unchanged. (Same reasoning as the nav capsule's inset in RootScreen.)
      //
      // `max`, not a sum: an open keyboard is drawn *over* the navigation bar,
      // so the two insets overlap rather than stack. Adding them would leave a
      // nav-bar-sized gap above the keyboard.
      final double bottomInset = math.max(
        MediaQuery.viewInsetsOf(context).bottom,
        MediaQuery.viewPaddingOf(context).bottom,
      );

      // Padding *outside* the scroll view, so the scroll viewport itself ends
      // above the system bar and rows never travel underneath it mid-scroll.
      // The sheet's Material still paints down to the screen edge, so the
      // surface stays flush with the bottom of the display.
      if (selfSizing) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: content,
        );
      }
      // Cap at a fraction of the viewport and scroll the overflow. The
      // ConstrainedBox alone is not enough — without the scroll view a Column
      // taller than the cap still throws. The inset comes off the cap so the
      // sheet's overall height (content + inset) still honours it.
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height * maxHeightFactor -
                        bottomInset)
                    .clamp(0.0, double.infinity),
          ),
          child: SingleChildScrollView(child: content),
        ),
      );
    },
  );
}
