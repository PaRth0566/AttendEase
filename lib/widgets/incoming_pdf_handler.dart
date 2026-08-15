import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/db_helper.dart';
import '../router/app_router.dart';
import '../services/app_refresh_bus.dart';
import '../services/attendance_report_sync_service.dart';
import '../services/incoming_pdf_service.dart';
import '../services/local_pdf_parser.dart';
import '../services/report_owner_check.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'app_overlays.dart';
import 'report_replace_dialog.dart';

/// Asks about, and then performs, an import of a PDF opened from outside the app.
///
/// Wraps the router's child so it sits under a `Navigator` — the dialogs need
/// one — and is otherwise invisible: it renders [child] untouched and does
/// nothing at all unless a PDF actually arrives.
///
/// Where an arriving report goes depends on how far into the app the user is:
///
///   * **Signed in, set up** — a confirm dialog, then the same import the
///     dashboard's sync button runs.
///   * **Signed in, no data yet** — parsed and handed to the setup wizard at
///     `/setup/basic`, exactly as the Upload Report screen does on success, so
///     onboarding continues from the report they just opened.
///   * **Signed out** — held, and picked up again as soon as auth completes.
///     Their tap is not wasted just because they were not signed in.
class IncomingPdfHandler extends StatefulWidget {
  const IncomingPdfHandler({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingPdfHandler> createState() => _IncomingPdfHandlerState();
}

class _IncomingPdfHandlerState extends State<IncomingPdfHandler> {
  final IncomingPdfService _service = IncomingPdfService.instance;

  /// The context to show dialogs and snackbars from.
  ///
  /// Deliberately *not* this widget's own `context`. This handler wraps the
  /// router's child, which puts it above the `Navigator` and above any
  /// `ScaffoldMessenger` — so `Navigator.of(context)` and
  /// `ScaffoldMessenger.maybeOf(context)` either threw or silently found
  /// nothing, and no dialog could ever appear. Going through the root navigator
  /// key gets a context underneath both.
  BuildContext? get _uiContext => AppRouter.rootNavigatorKey.currentContext;

  /// Guards against a second PDF stacking a dialog on the first, in the spirit
  /// of `UpdateService.runExclusiveSheet`.
  bool _busy = false;

  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _service.onPdfReceived.addListener(_onWarmDelivery);
    // A PDF held while the user was signed out becomes importable the moment
    // they are in. Watching auth state rather than patching each login screen
    // keeps this to one place and covers Google, email and guest sign-in alike.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null || !_service.hasHeld) return;
      // Let the router finish redirecting first. Sign-in completing is not the
      // same moment as the destination screen being on-screen, and asking "sync
      // this report?" over a half-built route is how a dialog ends up attached
      // to a navigator that is about to be replaced.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted || !_service.hasHeld) return;
      final held = _service.takeHeld();
      if (held != null) await _handle(held);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitial());
  }

