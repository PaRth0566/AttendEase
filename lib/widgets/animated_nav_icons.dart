import 'dart:ui' show PointMode, lerpDouble;

import 'package:flutter/material.dart';

/// The three bottom-nav icons, hand-ported from SVG to [CustomPainter].
///
/// Named `animated_nav_icons` rather than `animated_icons` because Flutter's
/// own `AnimatedIcon`/`AnimatedIcons` come in with `material.dart`, which every
/// consumer of this file already imports.
///
/// ## How they play
///
/// Each icon plays its cycle exactly once, when its tab *becomes* the selected
/// one — not on a loop, and not on deselection. A persistent bar is the wrong
/// place for perpetual motion, and the single play carries a meaning the loop
/// does not: you just arrived here.
///
/// Selection is passed in rather than observed, because these icons cannot see
/// it. [GlassTabBar] renders two complete rows of tabs — one drawn entirely
/// unselected, one drawn entirely selected and clipped to the travelling pill
/// (`tab_bar_bottom_layout.dart`). Neither row's icons ever witness a change of
/// state, so the owning screen has to tell both copies at once. Doing it that
/// way also keeps them frame-synced: both start on the same [setState].
///
/// Selection alone cannot drive the play, for two reasons the [epoch] handles
/// together. The icon must replay when you tap the tab you are already on,
/// where `active` never changes; and it must play when the package mounts its
/// filled copy straight into the active state, where there is no `false→true`
/// edge to see. Both are covered by the host bumping `epoch` on every
/// activation and the icon playing any epoch it has not yet played. The counter
/// is passed down rather than read from a tap handler here, because the bar's
/// own `TabIndicator` owns the whole tab's gesture and a nested
/// [GestureDetector] would have to beat it in the arena to see the pointer.
///
/// ## Outline and filled
///
/// [filled] is a separate axis from [active], and it maps onto the bar's two
/// rows rather than onto selection: the unselected row is handed the outline
/// variant and the pill-masked row the filled one, which is what `activeIcon`
/// is for. The fill therefore arrives exactly as the pill sweeps over the icon,
/// with no state of its own to keep in sync.
///
/// "Filled" here is a *tint*, not a silhouette: the border stays at full
/// opacity and the interior takes a [_fillOpacity] wash of the same colour, so
/// the glass behind the bar still reads through the shape. Every stroke the
/// outline variant draws is drawn in the filled one too, at the same weight —
/// the fill is added underneath rather than replacing anything. That is also
/// what keeps the icon's outer edge in exactly the same place across the swap,
/// so it does not appear to shrink as the pill crosses it.
///
/// ## Stroke width
///
/// [strokeWidth] on all three is in **logical pixels of the rendered icon**,
/// not each icon's own design space. The three source SVGs have three different
/// viewBoxes — 32, 24 and 430 — so one design-space number would paint three
/// different visible weights and the bar would stop reading as one icon set.
/// Each painter converts to its own space with `strokeWidth / scale`.

// ---------------------------------------------------------------------------
// Shared timing
// ---------------------------------------------------------------------------

/// Interior tint of a filled icon, as a fraction of the icon's own colour.
///
/// One token for all three so the active tabs match. Low enough that the bar's
/// glass still shows through and the border stays the dominant edge; high
/// enough to read as a state change at 26px. Tune here, not per icon.
const double _fillOpacity = 0.22;

/// Samples a keyframe track: [values] at [times], eased by the [curves] between
/// them (one curve per segment, so `curves.length == times.length - 1`).
///
/// This is the SVG `keyTimes` / `values` / `keySplines` triple, evaluated at
/// [t] in 0…1.
double _interp(
  List<double> times,
  List<double> values,
  List<Cubic> curves,
  double t,
) {
  if (t <= times.first) return values.first;
  if (t >= times.last) return values.last;
  for (int i = 0; i < times.length - 1; i++) {
    if (t > times[i + 1]) continue;
    final double span = times[i + 1] - times[i];
    final double local = span <= 0 ? 1.0 : (t - times[i]) / span;
    return lerpDouble(values[i], values[i + 1], curves[i].transform(local))!;
  }
  return values.last;
}

