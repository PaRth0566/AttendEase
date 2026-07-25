import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_dimens.dart';
import 'app_motion.dart';

/// Container-transform ("open") motion, ported from the budget app's settings
/// screen.
///
/// The budget app wraps every settings row in `OpenContainer` (from the
/// `animations` package) so the tapped row physically expands into the full
/// page. `OpenContainer` pushes its own route internally, which would bypass
/// GoRouter entirely — AttendEase is fully router-driven, so instead we split
/// the effect in two:
///
///  * [ContainerTransformAnchor] records the screen rect of whatever the user
///    is about to tap (on pointer-down, so the child's own `onTap` is
///    untouched).
///  * `AppPageTransition.containerPage` reads that rect and morphs the incoming
///    route out of it.
///
/// URLs, deep links, redirect guards and the back stack all keep working.

/// A recorded tap origin: where on screen the transform should start from.
@immutable
class ContainerTransformRect {
  const ContainerTransformRect(this.rect, this.radius);

  final Rect rect;
  final double radius;
}

/// Registry connecting a tapped [ContainerTransformAnchor] to the route that
/// the tap ends up opening.
///
/// Flow: pointer-down stores a *pending* origin; the first
/// `containerPage` transition built afterwards [claim]s it and keeps it for the
/// lifetime of that page key, so the reverse (pop) animation morphs back into
/// the same spot.
class ContainerTransformOrigin {
  ContainerTransformOrigin._();

  static ContainerTransformRect? _pending;
  static DateTime? _pendingAt;
  static final Map<Object, ContainerTransformRect> _claimed = {};

  /// How long a pending origin stays usable. Guards against a route opened
  /// programmatically (deep link, redirect, post-async navigation) inheriting
  /// the rect of some unrelated tile the user touched much earlier.
  static const Duration _freshness = Duration(seconds: 1);

  /// Called by [ContainerTransformAnchor] on pointer-down.
  static void record(Rect rect, double radius) {
    _pending = ContainerTransformRect(rect, radius);
    _pendingAt = DateTime.now();
  }

  /// Discards any pending origin, so the next route uses the default page
  /// transition. Use for navigation that shouldn't read as "this thing opened".
  static void clear() {
    _pending = null;
    _pendingAt = null;
  }

  /// Returns the origin the route under [pageKey] should morph out of.
  ///
  /// A fresh pending origin always wins — reopening the same page after
  /// scrolling must start from where the tile is *now*, not where it was last
  /// time. Otherwise the previously claimed origin is returned, so the
  /// per-frame calls during a transition (and the reverse animation on pop) all
  /// agree on one rect.
  static ContainerTransformRect? claim(Object pageKey) {
    final pending = _takeFresh();
    if (pending != null) {
      _claimed[pageKey] = pending;
      return pending;
    }
    return _claimed[pageKey];
  }

  /// Consumes the pending origin if it was recorded recently enough to belong
  /// to the navigation that is starting right now.
  static ContainerTransformRect? _takeFresh() {
    final pending = _pending;
    final at = _pendingAt;
    if (pending == null || at == null) return null;
    clear();
    if (DateTime.now().difference(at) > _freshness) return null;
    return pending;
  }

  @visibleForTesting
  static void resetForTesting() {
    clear();
    _claimed.clear();
  }
}

/// Wraps a tappable card/tile so that the route it opens grows out of it.
///
/// Uses a translucent [Listener] rather than owning the gesture, so existing
/// `Pressable` / `InkWell` / `ListTile` taps inside [child] keep working
/// exactly as before — this only measures.
///
/// [borderRadius] should match the child's own corner radius so the corners
/// morph smoothly into the full-screen page.
class ContainerTransformAnchor extends StatefulWidget {
  const ContainerTransformAnchor({
    super.key,
    required this.child,
    this.borderRadius = AppDimens.radiusMd,
    this.enabled = true,
  });

  final Widget child;
  final double borderRadius;
  final bool enabled;

  @override
  State<ContainerTransformAnchor> createState() =>
      _ContainerTransformAnchorState();
}

class _ContainerTransformAnchorState extends State<ContainerTransformAnchor> {
  final GlobalKey _anchorKey = GlobalKey();

  void _recordOrigin() {
    if (!widget.enabled) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    ContainerTransformOrigin.record(
      box.localToGlobal(Offset.zero) & box.size,
      widget.borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _anchorKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordOrigin(),
      child: widget.child,
    );
  }
}

/// Animates [child] growing from [origin] to fill the screen, fading its
/// contents in as it goes — the Material container transform.
///
/// Runs in reverse on pop, shrinking the page back into the tile it came from.
class ContainerTransformTransition extends StatelessWidget {
  const ContainerTransformTransition({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final ContainerTransformRect origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.disableAnimations) return child;

    final Size screen = media.size;
    final Rect full = Offset.zero & screen;
    final Color surface = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Curve applied by hand rather than via CurvedAnimation: this builds
        // every frame, and a CurvedAnimation allocated here would never be
        // disposed. Emphasized easing runs both ways so opening and closing
        // ease off the tile and settle onto it instead of snapping.
        final double t =
            AppMotion.morph.transform(animation.value.clamp(0.0, 1.0));
        // Settled: hand the page through untouched so the arrived screen isn't
        // paying for an extra Stack/Material/clip layer for its whole life.
        if (t >= 1.0) return child!;

        final Rect rect = Rect.lerp(origin.rect, full, t)!;
        final double radius = lerpDouble(origin.radius, 0, t)!;

        // The page is revealed by fading a surface-coloured sheet off the top
        // of it, rather than by fading the page itself. Same look, but an
        // Opacity here would force a full-screen saveLayer on every frame of
        // the reveal — the most expensive thing in the whole transition, and
        // exactly where dropped frames show up.
        final double veil =
            1 - (((t - 0.10) / 0.45).clamp(0.0, 1.0));
        // Lift the card while it's in flight, settle it back down on arrival.
        final double elevation = 6 * (1 - (2 * t - 1) * (2 * t - 1));

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Material(
                color: surface,
                elevation: elevation,
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: Clip.antiAlias,
                // Taps landing mid-flight would hit whatever happens to be
                // under the cursor in a page that is still moving.
                child: IgnorePointer(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: screen.width,
                    maxWidth: screen.width,
                    minHeight: screen.height,
                    maxHeight: screen.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        child!,
                        if (veil > 0)
                          ColoredBox(
                            color: surface.withValues(alpha: veil),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
