# Vendored `liquid_glass_widgets`

Upstream: `liquid_glass_widgets` **0.18.4** from pub.dev, copied verbatim except
for the patch below. Wired in by `dependency_overrides` in the root
`pubspec.yaml`; the `^0.18.4` entry under `dependencies` is what the override
replaces, so both move together on an upgrade.

Only `lib/`, `shaders/`, `pubspec.yaml`, `analysis_options.yaml` and the licence
and changelog are vendored — the upstream `example/`, `scripts/` and
`test_clip.dart` are not needed to build against it.

## The patch

The nav bar's selection pill deformed the wrong way while travelling.
`DraggableIndicatorPhysics.buildJellyTransform` squashes the indicator **along**
its direction of motion and stretches it across — the inverse of conventional
squash-and-stretch, where a moving object elongates along its path. For a pill
crossing a tab bar the difference is not subtle: the squash coefficient is 0.5
against the stretch's 0.3, and on AttendEase's full-width Dashboard→Profile trip
the spring saturates the distortion clamp, so the pill necked down to 0.6× width
and sprang back on arrival. Measured off a screen recording, 181 px at rest
against ~95 px at peak. That reads as the pill leaving and reappearing rather
than sliding.

The two constants that drive it (`maxDistortion: 0.8`, `velocityScale: 10`) are
literals at the call sites with no parameter on `GlassTabBar` reaching them, so
there is no way to change this from outside the package.

Every edit is tagged `AttendEase patch` — `grep -rn "AttendEase patch" lib/` finds
all of them. There are five, in three files:

| File | Change |
| --- | --- |
| `lib/utils/draggable_indicator_physics.dart` | Adds `stretchAlongMotion` to `buildJellyTransform`. Default `false` reproduces upstream exactly; `true` elongates by `1 + 0.3·d` along the path and takes the perpendicular scale as the reciprocal, so the shape holds its area. |
| `lib/widgets/shared/animated_glass_indicator.dart` | Adds a `stretchAlongMotion` field (default `false`) and forwards it to the transform. |
| `lib/widgets/surfaces/shared/tab_bar_bottom_internal.dart` | Passes `true` at four sites: the `JellyClipper` transform and all three `AnimatedGlassIndicator` constructions. |

Nothing else in the package changes behaviour, because the flag defaults to
`false` everywhere it is not passed — `GlassSlider`, `GlassSegmentedControl` and
the searchable bar are all untouched.

Area conservation is the part not to "simplify" later. Merely swapping
upstream's two coefficients was the first attempt: it put `-0.5` on the height,
which flattened a ~50 px pill to 30 px and left the icon inside it standing
proud at top and bottom — a stretched band rather than a moving pill.
`test/nav_pill_jelly_test.dart` pins both the direction and the area.

**The four sites in `tab_bar_bottom_internal.dart` must agree.** The transform is
applied both to the pill and, via `JellyClipper`, to the icon layer that is cut
out of it. If they disagree the icon window deforms differently from the pill it
is supposed to sit inside, and the selected icon clips against its own pill.

## The second patch — `alignmentOverride` (interactive tab slide)

`GlassTabBar` could only place the pill at a discrete tab index, so nothing
could drive it from a continuous page-scroll position. This adds an **additive**
`double? alignmentOverride` (in `[-1, 1]`) that, when non-null, wins over the
discrete `tabIndex` and lets `RootScreen`'s `PageController` move the pill frame
for frame with the sliding screens. Every existing call site keeps working
untouched because it defaults to `null`.

Tagged `AttendEase patch`. Four files, all additive:

| File | Change |
| --- | --- |
| `lib/widgets/surfaces/shared/tab_bar_drag_gesture_mixin.dart` | Adds abstract getter `double? get alignmentOverride => null;` and an early-return guard in `updateTabAlignIfNeeded` so a stale index cannot yank the pill mid-override. |
| `lib/widgets/surfaces/shared/tab_bar_bottom_internal.dart` | `TabIndicator` gains the `alignmentOverride` field; `TabIndicatorState` overrides the getter, feeds it as `targetAlignment`, and passes it as the `VelocitySpringBuilder` `value` with `active: … \|\| alignmentOverride != null`. The spring is **not** bypassed — it still computes the `velocity` the jelly stretch reads. |
| `lib/widgets/surfaces/shared/tab_bar_bottom_layout.dart` | Threads `alignmentOverride` from the layout to `TabIndicator`. |
| `lib/widgets/surfaces/glass_tab_bar.dart` | Threads `alignmentOverride` through `GlassTabBar.bottom` → `this._` → `TabBarBottomLayout`. `GlassTabBar.searchable` does not use it. |

### `alignmentOverride` vs. the bar's own drag gesture

The override as first written (`alignmentOverride ?? tabXAlign`) won
*unconditionally*, and `RootScreen` always supplies one — so the bar's built-in
drag gesture, which only ever writes `tabXAlign`, wrote into a value nothing
read. Dragging the pill along the bar did nothing visible; it snapped only at
release (via `notifyTabChanged`). `test/nav_pill_drag_test.dart` (in the app,
not the package) pins the fix.

`TabIndicatorState` now carries a `_dragOwnsPill` flag, set when a bar drag
starts *while an override is present*. While set, the pill is driven by
`tabXAlign` (finger) and the override is ignored; both `targetAlignment` and the
`VelocitySpringBuilder` `value` route through it. On release the flag lingers
through the settle and clears in `build` once the override has converged to the
released tab (`|override − tabXAlign| < 0.02`), so the page-follow resumes with
no snap-back. Consumers that pass no override never set the flag and keep the
plain `tabXAlign` path.

## Upgrading

1. Copy the new upstream version over this directory, keeping this file.
2. Re-apply the five edits; the table above locates them.
3. Check first whether upstream has exposed the jelly parameters — if it has,
   drop the fork, take the pub dependency back, and delete the override.

Worth raising upstream: the axis choice looks like a plain sign error, and the
constants deserve to be parameters either way.