/// Reports every play and every disposal, as `'play <label>'` /
/// `'dispose …'`, so tests can assert on *which* icon animated.
///
/// There is no other way to observe it: the animation is painted, not built,
/// so nothing about a play shows up in the widget tree for a finder to match.
/// `test/nav_icon_play_test.dart` is the regression that needs this.
@visibleForTesting
void Function(String event)? debugNavIcon;

/// Stable identities for one bar's six icon copies (three tabs ×
/// outline/filled), so each copy keeps its [State] — and therefore its running
/// animation — when the bar rebuilds it somewhere else in the tree.
///
/// This is what stops an arrival animating twice. `TabIndicator` chooses its
/// entire render tree with a `switch` on `maskingQuality`: the clip-free `.off`
/// path while the pill travels, the dual-layer `.high` path once it parks. The
/// two put the icon rows at different depths under different parents, so the
/// swap as the pill settles reconciles as a tear-down and a fresh build rather
/// than an update. The rebuilt copy is born active at an epoch it has no memory
/// of playing, the born-active rule in [_NavIconHost] fires exactly as
/// designed, and the cycle already running restarts from zero — one arrival,
/// two visible plays. Dashboard→Profile shows it most plainly because that trip
/// crosses two tabs, so the pill is still travelling well into the 1100 ms
/// cycle and the restart lands in open view.
///
/// A [GlobalKey] turns that tear-down into a reparent. The swap happens within
/// one build, so Flutter finds the deactivated element by key and moves it,
/// [State] and [AnimationController] intact: `didUpdateWidget` sees an epoch it
/// has already played, declines to replay, and the single cycle carries on
/// uninterrupted across the swap. Merely suppressing the second play would
/// truncate that cycle instead, since the flip lands partway through it.
///
/// Owned per bar rather than globally, because a [GlobalKey] carries State
/// wherever it goes: one process-wide set would hand a fresh bar the last one's
/// half-played animations, and any two bars alive at once would collide on the
/// same keys.
class NavIconKeys {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// The key for one icon copy — `slot` being its `debugLabel`, e.g.
  /// `'prof/FILL'`. Created on first use and kept for this bar's life.
  ///
  /// Each key is used exactly once per frame: the bar draws the outline row
  /// from `GlassTab.icon` and the pill-masked row from `GlassTab.activeIcon`,
  /// and `filled` differs between them, so the two never collide.
  GlobalKey operator [](String slot) =>
      _keys.putIfAbsent(slot, () => GlobalKey(debugLabel: slot));
}

/// Owns the controller and the play-once rule for all three icons; the public
/// widgets are thin wrappers that supply a painter and a duration.
class _NavIconHost extends StatefulWidget {
  const _NavIconHost({
    super.key,
    required this.duration,
    required this.size,
    required this.active,
    required this.epoch,
    required this.painterBuilder,
    this.debugLabel = '',
  });

  final String debugLabel;
  final Duration duration;
  final double size;

  /// Whether this is the currently-arrived tab.
  final bool active;

  /// A counter the host bumps every time a tab becomes the arrived one (and
  /// again when the arrived tab is re-tapped). The icon plays whenever it is
  /// [active] and carries an [epoch] it has not yet played.
  ///
  /// This is what makes the play independent of *when* the widget is mounted.
  /// The package renders the selected row's off-pill tabs as `SizedBox.shrink`,
  /// so a tab's filled icon is frequently torn down and rebuilt as the pill
  /// travels — and on a real device that rebuild can coincide, in a single
  /// coalesced frame, with the tab becoming active. Watching for a live
  /// `active` false→true edge missed exactly that case: the icon was born
  /// active, so there was no edge, so it sat still while its hidden outline
  /// twin (which is never torn down) animated under the pill. Comparing epochs
  /// instead means a born-active icon still knows it owes a play.
  ///
  /// Epoch 0 is the sentinel for "no navigation yet": the tab selected at cold
  /// start is born active at epoch 0 and stays quiet, as before.
  final int epoch;

  final CustomPainter Function(Animation<double> progress) painterBuilder;

  @override
  State<_NavIconHost> createState() => _NavIconHostState();
}

