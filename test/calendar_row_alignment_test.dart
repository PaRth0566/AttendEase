// Where the calendar's per-row P/A controls land horizontally.
//
// The trailing block of a record card is a P/A cluster and, on rows that have
// one, a delete button. Those two competing requirements are what makes the
// alignment easy to get wrong:
//
//  * Down a single day's stack the clusters must line up, so a row with no
//    delete button still reserves the column one — otherwise the pills step 42px
//    sideways from card to card.
//  * But a day where *nothing* is deletable has no column to line up with, and
//    reserving one there just indents every row's pills away from the card edge.
//    That is the "Not Updated day looks mis-aligned" bug: a day of projected
//    lectures rendered every P/A pair 42px short of the right edge, paying for a
//    button that appeared on none of its rows.
//
// `occupiesDeleteColumn` is the single predicate both rules read, so the two can
// never disagree about which rows own that column.

import 'package:attend_ease/screens/calendar/calender_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row as `getDaySchedule` returns it.
Map<String, dynamic> row({
  required String status,
  int? recordId,
  int isVirtual = 0,
}) {
  return {
    'record_id': recordId,
    'status': status,
    'is_virtual': isVirtual,
    'subject_name': 'Software Engineering',
    'timetable_entry_id': 1,
    'record_date': '2026-08-10',
    'source': 'pdf',
    'original_status': status,
  };
}

/// A projected lecture on a date the report has not covered: no stored row at
/// all, which is what the calendar shows as "Not Updated".
Map<String, dynamic> virtualNU() =>
    row(status: 'NU', recordId: null, isVirtual: 1);

void main() {
  group('a row owns the delete column when', () {
    test('it holds a stored Present or Absent', () {
      // The two cases that actually render a delete button.
      expect(occupiesDeleteColumn(row(status: 'P', recordId: 7)), isTrue);
      expect(occupiesDeleteColumn(row(status: 'A', recordId: 8)), isTrue);
    });

    test('it holds a stored Not Conducted', () {
      // No button, but a disabled icon in its place explaining that the report's
      // own row cannot be deleted — same width, same column.
      expect(occupiesDeleteColumn(row(status: 'NC', recordId: 9)), isTrue);
    });
  });

  group('a row does not own the delete column when', () {
    test('it is a projected lecture', () {
      expect(
        occupiesDeleteColumn(virtualNU()),
        isFalse,
        reason: 'there is no stored row to delete',
      );
    });

    test('it is a stored Not Updated', () {
      expect(
        occupiesDeleteColumn(row(status: 'NU', recordId: 11)),
        isFalse,
        reason: 'deleting a stored NU would destroy the PDF baseline that makes '
            'its P/A pills tappable in the first place, so no button is offered',
      );
    });
  });

  group('across a whole day', () {
    test('a day of nothing but Not Updated reserves no column', () {
      // The screenshot case: four projected lectures, no delete button anywhere,
      // so nothing should be indented for one.
      final day = [virtualNU(), virtualNU(), virtualNU(), virtualNU()];

      expect(
        day.any(occupiesDeleteColumn),
        isFalse,
        reason: 'every P/A pair sits against the card edge — this is the bug the '
            'predicate exists to fix',
      );
    });

    test('one deletable row makes the whole day reserve it', () {
      // A part-marked day: three lectures, one already Present. The two unmarked
      // rows must still reserve the column, or their pills sit 42px right of the
      // marked row's and the stack reads as ragged.
      final day = [row(status: 'P', recordId: 7), virtualNU(), virtualNU()];

      expect(day.any(occupiesDeleteColumn), isTrue);
      expect(
        day.where(occupiesDeleteColumn),
        hasLength(1),
        reason: 'only the marked row draws a button; the other two just hold the '
            'space so all three line up',
      );
    });

    test('a fully marked day reserves it on every row', () {
      final day = [
        row(status: 'P', recordId: 7),
        row(status: 'A', recordId: 8),
        row(status: 'NC', recordId: 9),
      ];

      expect(day.every(occupiesDeleteColumn), isTrue);
    });
  });
}
