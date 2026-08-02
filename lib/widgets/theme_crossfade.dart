import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Wraps the whole app so a theme change reads as one smooth crossfade instead
/// of an abrupt flip.
///
/// ## Why a snapshot crossfade and not `AnimatedTheme`
///
/// `MaterialApp` already wraps its child in an `AnimatedTheme`, so the
/// *standard* `ThemeData` colours lerp on their own. That is exactly why the
/// old toggle looked broken rather than merely unanimated: `ThemeData.lerp`
/// switches the discrete `brightness` field at the animation's midpoint, and a
/// large part of this app does not read the lerp-able colours at all — it
/// branches on `Theme.of(context).brightness` (the glass nav bar via
/// `GlassNavTheme.settings`, the `AppColors` theme extension, the per-screen
/// `isDark ? … : …` choices). Those all snap at t=0.5 while the scaffold
/// background eases, which is the flash: half the UI jumps a beat ahead of the
/// other half.
///
/// No per-property tween can unify that, because the two halves animate on
/// different mechanisms. Fading *pixels* can: we photograph the outgoing theme,
/// flip the real theme underneath instantly, and dissolve the photo away over a
/// single duration/curve. Everything under the photo — background, text, icons,
/// cards, the glass bar — is revealed on the same timeline, so nothing can lead
/// or lag. It is the strategy the `animated_theme_switcher` package uses,
/// implemented in-repo so it drives the app's existing `themeProvider` and
/// `MaterialApp.router` directly rather than bringing a second theme-owner.
///
/// ## Usage
///
/// Mount it once, inside `MaterialApp.builder`, wrapping `child`. Trigger a
/// themed change through [ThemeCrossfadeController.crossfade] instead of poking
/// the theme source directly:
///
/// ```dart
/// ThemeCrossfade.of(context).crossfade(
///   () => themeProvider.setThemeMode(ThemeMode.dark),
/// );
/// ```
///
/// The callback is what actually mutates the theme; the widget only sequences
/// the capture, the swap and the fade around it.
class ThemeCrossfade extends StatefulWidget {
  const ThemeCrossfade({
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOutCubic,
    super.key,
  });

  final Widget child;

  /// How long the outgoing snapshot takes to dissolve. 300 ms provides a
  /// smooth crossfade.
  final Duration duration;

  /// Applied to the fade. Ease-in-out cubic so the dissolve accelerates smoothly
  /// off the old theme and decelerates onto the new one.
  final Curve curve;

  /// The nearest controller above [context]. Throws if none is mounted.
  static ThemeCrossfadeController of(BuildContext context) {
    final state = context.findAncestorStateOfType<_ThemeCrossfadeState>();
    assert(
      state != null,
      'ThemeCrossfade.of() called with a context that has no ThemeCrossfade '
      'ancestor. Mount ThemeCrossfade inside MaterialApp.builder.',
    );
    return state!;
  }

  /// Safe accessor returning null if ThemeCrossfade is not mounted above [context].
  static ThemeCrossfadeController? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<_ThemeCrossfadeState>();
  }

  @override
  State<ThemeCrossfade> createState() => _ThemeCrossfadeState();
}

/// The surface [ThemeCrossfade.of] hands back — just the trigger, so callers
/// cannot reach into the widget's animation state.
abstract class ThemeCrossfadeController {
  /// Photographs the current UI, runs [applyThemeChange] to flip the theme
  /// underneath, then dissolves the photo away.
  ///
  /// Optionally pass [maskRect] and [maskBorderRadius] to cut out a hole over
  /// interactive toggle widgets so they can animate live alongside the theme dissolve.
  Future<void> crossfade(
    VoidCallback applyThemeChange, {
    VoidCallback? onMidpoint,
    Rect? maskRect,
    BorderRadius? maskBorderRadius,
  });
}

class _ThemeCrossfadeState extends State<ThemeCrossfade>
    with SingleTickerProviderStateMixin
    implements ThemeCrossfadeController {
  /// Wraps the live child so [RenderRepaintBoundary.toImage] has an isolated
  /// layer to photograph.
  final GlobalKey _boundaryKey = GlobalKey();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// The outgoing frame, held only for the length of one fade. Null at rest.
  ui.Image? _snapshot;
  Rect? _maskRect;
  BorderRadius? _maskBorderRadius;

  /// Guards against a second toggle landing mid-fade.
  bool _capturing = false;

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Future<void> crossfade(
    VoidCallback applyThemeChange, {
    VoidCallback? onMidpoint,
    Rect? maskRect,
    BorderRadius? maskBorderRadius,
  }) async {
    if (_capturing || _snapshot != null) {
      applyThemeChange();
      onMidpoint?.call();
      return;
    }
    _capturing = true;
    _maskRect = maskRect;
    _maskBorderRadius = maskBorderRadius;

    final ui.Image? image = await _capture();
    if (!mounted) {
      image?.dispose();
      _capturing = false;
      return;
    }

    if (image == null) {
      applyThemeChange();
      onMidpoint?.call();
      _capturing = false;
      return;
    }

    setState(() => _snapshot = image);
    applyThemeChange();
    onMidpoint?.call();

    _capturing = false;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      _disposeSnapshot();
      return;
    }

    try {
      await _controller.forward(from: 0);
    } on TickerCanceled {
      // Teardown below runs
    }
    if (mounted) {
      _disposeSnapshot();
    } else {
      _snapshot?.dispose();
      _snapshot = null;
    }
    _controller.reset();
  }

  Future<ui.Image?> _capture() async {
    final context = _boundaryKey.currentContext;
    final object = context?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final double pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context!) ?? 1;
    try {
      return await object.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  void _disposeSnapshot() {
    final old = _snapshot;
    setState(() {
      _snapshot = null;
      _maskRect = null;
      _maskBorderRadius = null;
    });
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (_snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final double t = widget.curve.transform(_controller.value);
                  final rawImage = RawImage(
                    image: _snapshot,
                    fit: BoxFit.fill,
                    scale: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
                  );
                  final Widget imageWidget = _maskRect != null
                      ? ClipPath(
                          clipper: _HoleClipper(
                            _maskRect!,
                            _maskBorderRadius ?? BorderRadius.circular(20),
                          ),
                          child: rawImage,
                        )
                      : rawImage;

                  return Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: imageWidget,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.rect, this.borderRadius);

  final Rect rect;
  final BorderRadius borderRadius;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(borderRadius.toRRect(rect));
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(covariant _HoleClipper oldClipper) {
    return oldClipper.rect != rect || oldClipper.borderRadius != borderRadius;
  }
}