class _NavIconHostState extends State<_NavIconHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// The epoch whose play this icon has already run (or claimed as not owed).
  /// Null means it has played nothing yet.
  ///
  /// Kept alive across the bar's masking-quality swap by the [GlobalKey] each
  /// icon carries — see [NavIconKeys]. Without that the swap discarded this
  /// field mid-cycle and the born-active rule replayed the same arrival.
  int? _playedEpoch;

  /// Claims [epoch], returning whether the play is owed.
  bool _claim(int epoch) {
    if (_playedEpoch == epoch) return false;
    _playedEpoch = epoch;
    return true;
  }

  @override
  void initState() {
    super.initState();
    // Born active — either the cold-start tab, or a copy the bar mounted
    // straight into the selected state mid-navigation. The epoch tells the two
    // apart: 0 is cold start (claim it, stay quiet), and anything else is a
    // real arrival whose play the missing false→true edge would otherwise have
    // swallowed.
    //
    // This runs only for a genuinely new icon. The rebuild that the bar's
    // masking swap performs at the end of every trip is a reparent, because of
    // the [GlobalKey] in [NavIconKeys] — the State comes through it intact and
    // `didUpdateWidget` handles that frame instead, so an arrival already
    // playing is not born again here and does not restart.
    if (widget.active) {
      _claim(widget.epoch);
      if (widget.epoch != 0) {
        // MediaQuery is not readable in initState; defer past first build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _play();
        });
      }
    }
  }

  @override
  void didUpdateWidget(_NavIconHost old) {
    super.didUpdateWidget(old);
    // Runs on every frame of a swipe — the root screen mirrors the page
    // position into State to track the pill — so this must fire only on a real
    // change of state, never on a bare rebuild.
    if (widget.active && widget.epoch != 0 && _claim(widget.epoch)) {
      _play();
    } else if (old.active && !widget.active) {
      // Leaving a tab parks its icon. Deselection used to be ignored entirely,
      // which left the controller running: the outline copy of a tab is
      // visible the whole time, so an icon you had just left went on animating
      // for up to another two seconds from a tab you were no longer on.
      debugNavIcon?.call('stop ${widget.debugLabel}');
      _playedEpoch = null;
      _c.reset();
    }
  }

  @override
  void dispose() {
    debugNavIcon?.call(
      'dispose ${widget.debugLabel} '
      'value=${_c.value.toStringAsFixed(2)}',
    );
    _c.dispose();
    super.dispose();
  }

  void _play() {
    debugNavIcon?.call('play ${widget.debugLabel}');
    // Reduced motion parks the icon on its resting pose rather than playing it
    // instantly, which would be a one-frame flicker to no purpose. Same
    // choke-point idea as AppMotion.duration.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 0;
      return;
    }
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: widget.painterBuilder(_c),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard — four panels trading heights
// ---------------------------------------------------------------------------

class DashboardMorphIcon extends StatelessWidget {
  const DashboardMorphIcon({
    super.key,
    this.size,
    this.color,
    this.accentColor,
    this.strokeWidth = 1.75,
    this.filled = false,
    this.active = false,
    this.epoch = 0,
    this.keys,
  });

  /// The owning bar's [NavIconKeys]. Pass it inside a [GlassTabBar], where the
  /// masking swap rebuilds the icons; omit it anywhere the icon is not moved
  /// between parents and there is nothing to preserve.
  final NavIconKeys? keys;

  /// Defaults to the ambient [IconTheme]'s size — which inside the bar is
  /// `GlassNavTheme.iconSize`.
  final double? size;

  /// Defaults to the ambient [IconTheme]'s colour, which is how the bar hands
  /// each row its selected/unselected colour.
  final Color? color;

  /// Bottom-right panel. Falls back to [color] (the SVG's
  /// `var(--icon-accent, currentColor)`).
  final Color? accentColor;

  /// Logical pixels. See the file header.
  final double strokeWidth;

  /// Tints each panel's interior. See the file header.
  final bool filled;

  final bool active;

  /// Bumped by the host on each activation. See the file header.
  final int epoch;

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final Color resolved = color ?? iconTheme.color ?? const Color(0xFF000000);
    final String slot = filled ? 'dash/FILL' : 'dash/rest';
    return _NavIconHost(
      // Keeps this copy's animation alive across the bar's masking swap, which
      // otherwise rebuilds it mid-cycle and replays the arrival. See
      // [NavIconKeys].
      key: keys?[slot],
      debugLabel: slot,
      duration: const Duration(milliseconds: 1100),
      size: size ?? iconTheme.size ?? 24,
      active: active,
      epoch: epoch,
      painterBuilder: (progress) => _DashboardMorphPainter(
        progress: progress,
        color: resolved,
        accentColor: accentColor ?? resolved,
        strokeWidth: strokeWidth,
        filled: filled,
      ),
    );
  }
}

