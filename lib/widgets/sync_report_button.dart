import 'package:flutter/material.dart';

import '../services/app_refresh_bus.dart';
import '../services/attendance_report_sync_service.dart';
import '../services/review_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_motion.dart';
import 'report_replace_dialog.dart';

/// A circular "sync a new attendance report" button for a screen's AppBar.
///
/// Same job as the Sync New Report screen — pick a PDF, replace that semester's
/// records, back up — reduced to one tap from the dashboard. It moves through
/// three states: the upload icon at rest, a progress ring while the report is
/// being read and written, and a tick briefly afterwards so the sync reads as
/// finished rather than merely stopping.
///
/// A ring rather than the animated GIF this used to play: the GIF's first frame
/// clears its canvas to opaque white with transparency switched off, so it drew
/// its own square over the button's grey chip and looped there forever. The
/// progress ring needs no asset and is theme-coloured for free.
///
/// The resting icon is the bundled PNG, a transparent-background glyph tinted
/// to the theme's content colour, so it reads white on the dark theme and dark
/// on the light one.
///
/// Neutral grey rather than the app's blue: it sits in the AppBar beside the
/// screen title, where blue would read as the primary action of the page. The
/// surface is the same subtle-surface / card-border pair the cards and tiles
/// use, so it belongs to the existing component set in both themes.
class SyncReportButton extends StatefulWidget {
  const SyncReportButton({super.key, this.onSynced});

  /// Called after a successful import, before the tick fades. The whole app is
  /// refreshed through [AppRefreshBus] regardless — this is for anything the
  /// hosting screen wants to do on top.
  final VoidCallback? onSynced;

  /// Outer diameter. Large enough to read as a button and to clear the 44px
  /// minimum touch target once the AppBar's own padding is counted, without
  /// competing with the screen title.
  static const double _size = 40;

  @override
  State<SyncReportButton> createState() => _SyncReportButtonState();
}

class _SyncReportButtonState extends State<SyncReportButton> {
  bool _syncing = false;
  bool _justFinished = false;

  /// Guards against a second tap while the picker or the import is in flight.
  /// Separate from [_syncing], which is only true once there is actually a file
  /// being read — the ring must not spin while the OS file picker is open.
  bool _busy = false;

  /// When the ring appeared, so a fast import still shows it long enough to be
  /// seen rather than flashing.
  DateTime? _spinnerStartedAt;

  /// Minimum time the progress ring stays up. A local parse of a small report
  /// finishes in a few hundred milliseconds, which would blink the ring on and
  /// off and read as a glitch rather than as work happening.
  static const Duration _minSpinnerTime = Duration(milliseconds: 900);

  /// How long the tick stays up after a sync. Long enough to register as an
  /// answer to the tap, short enough not to become a permanent state.
  static const Duration _doneLinger = Duration(milliseconds: 1600);