  @override
  void dispose() {
    _service.onPdfReceived.removeListener(_onWarmDelivery);
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _checkInitial() async {
    final pdf = await _service.takeInitialPdf();
    if (pdf != null) await _handle(pdf);
  }

  void _onWarmDelivery() {
    final pdf = _service.onPdfReceived.value;
    if (pdf == null) return;
    _service.onPdfReceived.value = null;
    _handle(pdf);
  }

  /// Routes [pdf] according to how far into the app the user is.
  Future<void> _handle(IncomingPdf pdf) async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      // Signed-in only, guest or Google alike — importing writes into a
      // per-user database and backs up to that user's cloud document, so there
      // is nowhere to put a report until we know whose it is. The router is
      // already sending them to /login; hold the report and let the auth
      // listener resume this the moment they are in, so their tap is not lost.
      if (FirebaseAuth.instance.currentUser == null) {
        _service.hold(pdf);
        return;
      }

      // Wait for a navigator to exist before trying to show anything on it.
      // On a cold start this runs from the first post-frame callback, which can
      // land before the router has built its first route — and a dialog with no
      // navigator is the silent no-op that made the feature look dead.
      if (!await _waitForNavigator()) {
        _service.hold(pdf);
        return;
      }

      if (await _hasSetupData()) {
        await _confirmAndSync(pdf);
      } else {
        await _sendToSetup(pdf);
      }
    } finally {
      _busy = false;
    }
  }

  /// Polls briefly for the root navigator to come up. True once it has.
  Future<bool> _waitForNavigator() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (!mounted) return false;
      if (_uiContext != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _uiContext != null;
  }

  /// Whether this user has subjects yet — the same question the router's
  /// redirect asks before letting `/app/*` through.
  Future<bool> _hasSetupData() async {
    try {
      final db = await DBHelper.instance.database;
      final subjects = await db.query('subjects', limit: 1);
      return subjects.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Set-up user: confirm, then import ─────────────────────────────────────

  Future<void> _confirmAndSync(IncomingPdf pdf) async {
    final confirmed = await _askToSync(pdf.name);
    if (confirmed != true || !mounted) return;

    // Reassignable, because a report from a different course interrupts the
    // import to ask: the progress dialog comes down, the confirm goes up, and a
    // fresh progress dialog replaces it. The two cannot be stacked — a confirm
    // opened behind the non-dismissible progress barrier is unreachable, which
    // would strand the import waiting on an answer the user cannot give.
    var progress = _showProgress();
    try {
      final result = await const AttendanceReportSyncService().syncFromBytes(
        pdf.bytes,
        confirmReplace: (mismatch) =>
            _handOffToReplaceConfirm(mismatch, progress, (fresh) {
              progress = fresh;
            }),
      );
      // Whichever handle is current — the original, or the one the replacement
      // put up. Closing the stale one is a no-op.
      progress.close();
      if (!mounted) return;

      // Null is a declined replacement: nothing was written, so there is
      // nothing to refresh or announce.
      if (result == null) return;

      // Every mounted tab re-reads the database, so the dashboard, calendar and
      // profile all show the new report without being revisited.
      AppRefreshBus.instance.refreshAll();

      // Land on the dashboard. Opening a report from the "Open with" sheet is a
      // cold start as often as not, and the launch route is wherever the user
      // last was — the calendar or a subject detail page. Showing the numbers
      // that just changed is the answer to the tap.
      final uiContext = _uiContext;
      if (uiContext != null && uiContext.mounted) {
        uiContext.go('/app/dashboard');
      }

      _showMessage(_successMessage(result), isError: false);
    } catch (error) {
      progress.close();
      if (!mounted) return;
      await _showParseError(AttendanceReportSyncService.friendlyError(error));
    }
  }

  /// Swaps the progress dialog out for the replace confirmation and, if the user
  /// agrees, puts a fresh progress dialog back up before the wipe begins.
  ///
  /// [onReplaced] hands the new handle back to the caller's local, so the close
  /// that follows the import targets the dialog actually on screen.
  Future<bool> _handOffToReplaceConfirm(
    ReportOwnerMismatch mismatch,
    _ProgressHandle progress,
    void Function(_ProgressHandle) onReplaced,
  ) async {
    progress.close();
    if (!mounted) return false;
    final uiContext = _uiContext;
    if (uiContext == null || !uiContext.mounted) return false;

    final replace = await confirmReportReplace(uiContext, mismatch);
    if (!replace || !mounted) return false;

    // Erasing and re-importing takes visibly longer than a normal sync, and the
    // label is the only thing telling the user their data is going.
    onReplaced(_showProgress(label: 'Replacing your data…'));
    return true;
  }

  /// What to say after an import, which depends on whether it replaced the
  /// previous course's data or merely folded a semester in.
  String _successMessage(AttendanceReportSyncResult result) =>
      result.replacedPreviousData
      ? 'Replaced your data with the new report (Sem ${result.semester}).'
      : 'Attendance updated from your new report (Sem ${result.semester}).';

  /// The error a wrong PDF gets, with the offer to pick a different one.
  ///
  /// Same message the in-app upload shows, since it is the same parser refusing
  /// the same file.
  Future<void> _showParseError(String message) async {
    final uiContext = _uiContext;
    if (uiContext == null) return;
    final retry = await showAppDialog<bool>(
      context: uiContext,
      builder: (dialogContext) => _errorDialog(
        dialogContext,
        message: message,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppDimens.space4),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space20,
                vertical: AppDimens.space12,
              ),
            ),
            child: const Text('Choose another PDF'),
          ),
        ],
      ),
    );
    if (retry != true || !mounted) return;

    // Straight to the existing picker-and-import path, so the retry behaves
    // exactly like syncing from inside the app — including the hand-off to the
    // replace confirmation when the new pick is another course's report.
    var progress = _showProgress();
    try {
      final result = await const AttendanceReportSyncService().pickAndSync(
        confirmReplace: (mismatch) =>
            _handOffToReplaceConfirm(mismatch, progress, (fresh) {
              progress = fresh;
            }),
      );
      progress.close();
      if (!mounted || result == null) return;
      AppRefreshBus.instance.refreshAll();
      final retryContext = _uiContext;
      if (retryContext != null && retryContext.mounted) {
        retryContext.go('/app/dashboard');
      }
      _showMessage(_successMessage(result), isError: false);
    } catch (error) {
      progress.close();
      if (!mounted) return;
      _showMessage(
        AttendanceReportSyncService.friendlyError(error),
        isError: true,
      );
    }
  }

  Future<bool?> _askToSync(String fileName) {
    final uiContext = _uiContext;
    if (uiContext == null) return Future<bool?>.value(null);
    return showAppDialog<bool>(
      context: uiContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final c = dialogContext.appColors;
        return AlertDialog(
          // A tinted disc behind the glyph, so the icon reads as a deliberate
          // header rather than a symbol floating above the title. Same primary
          // colour as before, just carrying a faint ground.
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sync_rounded,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          title: const Text('Sync this report?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update your attendance from this report? Only the semester it '
                'covers is replaced. Your other semesters stay as they are.',
                textAlign: TextAlign.center,
                // Roomier line height: the body sits directly under a centred
                // title, and at the default leading three full-width lines read
                // as a block of text rather than a sentence.
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppDimens.space20),
              // The filename gets its own surface. Left bare it was just a third
              // line of grey text competing with the message above it; boxed, it
              // reads at a glance as "this is the file you tapped", which is the
              // one thing worth double checking before overwriting a semester.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space10,
                ),
                decoration: BoxDecoration(
                  color: c.subtleSurface,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  border: Border.all(color: c.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 18,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: AppDimens.space10),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppDimens.space20,
            AppDimens.space8,
            AppDimens.space20,
            AppDimens.space20,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            const SizedBox(width: AppDimens.space4),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              // The dismiss button is a bare label while this one is a filled
              // pill, so a little breathing room inside it keeps the pair from
              // reading lopsided.
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space20,
                  vertical: AppDimens.space12,
                ),
              ),
              child: const Text('Sync now'),
            ),
          ],
        );
      },
    );
  }

  // ── New user: hand the report to the setup wizard ──────────────────────────

  Future<void> _sendToSetup(IncomingPdf pdf) async {
    final progress = _showProgress(label: 'Reading your attendance report…');
    try {
      final data = await LocalPdfParser.extractAttendanceFromPdf(
        pdf.bytes,
      ).timeout(AttendanceReportSyncService.parseTimeout);
      progress.close();
      if (!mounted) return;
      // The destination UploadPdfScreen uses on success, so the rest of
      // onboarding is reached the way it always was.
      AppRouter.rootNavigatorKey.currentContext?.go(
        '/setup/basic',
        extra: data,
      );
    } catch (error) {
      progress.close();
      if (!mounted) return;
      await _showParseErrorForSetup(
        AttendanceReportSyncService.friendlyError(error),
      );
    }
  }

  /// Pre-setup variant of the error: there is nothing to sync into yet, so the
  /// only offer is to try a different file.
  Future<void> _showParseErrorForSetup(String message) async {
    final uiContext = _uiContext;
    if (uiContext == null) return;
    await showAppDialog<void>(
      context: uiContext,
      builder: (dialogContext) => _errorDialog(
        dialogContext,
        message: message,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// The look shared by both error dialogs: a tinted disc round the glyph,
  /// matching [_askToSync]'s icon treatment, and the roomier body line height.
  Widget _errorDialog(
    BuildContext dialogContext, {
    required String message,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(dialogContext);
    final c = dialogContext.appColors;
    return AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.error_outline_rounded, color: c.danger, size: 24),
      ),
      title: const Text('That PDF cannot be read'),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppDimens.space20,
        AppDimens.space8,
        AppDimens.space20,
        AppDimens.space20,
      ),
      // "Choose another PDF" beside "Cancel" is wider than a narrow phone's
      // dialog, and the default row would let the label wrap inside the pill.
      // Overflowing stacks them instead, which stays legible at any width.
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: AppDimens.space8,
      actions: actions,
    );
  }

  // ── Shared chrome ─────────────────────────────────────────────────────────

  /// A non-dismissible progress dialog, and the handle that closes it.
  ///
  /// Returned as a closer rather than tracked in a field so every path that
  /// opens one closes exactly that one, including on an early return.
  _ProgressHandle _showProgress({String label = 'Syncing your attendance…'}) {
    final uiContext = _uiContext;
    if (uiContext == null) return _ProgressHandle(null);
    final navigator = Navigator.of(uiContext, rootNavigator: true);
    showAppDialog<void>(
      context: uiContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
    return _ProgressHandle(navigator);
  }

  /// Shows a message in the app's theme-aware snackbar chip.
  ///
  /// The status colour rides on the leading icon rather than filling the bar, so
  /// these read the same as every other message in the app.
  void _showMessage(String text, {required bool isError}) {
    final uiContext = _uiContext;
    if (uiContext == null) return;
    final messenger = ScaffoldMessenger.maybeOf(uiContext);
    if (messenger == null) return;
    final c = uiContext.appColors;
    messenger.showSnackBar(
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
  Widget build(BuildContext context) => widget.child;
}

/// Closes a progress dialog exactly once, whatever path gets there.
class _ProgressHandle {
  _ProgressHandle(this._navigator);

  /// Null when there was no navigator to show a dialog on, which makes [close]
  /// a no-op — callers can close unconditionally without checking.
  final NavigatorState? _navigator;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    final navigator = _navigator;
    if (navigator != null && navigator.canPop()) navigator.pop();
  }
}