class _DashboardMorphPainter extends CustomPainter {
  _DashboardMorphPainter({
    required this.progress,
    required this.color,
    required this.accentColor,
    required this.strokeWidth,
    required this.filled,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final Color accentColor;
  final double strokeWidth;
  final bool filled;

  // Shared timeline: hold, morph, hold, morph back.
  static const List<double> _times = [0, 0.15, 0.5, 0.65, 1];
  static const List<Cubic> _curves = [
    Cubic(0, 0, 1, 1), // linear (values held, so this never shows)
    Cubic(0.65, 0, 0.35, 1), // ease-in-out
    Cubic(0, 0, 1, 1),
    Cubic(0.65, 0, 0.35, 1),
  ];

  // Panel width, and the two column x-positions. Narrower than the original 9
  // with the columns pushed apart (x 6/18 rather than 6/17) so the gap between
  // them is 4 units instead of 2 — the boxes were reading as cramped. The icon
  // still sits inside the same 6…26 bounds, so its footprint is unchanged.
  static const double _panelW = 8;
  static const double _colLeft = 6;
  static const double _colRight = 18;

  // Two shapes only: "tall" panels shrink while "short" panels grow. Slightly
  // shorter than the original 12/6 to open a 3.5-unit vertical gap (was 2)
  // between the rows while keeping the 6…26 bounds and the 2:1 tall:short feel.
  static const List<double> _tall = [11, 11, 5.5, 5.5, 11];
  static const List<double> _short = [5.5, 5.5, 11, 11, 5.5];

  // Bottom-row panels also slide, since they're anchored to their base edge at
  // y=26. A short panel's top sits at 20.5, a tall one's at 15.
  static const List<double> _risingY = [
    20.5,
    20.5,
    15,
    15,
    20.5,
  ]; // grows upward
  static const List<double> _fallingY = [
    15,
    15,
    20.5,
    20.5,
    15,
  ]; // shrinks downward

  static const double _radius = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.value;
    final double scale = size.width / 32.0;

    canvas.save();
    canvas.scale(scale);

    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = c;
    Paint fill(Color c) => Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = c.withValues(alpha: c.a * _fillOpacity);

    final Paint paint = stroke(color);
    final Paint accent = stroke(accentColor);
    final Paint? paintFill = filled ? fill(color) : null;
    final Paint? accentFill = filled ? fill(accentColor) : null;

    // The interior wash goes down first and the border over it at full
    // opacity, so the panel edges land in exactly the same place in both
    // variants.
    void panel(double x, double y, double h, Paint edge, Paint? interior) {
      final RRect rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, _panelW, h),
        const Radius.circular(_radius),
      );
      if (interior != null) canvas.drawRRect(rect, interior);
      canvas.drawRRect(rect, edge);
    }

    final double tall = _interp(_times, _tall, _curves, t);
    final double short = _interp(_times, _short, _curves, t);

    panel(_colLeft, 6, tall, paint, paintFill); // top-left
    panel(_colRight, 6, short, paint, paintFill); // top-right
    panel(
      _colLeft,
      _interp(_times, _risingY, _curves, t),
      short,
      paint,
      paintFill,
    ); // bottom-left
    panel(
      _colRight,
      _interp(_times, _fallingY, _curves, t),
      tall,
      accent,
      accentFill,
    ); // bottom-right

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DashboardMorphPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.accentColor != accentColor ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}

// ---------------------------------------------------------------------------
// Calendar — a grid of days blinking in sequence
// ---------------------------------------------------------------------------

class CalendarDaysIcon extends StatelessWidget {
  const CalendarDaysIcon({
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 1.75,
    this.filled = false,
    this.active = false,
    this.epoch = 0,
    this.keys,
  });

  final double? size;
  final Color? color;

  /// The owning bar's [NavIconKeys]. See [DashboardMorphIcon.keys].
  final NavIconKeys? keys;

