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

/// A recorded tap origin: where on screen the transform should start from, plus
/// the card that was tapped so it can fly along with the box.
@immutable
class ContainerTransformRect {
  const ContainerTransformRect(this.rect, this.radius, {this.closedChild});

  final Rect rect;
  final double radius;

  /// The tapped card's own subtree, rebuilt inside the flying box.
  ///
  /// `OpenContainer` does exactly this with its `closedBuilder`: the card is
  /// scaled up with the box while the page fades in on top of it. That overlap
  /// is what makes the card appear to *become* the page — without it the box is
  /// a blank sheet and the card simply vanishes on the first frame.
  ///
  /// Rebuilt against the incoming route's context (as the reference does), so a
  /// subtree that must not exist twice — one holding a `GlobalKey`, or a `State`
  /// that owns a resource — should set `enabled: false` on its anchor.
  final Widget? closedChild;
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
  static void record(Rect rect, double radius, {Widget? closedChild}) {
    _pending = ContainerTransformRect(rect, radius, closedChild: closedChild);
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
      closedChild: widget.child,
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

/// Animates [child] growing from [origin] to fill the screen with the tapped
/// card scaling up inside it — the Material container transform.
///
/// Structurally a port of `_OpenContainerRoute.buildPage` from the `animations`
/// package (`ContainerTransitionType.fade`), which is what the budget app drives
/// through `OpenContainerNavigation`: both the card and the page are laid out at
/// their natural size and *scaled* into the flying box, and geometry follows the
/// curve while the card→page cross-fade follows the raw animation value.
///
/// Three of the reference's timings are deliberately **not** matched, because
/// they are what made this read as slow and boxy. See [_scrimAlpha],
/// [_cornerCollapse] and [_openOpacityForward] — each says what the reference
/// does and why we don't. Anyone re-syncing this against the budget app should
/// leave those three alone.
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

  /// Dims everything outside the flying box.
  ///
  /// Lighter than the reference's `Colors.black54`: at this speed a dim that
  /// deep reads as a modal slamming in rather than a card opening.
  static const Color scrimColor = Colors.black26;

  /// Lets tests find the scrim.
  static const Key scrimKey = Key('containerTransformScrim');

  /// How dark the scrim is at curve position [t].
  ///
  /// The reference ramps to full strength over the first *fifth* and holds it —
  /// which at any duration is a visible hard step near the start. Ramping across
  /// the whole flight instead means the dim is never faster than the box.
  static double _scrimAlpha(double t) => t;

  /// How far the corners have flattened at curve position [t].
  ///
  /// The reference collapses the radius linearly with the geometry, so the
  /// corners are essentially square by the halfway point and the remaining —
  /// largest, most visible — half of the flight is a hard rectangle. That is the
  /// "boxy" part. Easing it in holds most of the card's radius until the box is
  /// nearly home, so it stays a growing rounded card and squares off only as it
  /// becomes the page.
  // Called with the raw animation value v (pre-geometry-curve). Corners follow
  // the box's real screen progress, so the rounding melts continuously instead
  // of easing on top of an already-eased position (§2).
  static double _cornerCollapse(double v) =>
      Curves.easeInOutCubic.transform(v);

  /// The page's opacity as it fades in over the card.
  ///
  /// The reference crosses over in a fifth of the transition (0.2 → 0.4), which
  /// is abrupt — the card is replaced in a blink rather than becoming the page.
  /// Widened to over half the flight so the two genuinely overlap.
  static double _openOpacityForward(double v) =>
      ((v - 0.15) / 0.45).clamp(0.0, 1.0);

  /// [_openOpacityForward] mirrored for the pop: the page holds while the box
  /// starts shrinking, then hands back to the card over 0.85 → 0.40.
  static double _openOpacityReverse(double v) =>
      ((v - 0.40) / 0.45).clamp(0.0, 1.0);

  /// The card clone's own opacity.
  ///
  /// `ContainerTransitionType.fade` holds the closed child at a constant 1.0 for
  /// the whole flight, and this port followed it. That is fine for the
  /// reference's full-width settings rows, which barely change size; it is not
  /// fine for a dashboard card scaled to the full screen. `FittedBox` magnifies
  /// the clone's *contents* along with its box, so the card's 5px progress bar
  /// balloons into a thick band across the top of the screen and sits there,
  /// fully opaque, until the page finally covers it at v = 0.60.
  ///
  /// Fading the clone out instead lets it dissolve as it grows, so what you see
  /// is the card expanding rather than its insides being blown up. It reaches
  /// zero exactly where [_openOpacityForward] reaches one, so the two hand over
  /// with no seam and the surface never shows through on its own. Symmetric in
  /// v, so the pop brings the card back without a separate reverse curve.
  ///
  /// Deviation from the reference: this is `fadeThrough`'s treatment of the
  /// closed child, not `fade`'s. Return this to a constant 1.0 to get the
  /// faithful behaviour back.
  static double _closedOpacity(double v) =>
      1 - ((v - 0.25) / 0.35).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.disableAnimations) return child;

