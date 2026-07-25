import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_motion.dart';

/// Shared page transition (fade + subtle upward slide) for the whole app.
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
      reverseTransitionDuration: AppMotion.standard,
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
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }

  /// Container-transform-style "morph" page: the incoming screen scales up from
  /// slightly smaller while fading in, reading as a card expanding open. Pair
  /// with a shared-element [Hero] (e.g. the subject title) for the full effect.
  static Page<dynamic> morphPage(GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: AppMotion.emphasized,
      reverseTransitionDuration: AppMotion.standard,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.of(context).disableAnimations) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.enter,
          reverseCurve: AppMotion.exit,
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