  Future<void> _sync() async {
    if (_busy) return;
    _busy = true;
    setState(() => _justFinished = false);

    try {
      final result = await const AttendanceReportSyncService().pickAndSync(
        // The ring starts when the *import* does, not when the button is
        // tapped: everything before this is the OS file picker sitting over the
        // app, where a spinner underneath is both invisible and wrong.
        onStage: (stage) {
          if (!mounted || stage != ReportSyncStage.reading) return;
          _spinnerStartedAt = DateTime.now();
          setState(() => _syncing = true);
        },
        // A report for someone else's course cannot be folded into this one, so
        // the import stops here and asks before anything is written.
        confirmReplace: (mismatch) async {
          if (!mounted) return false;
          return confirmReportReplace(context, mismatch);
        },
      );
      if (!mounted) return;

      // Null is a dismissed file picker, or a declined replacement: nothing was
      // imported either way, so drop straight back to the resting icon with no
      // message. The dialog was the user's answer; a snackbar restating it would
      // only be noise.
      if (result == null) {
        setState(() => _syncing = false);
        return;
      }

      await _holdForMinSpinner();
      if (!mounted) return;

      // Every mounted screen re-reads the database, so the dashboard, calendar
      // and profile all show the new report without being revisited.
      AppRefreshBus.instance.refreshAll();
      widget.onSynced?.call();

      setState(() {
        _syncing = false;
        _justFinished = true;
      });

      _showMessage(
        result.replacedPreviousData
            ? 'Replaced your data with the new report (Sem ${result.semester}).'
            : 'Attendance updated from your new report '
                  '(Sem ${result.semester}).',
        isError: false,
      );

      // A completed sync is the app's clearest "something good just happened"
      // moment, so it's where we count toward — and occasionally fire — the Play
      // in-app review prompt. Gated inside the service (min actions, not the
      // first one, once per 30 days); a failed sync never reaches here.
      await ReviewService.instance.registerPositiveAction();
      await ReviewService.instance.maybeRequestReview();

      await Future<void>.delayed(_doneLinger);
      if (mounted) setState(() => _justFinished = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _showMessage(
        AttendanceReportSyncService.friendlyError(error),
        isError: true,
      );
    } finally {
      _busy = false;
    }
  }

  /// Keeps the progress ring up long enough to be seen.
  ///
  /// The import is often faster than the eye, and a spinner that appears and
  /// vanishes inside ~300ms reads as a glitch rather than as progress. Waits
  /// only for the remainder, so a slow parse is never padded.
  Future<void> _holdForMinSpinner() async {
    final startedAt = _spinnerStartedAt;
    if (startedAt == null) return;
    final remaining = _minSpinnerTime - DateTime.now().difference(startedAt);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  /// Shows a message in the app's theme-aware snackbar chip.
  ///
  /// Deliberately not colour-coded green/red. A solid green bar for "done" was
  /// louder than the event deserves and did not match the rest of the app's
  /// messages; the text already says what happened, and an error carries the
  /// danger colour on its icon instead of flooding the whole chip.
  void _showMessage(String text, {required bool isError}) {
    final c = context.appColors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 20,
                color: isError ? c.danger : c.success,
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(child: Text(text)),
            ],
          ),
          duration: Duration(seconds: isError ? 5 : 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final Color content =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;

    final String label = _syncing
        ? 'Syncing attendance report'
        : 'Sync new attendance report';

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: _syncing ? 'Syncing…' : 'Sync new report',
        child: SizedBox.square(
          dimension: SyncReportButton._size,
          child: Material(
            // The grey card surface throughout, syncing or not. The resting icon
            // is a transparent-background glyph tinted to the theme, so it sits
            // directly on this chip with nothing of its own behind it.
            color: c.subtleSurface,
            shape: CircleBorder(side: BorderSide(color: c.cardBorder)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : _sync,
              customBorder: const CircleBorder(),
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.fast),
                  child: _icon(content, c.success),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The button's centre: a progress ring mid-sync, a tick just after, and the
  /// upload icon at rest.
  Widget _icon(Color content, Color success) {
    if (_syncing) {
      return SizedBox.square(
        key: const ValueKey('syncing'),
        // Inset from the 40px chip so the ring reads as sitting inside the
        // button rather than tracing its border.
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          // Matches the resting icon's weight, so the swap changes the shape
          // without changing how heavy the button looks.
          color: content.withValues(alpha: 0.75),
        ),
      );
    }
    if (_justFinished) {
      return Icon(
        Icons.check_rounded,
        key: const ValueKey('done'),
        size: 20,
        color: success,
      );
    }
    // The artwork is a bare glyph on a transparent background, so a plain srcIn
    // tint is all it needs: the alpha channel already separates arrow from
    // nothing, and every visible pixel takes the theme's content colour. It
    // reads white on the dark theme and dark on the light one.
    return Image.asset(
      'assets/icon/upload_pdf_icon.png',
      key: const ValueKey('idle'),
      width: 20,
      height: 20,
      color: content.withValues(alpha: 0.85),
      colorBlendMode: BlendMode.srcIn,
      // The source is much larger than 20px, so it is filtered on the way down
      // rather than left to alias along the arrow's diagonals.
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Wraps [SyncReportButton] with the inset that keeps it off the screen edge.
///
/// An `AppBar` action sits flush against the trailing edge by default, which on
/// a circular button reads as it having been pushed off the screen. The trailing
/// gap matches the dashboard's own horizontal content padding so the button
/// lines up with the cards below it rather than floating past them.
class SyncReportAction extends StatelessWidget {
  const SyncReportAction({super.key, this.onSynced});

  final VoidCallback? onSynced;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width > 600;
    return Padding(
      padding: EdgeInsets.only(
        right: wide ? AppDimens.space32 : AppDimens.space16,
        left: AppDimens.space8,
        top: AppDimens.space8,
        bottom: AppDimens.space8,
      ),
      child: SyncReportButton(onSynced: onSynced),
    );
  }
}
