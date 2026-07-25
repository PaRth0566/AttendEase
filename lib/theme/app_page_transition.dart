import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_motion.dart';
import 'container_transform.dart';

/// Shared page transition (fade) for the whole app.
///
/// Previously only 2 of ~25 routes animated. This is used both as a GoRouter
/// `pageBuilder` helper and as a `PageTransitionsBuilder` for `Navigator.push`.
class AppPageTransition {
  AppPageTransition._();

  /// Wraps [child] in a GoRouter [CustomTransitionPage] with the shared motion.
  static Page<dynamic> page(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.emphasized,
      // Matched to the forward duration. A 250ms reverse against a 350ms
      // forward made popping feel like a different, hastier animation.
      reverseTransitionDuration: AppMotion.emphasized,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return buildTransition(context, animation, child);
      },
    );
  }

  static Widget buildTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) return child;
    // Emphasized easing in both directions. The old easeOutCubic/easeInCubic
    // pair left at (and arrived back at) full velocity, which is what made
    // pushing and popping read as abrupt.
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.morph,
      reverseCurve: AppMotion.morph,
    );
    // Fade only. The 4%-of-height upward slide that used to wrap this is
    // removed app-wide; the emphasized curve is what carries the motion now.
    return FadeTransition(opacity: curved, child: child);
  }

  /// Container transform: the incoming screen grows out of the exact card or
  /// tile the user tapped, corners morphing flat as it fills the screen.
  ///
  /// Requires the tapped widget to be wrapped in a [ContainerTransformAnchor];
  /// without a recorded origin (deep link, redirect, programmatic navigation)
  /// this falls back to the shared fade + slide from [page].
  static Page<dynamic> containerPage(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.morphOpen,
      reverseTransitionDuration: AppMotion.morphClose,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final origin = ContainerTransformOrigin.claim(state.pageKey);
        if (origin == null) return buildTransition(context, animation, child);
        return ContainerTransformTransition(
          animation: animation,
          origin: origin,
          child: child,
        );
      },
    );
  }

  /// Centered scale + fade "morph". Kept for pages opened from something that
  /// has no single anchor rect (e.g. an app-bar action). Prefer
  /// [containerPage] when the origin is a card or tile.
  static Page<dynamic> morphPage(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: AppMotion.emphasized,
      reverseTransitionDuration: AppMotion.emphasized,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.of(context).disableAnimations) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.morph,
          reverseCurve: AppMotion.morph,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// PageTransitionsBuilder so imperative `Navigator.push` matches GoRouter.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppPageTransition.buildTransition(context, animation, child);
  }
}