  /// Logical pixels. See the file header.
  final double strokeWidth;

  /// Tints the body's interior. The header rule and the day dots are drawn
  /// identically either way. See the file header.
  final bool filled;

  final bool active;

  /// Bumped by the host on each activation. See the file header.
  final int epoch;

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    return _NavIconHost(
      // The blink sweep staggers a dip across twelve dots; its timing lives in
      // the painter's _span/_blink/_stagger, scaled so the last dot lands just
      // inside this cycle. The SVG's original 2.4s cycle was a *loop* period —
      // the tail was idle time to space out repeats, which a single play has
      // nothing to space out.
      key: keys?[filled ? 'cal/FILL' : 'cal/rest'],
      debugLabel: filled ? 'cal/FILL' : 'cal/rest',
      duration: const Duration(milliseconds: 1100),
      size: size ?? iconTheme.size ?? 24,
      active: active,
      epoch: epoch,
      painterBuilder: (progress) => _CalendarDaysPainter(
        progress: progress,
        color: color ?? iconTheme.color ?? const Color(0xFF000000),
        strokeWidth: strokeWidth,
        filled: filled,
      ),
    );
  }
}

class _CalendarDaysPainter extends CustomPainter {
  _CalendarDaysPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.filled,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;
  final bool filled;

  /// Seconds of blink timeline the controller spans. Matches the host duration
  /// (1100ms). Blink and stagger are scaled to fit: the last dot starts at
  /// 11×_stagger = 0.756s and finishes its dip at 1.031s, just inside _span.
  static const double _span = 1.1;
  static const double _blink = 0.275; // one dot's dip and recovery
  static const double _stagger = 0.06875; // between neighbours
  static const double _dimmest = 0.3;

  /// Reading order, which is what makes the sweep look like a sweep.
  static const List<Offset> _dots = [
    Offset(12, 12.75),
    Offset(14.25, 12.75),
    Offset(16.5, 12.75),
    Offset(7.5, 15),
    Offset(9.75, 15),
    Offset(12, 15),
    Offset(14.25, 15),
    Offset(16.5, 15),
    Offset(7.5, 17.25),
    Offset(9.75, 17.25),
    Offset(12, 17.25),
    Offset(14.25, 17.25),
  ];

  /// The CSS `animation-delay` becomes a phase offset on shared progress: a
  /// dot whose window has not opened yet, or has already closed, sits at full
  /// opacity. Linear, as the SVG's keyframes are.
  static double _opacityAt(double seconds, int index) {
    final double local = seconds - index * _stagger;
    if (local <= 0 || local >= _blink) return 1;
    final double half = _blink / 2;
    return local < half
        ? lerpDouble(1, _dimmest, local / half)!
        : lerpDouble(_dimmest, 1, (local - half) / half)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double seconds = progress.value * _span;
    final double scale = size.width / 24.0;

    canvas.save();
    canvas.scale(scale);

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;

    // The two hanger ticks above the body.
    canvas.drawLine(const Offset(6.75, 3), const Offset(6.75, 5.25), stroke);
    canvas.drawLine(const Offset(17.25, 3), const Offset(17.25, 5.25), stroke);

    // Body. The SVG spells this as three open subpaths that share edges; the
    // outer two of them are exactly this rounded rectangle.
    final RRect body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(3, 5.25, 21, 21),
      const Radius.circular(2.25),
    );
    if (filled) {
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = color.withValues(alpha: color.a * _fillOpacity),
      );
    }
    canvas.drawRRect(body, stroke);

    // The header rule, with its corners curving down into the body's sides.
    // Left open at the bottom on purpose — the rest of its outline is the
    // rectangle above, and stroking it twice would only thicken those edges.
    final Path header = Path()
      ..moveTo(3, 18.75)
      ..lineTo(3, 11.25)
      ..arcToPoint(
        const Offset(5.25, 9),
        radius: const Radius.circular(2.25),
        clockwise: true,
      )
      ..lineTo(18.75, 9)
      ..arcToPoint(
        const Offset(21, 11.25),
        radius: const Radius.circular(2.25),
        clockwise: true,
      )
      ..lineTo(21, 18.75);
    canvas.drawPath(header, stroke);

    // Dots. The SVG draws these as zero-length round-capped paths, which is a
    // point with a round cap — so that is what they are here too, and their
    // diameter tracks the stroke weight.
    //
    // Drawn identically in both variants, on top of the wash rather than
    // punched out of it: against a 22% interior a hole has almost no contrast,
    // and the blink — the whole point of this icon — would vanish with it.
    final Paint dot = Paint()
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (int i = 0; i < _dots.length; i++) {
      dot.color = color.withValues(alpha: color.a * _opacityAt(seconds, i));
      canvas.drawPoints(PointMode.points, [_dots[i]], dot);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CalendarDaysPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}

