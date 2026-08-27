import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'pressable.dart';

/// The calendar's selected-day heading: the date, and — when the day is one that
/// can be marked — the two pills that set every lecture on it Present or Absent.
///
/// Both live on one line, which is the whole reason this is a widget rather than a
/// `Text`: the pills take a fixed width out of the row, and a long date
/// ("Wednesday, September 30, 2026") then has to give way on a narrow phone
/// without being cut in half. See [headingFor] for how the wrap point is chosen.
class CalendarDayHeader extends StatelessWidget {
  const CalendarDayHeader({
    super.key,
    required this.day,
    required this.showBulkActions,
    required this.onMarkAllPresent,
    required this.onMarkAllAbsent,
  });

  /// The day whose lectures are listed below the heading.
  final DateTime day;

  /// Whether the day is one a bulk mark may write to at all. False for Sundays,
  /// future days, days with nothing markable on them, and while the day's records
  /// are still loading — the caller owns that decision.
  final bool showBulkActions;

  final VoidCallback onMarkAllPresent;
  final VoidCallback onMarkAllAbsent;

  /// Short labels, on purpose: they sit beside a date on one line, and they read
  /// as "the P on every card below" rather than as a new kind of control. The
  /// tooltips carry the long form.
  static const String presentLabel = 'All P';
  static const String absentLabel = 'All A';

  /// `Tuesday, August 25, 2026`, wrappable only after the weekday.
  ///
  /// Left to itself the text breaks at whichever space runs out first and strands
  /// "2026" alone on a second line. Joining the date's own parts with
  /// non-breaking spaces leaves exactly one break opportunity, so the heading
  /// wraps as "Tuesday," / "August 25, 2026" or stays on one line — never split
  /// mid-date.
  static String headingFor(DateTime day) {
    final String weekday = DateFormat('EEEE').format(day);
    final String date = DateFormat('MMMM d, yyyy').format(day);
    return '$weekday, ${date.replaceAll(' ', '\u00A0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              headingFor(day),
              // Two lines rather than an ellipsis: the heading is the thing on
              // this row that has to stay readable, and with the pills beside it
              // one line is not always enough.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.25,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
          if (showBulkActions) ...[
            const SizedBox(width: AppDimens.space10),
            // Pinned text scale: the pair is sized to leave the heading its room,
            // and a large system font would otherwise grow them until the date had
            // none. Same treatment as the calendar's legend row.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pill(
                    label: presentLabel,
                    tooltip: 'Mark every lecture on this day present',
                    icon: Icons.done_all_rounded,
                    color: c.success,
                    onTap: onMarkAllPresent,
                  ),
                  const SizedBox(width: AppDimens.space6),
                  _pill(
                    label: absentLabel,
                    tooltip: 'Mark every lecture on this day absent',
                    icon: Icons.remove_done_rounded,
                    color: c.danger,
                    onTap: onMarkAllAbsent,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One bulk-mark pill.
  ///
  /// Deliberately the same outlined-pill language as the per-row P/A toggles, in
  /// the same success/danger pair the day's cards and the month heatmap use.
  Widget _pill({
    required String label,
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      // The colour and the day below carry the meaning; this is the long form for
      // anyone who wants it, and the hint a screen reader reads out.
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: AppDimens.brSm,
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Pressable(
          onTap: onTap,
          borderRadius: AppDimens.brSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space8,
              vertical: AppDimens.space6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: AppDimens.space4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