    final Size screen = media.size;
    final Rect full = Offset.zero & screen;
    final Color surface = Theme.of(context).scaffoldBackgroundColor;
    final Widget? closedChild = origin.closedChild;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Settled: hand the page through untouched so the arrived screen isn't
        // paying for an extra Stack/Material/clip layer for its whole life.
        // (The reference keeps a Material here; ours would be redundant — the
        // open colour is the scaffold background and the open shape is square.)
        if (animation.isCompleted) return child!;

        final bool reversing = animation.status == AnimationStatus.reverse;
        final double v = animation.value.clamp(0.0, 1.0);
        // `CurvedAnimation(curve: fastOutSlowIn, reverseCurve:
        // fastOutSlowIn.flipped)`, applied by hand: this builds every frame and
        // a CurvedAnimation allocated here would never be disposed. (The
        // reference drops the reverse curve when a transition is interrupted
        // mid-flight; we don't track that.)
        final double t = reversing
            ? 1 - AppMotion.morphContainerCurve.transform(1 - v)
            : AppMotion.morphContainerCurve.transform(v);

        final Rect rect = Rect.lerp(origin.rect, full, t)!;
        final double radius = lerpDouble(origin.radius, 0, _cornerCollapse(v))!;
        final double pageOpacity =
            reversing ? _openOpacityReverse(v) : _openOpacityForward(v);
        final double scrim = _scrimAlpha(t);

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              key: scrimKey,
              color: scrimColor.withValues(alpha: scrimColor.a * scrim),
            ),
            Positioned.fromRect(
              rect: rect,
              child: Material(
                color: surface,
                // Flat throughout: the reference tweens closedElevation →
                // openElevation and the budget app passes 0 for both, so a
                // shadow appearing mid-flight is ours, not the effect's.
                elevation: 0,
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: Clip.antiAlias,
                animationDuration: Duration.zero,
                // Taps landing mid-flight would hit whatever happens to be
                // under the cursor in a page that is still moving.
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      // The tapped card, scaled to the box's current width so
                      // it grows with it, dissolving as it goes — see
                      // [_closedOpacity] for why it is not held opaque.
                      if (closedChild != null)
                        Opacity(
                          // Flutter skips the saveLayer at 0 and 1, so this is
                          // free outside the actual fade.
                          opacity: _closedOpacity(v),
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: origin.rect.width,
                              height: origin.rect.height,
                              // Rasterised once, then only re-composited as the
                              // scale changes — without this the card repaints
                              // every frame of the flight.
                              child: RepaintBoundary(child: closedChild),
                            ),
                          ),
                        ),
                      // The page laid out at its final size and *scaled* into
                      // the box, so its content morphs along with the corners.
                      // Rendering it full-size behind a growing clip instead
                      // reads as a wipe: nothing about the page moves.
                      FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: screen.width,
                          height: screen.height,
                          // Flutter skips the saveLayer at 0 and 1, so this
                          // only costs one during the actual cross-fade.
                          child: Opacity(
                            opacity: pageOpacity,
                            // The single biggest frame-time win here: a whole
                            // screen's worth of widgets being re-rasterised on
                            // every frame is what a scaled page otherwise costs.
                            child: RepaintBoundary(child: child),
                          ),
                        ),
                      ),
                    ],
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