// ---------------------------------------------------------------------------
// Profile — an avatar peeking around
// ---------------------------------------------------------------------------

class AvatarLookingAroundIcon extends StatelessWidget {
  const AvatarLookingAroundIcon({
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 1.75,
    this.filled = false,
    this.active = false,
    this.epoch = 0,
    this.keys,
  });

  final double? size;
  final Color? color;

  /// The owning bar's [NavIconKeys]. See [DashboardMorphIcon.keys].
  final NavIconKeys? keys;

  /// Tints the head and shoulders. They never overlap at any point in the
  /// cycle — the head's lowest reach is y=214.6 and the shoulders top out at
  /// 235 — so two translucent washes never stack into a darker seam.
  final bool filled;

  /// Logical pixels. See the file header — this icon is the reason that
  /// convention exists. Its design space is 430 units wide, so the SVG's
  /// stroke-width of 12 would paint at 0.6px inside a 22px bar: a grey haze
  /// next to two 1.75px icons.
  final double strokeWidth;

  final bool active;

  /// Bumped by the host on each activation. See the file header.
  final int epoch;

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    return _NavIconHost(
      key: keys?[filled ? 'prof/FILL' : 'prof/rest'],
      debugLabel: filled ? 'prof/FILL' : 'prof/rest',
      duration: const Duration(milliseconds: 1100),
      size: size ?? iconTheme.size ?? 24,
      active: active,
      epoch: epoch,
      painterBuilder: (progress) => _AvatarLookingAroundPainter(
        progress: progress,
        color: color ?? iconTheme.color ?? const Color(0xFF000000),
        strokeWidth: strokeWidth,
        filled: filled,
      ),
    );
  }
}

class _AvatarLookingAroundPainter extends CustomPainter {
  _AvatarLookingAroundPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.filled,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;
  final bool filled;

  // ── Body ────────────────────────────────────────────────────
  //
  // Three poses, morphed between. They are stored as flat number lists rather
  // than Paths because SVG path interpolation is only defined when the command
  // structure matches — and here it does, exactly: M, C, L, L, L, C, Z. So the
  // morph is a straight lerp of twenty coordinates.
  static const List<double> _bodyRest = [
    170, 235, //
    106.487, 235, 55, 286.487, 55, 350, //
    55, 375, //
    375, 375, //
    375, 350, //
    375, 286.487, 323.513, 235, 260, 235,
  ];
  static const List<double> _bodyRaised = [
    169.709, 197.523, //
    106.196, 197.523, 54.709, 249.01, 54.709, 312.523, //
    55, 361.85, //
    375, 361.85, //
    374.709, 312.523, //
    374.709, 249.01, 323.222, 197.523, 259.709, 197.523,
  ];
  static const List<double> _bodySunk = [
    170, 244.862, //
    106.487, 244.862, 55, 296.349, 55, 359.862, //
    55, 375, //
    375, 375, //
    375, 359.862, //
    375, 296.349, 323.513, 244.862, 260, 244.862,
  ];

  static const List<double> _bodyTimes = [
    0, 0.10833, 0.19167, 0.26667, 0.36667, //
    0.43485, 0.51667, 0.68288, 0.80181, 0.91081, 1,
  ];
  static const List<List<double>> _bodyPoses = [
    _bodyRest,
    _bodyRaised,
    _bodySunk,
    _bodyRest,
    _bodyRest,
    _bodySunk,
    _bodyRest,
    _bodyRest,
    _bodyRaised,
    _bodySunk,
    _bodyRest,
  ];
  static const Cubic _ease = Cubic(0.333, 0, 0.667, 1);
  static const List<Cubic> _bodyCurves = [
    Cubic(0.333, 0, 0.138, 1),
    _ease,
    _ease,
    _ease,
    _ease,
    _ease,
    _ease,
    Cubic(0.333, 0, 0.086, 1),
    _ease,
    _ease,
  ];

