import 'package:flutter/material.dart';

import '../services/report_owner_check.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'app_overlays.dart';

/// Asks whether to throw away everything the app holds and rebuild it from a
/// report belonging to a different student or course.
///
/// The one gate in front of `LocalDataResetService.clearAllAcademicData`, so it
/// has to be unambiguous about what disappears: every subject, the timetable,
/// every attendance record, the profile header, and the cloud backup — which the
/// import overwrites wholesale on its way out, not merges.
///
/// Returns false on cancel and on a dismissed barrier, so the caller's "did they
/// agree" check is a plain boolean and a stray tap can never trigger the wipe.
Future<bool> confirmReportReplace(
  BuildContext context,
  ReportOwnerMismatch mismatch,
) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    // Nothing about this is dismissible by accident.
    barrierDismissible: false,
    builder: (dialogContext) => _ReportReplaceDialog(mismatch: mismatch),
  );
  return confirmed ?? false;
}

class _ReportReplaceDialog extends StatelessWidget {
  const _ReportReplaceDialog({required this.mismatch});

  final ReportOwnerMismatch mismatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    // The student's name is the stronger signal and the one a friend's report
    // trips, so it leads when both fired. A different course under the same name
    // is the rarer transfer case.
    final bool byStudent = mismatch.differentStudent;

    return AlertDialog(
      // Same tinted-disc header the sync and error dialogs use, in the warning
      // colour: this is a fork in the road, not a failure.
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c.warning.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.swap_horiz_rounded,
          color: c.warning,
          size: 24,
        ),
      ),
      title: Text(
        byStudent
            ? 'This report is for a different student'
            : 'This report is for a different course',
      ),
      // Scrollable because this content is long and the dialog is now width-
      // capped. `AlertDialog` lays `content` out at intrinsic height inside a
      // Flexible with no scroll view of its own, so anything taller than the
      // room left over after the title and the stacked actions simply
      // overflows. Capping the dialog at [maxDialogWidth] narrowed this column
      // from 672px to 432px, the four paragraphs rewrapped ~32px taller, and it
      // tipped over the edge — but the same overflow was already reachable at a
      // large OS font scale. This is the treatment `showAppDialog`'s doc comment
      // asks long dialogs for.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _summary(byStudent),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: AppDimens.space16),
            // What actually goes, itemised. "Everything will be replaced" is easy
            // to skim past; three named things are not.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space12,
                vertical: AppDimens.space12,
              ),
              decoration: BoxDecoration(
                color: c.subtleSurface,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                border: Border.all(color: c.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Loss(
                    icon: Icons.menu_book_rounded,
                    text: _subjectsLine(),
                  ),
                  const SizedBox(height: AppDimens.space10),
                  const _Loss(
                    icon: Icons.calendar_view_week_rounded,
                    text: 'Your weekly timetable, rebuilt from the new report',
                  ),
                  const SizedBox(height: AppDimens.space10),
                  _Loss(
                    icon: Icons.person_rounded,
                    text: _profileLine(byStudent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space16),
            Text(
              'Your cloud backup will be replaced too. This cannot be undone.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: c.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppDimens.space20,
        AppDimens.space8,
        AppDimens.space20,
        AppDimens.space20,
      ),
      // "Replace all data" beside "Cancel" overruns a narrow phone's dialog, and
      // the default row would wrap the label inside the pill. Stacking stays
      // legible at any width — same treatment as the parse-error dialog.
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: AppDimens.space8,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: AppDimens.space4),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space20,
              vertical: AppDimens.space12,
            ),
          ),
          child: const Text('Replace all data'),
        ),
      ],
    );
  }

  /// The opening sentence, naming both sides of whichever mismatch fired.
  ///
  /// Each half is only spelled out when the parser actually read it — an empty
  /// stored course is possible on an install set up by hand, and "belongs to ''"
  /// would read as a bug.
  String _summary(bool byStudent) {
    final stored = byStudent ? mismatch.storedName : mismatch.storedCourse;
    final incoming = byStudent ? mismatch.reportName : mismatch.reportCourse;
    final subject = byStudent ? 'student' : 'course';

    final buffer = StringBuffer();
    if (incoming.isNotEmpty) {
      buffer.write('This report belongs to $incoming');
      if (stored.isNotEmpty) {
        buffer.write(', but your data is for $stored');
      }
      buffer.write('. ');
    } else {
      buffer.write("This report is for a different $subject than your data. ");
    }
    buffer.write(
      'The two cannot be combined — keeping both would mix the subjects and '
      'timetables together.',
    );
    return buffer.toString();
  }

  /// How much is being thrown away, in the only unit the user can see.
  String _subjectsLine() {
    final stored = mismatch.storedSubjectCount;
    final incoming = mismatch.reportSubjectCount;
    final storedLabel = stored == 1 ? '1 subject' : '$stored subjects';
    if (stored == 0) {
      return 'All existing subjects and their attendance records';
    }
    return '$storedLabel and all their attendance records, replaced by the '
        "report's $incoming";
  }

  String _profileLine(bool byStudent) {
    if (byStudent && mismatch.reportName.isNotEmpty) {
      return 'Your profile — name, course and year — becomes '
          '${mismatch.reportName}';
    }
    return 'Your profile details: name, course, year and semester';
  }
}

/// One line of the "what you lose" list: a muted glyph and its text.
class _Loss extends StatelessWidget {
  const _Loss({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Nudged down onto the first line's baseline rather than its box top,
          // which at this text size sits noticeably high.
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: muted),
        ),
        const SizedBox(width: AppDimens.space10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ),
      ],
    );
  }
}