  // ── Head ────────────────────────────────────────────────────
  //
  // Peeks up, ducks left, slides right, then pops back up.
  static const double _headRadius = 75;
  static const List<double> _headTimes = [
    0,
    0.1,
    0.18333,
    0.36722,
    0.51667,
    0.63333,
    0.80181,
    0.90292,
    1,
  ];
  static const List<double> _headX = [
    214.927,
    214.927,
    158.416,
    158.416,
    254.896,
    254.896,
    215.254,
    214.927,
    214.927,
  ];
  static const List<double> _headY = [
    124.992,
    81.965,
    139.644,
    139.644,
    138.773,
    138.773,
    85.152,
    138.932,
    124.992,
  ];
  static const List<Cubic> _headCurves = [
    Cubic(0.333, 0, 0.094, 1),
    _ease,
    _ease,
    _ease,
    Cubic(0.333, 0.333, 0.667, 0.667),
    Cubic(0.333, 0, 0.257, 1),
    _ease,
    _ease,
  ];

  // ── Squash ──────────────────────────────────────────────────
  //
  // The whole figure compresses a little as the head lands, pivoting on its
  // base so the feet stay planted.
  static const Offset _pivot = Offset(215, 375);
  static const List<double> _squashTimes = [0, 0.36667, 0.43485, 0.51667, 1];
  static const List<double> _squashX = [1, 1, 1.03, 1, 1];
  static const List<double> _squashY = [1, 1, 0.97, 1, 1];
  static const List<Cubic> _squashCurves = [_ease, _ease, _ease, _ease];

  static Path _bodyPath(double t) {
    final List<double> n = List<double>.generate(
      _bodyRest.length,
      (i) => _interp(_bodyTimes, _bodyTracks[i], _bodyCurves, t),
    );
    return Path()
      ..moveTo(n[0], n[1])
      ..cubicTo(n[2], n[3], n[4], n[5], n[6], n[7])
      ..lineTo(n[8], n[9])
      ..lineTo(n[10], n[11])
      ..lineTo(n[12], n[13])
      ..cubicTo(n[14], n[15], n[16], n[17], n[18], n[19])
      ..close();
  }

  /// The poses transposed into one keyframe track per coordinate, built once.
  /// [_interp] wants a track, and rebuilding twenty of them per frame — on an
  /// icon that repaints every frame it plays — is pure garbage.
  static final List<List<double>> _bodyTracks = List<List<double>>.generate(
    _bodyRest.length,
    (i) => [for (final List<double> pose in _bodyPoses) pose[i]],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.value;
    final double scale = size.width / 430.0;

    canvas.save();
    canvas.scale(scale);

    canvas.translate(_pivot.dx, _pivot.dy);
    canvas.scale(
      _interp(_squashTimes, _squashX, _squashCurves, t),
      _interp(_squashTimes, _squashY, _squashCurves, t),
    );
    canvas.translate(-_pivot.dx, -_pivot.dy);

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      // Divided by the squash too, so a compressed figure does not also thin
      // out — the SVG's stroke is likewise unaffected by its own transform
      // only because the squash is small; here we keep the weight exact.
      ..strokeWidth = strokeWidth / scale
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;

    final Paint? interior = filled
        ? (Paint()
            ..style = PaintingStyle.fill
            ..isAntiAlias = true
            ..color = color.withValues(alpha: color.a * _fillOpacity))
        : null;

    final Path body = _bodyPath(t);
    final Offset head = Offset(
      _interp(_headTimes, _headX, _headCurves, t),
      _interp(_headTimes, _headY, _headCurves, t),
    );

    // Shoulders. Butt caps, as the SVG has it: the path is closed, so there are
    // no free ends for a cap to round off anyway.
    if (interior != null) canvas.drawPath(body, interior);
    canvas.drawPath(body, paint..strokeCap = StrokeCap.butt);

    if (interior != null) canvas.drawCircle(head, _headRadius, interior);
    canvas.drawCircle(head, _headRadius, paint..strokeCap = StrokeCap.round);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AvatarLookingAroundPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}
