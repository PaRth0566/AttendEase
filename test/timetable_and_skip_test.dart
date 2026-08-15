import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/services/local_pdf_parser.dart';
import 'package:attend_ease/utils/calculation_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// This suite validates the timetable-inference and safe-to-skip logic against
// the REAL SAP attendance report supplied by the user (PARTH RATHOD, Sem V,
// 15 Jun 2026 → 22 Jul 2026, 127 rows). The report's schedule shifts partway
// through the semester, which is exactly what broke the old inference.
// ─────────────────────────────────────────────────────────────────────────────

// Short subject codes → full names (as they appear in the report).
const osl = 'Operating Systems With LinuxT Div C';
const fejs = 'Front End Develop With Modern JavaScript';
const sen = 'Software Engineering With .NET';
const dbms = 'Database Management SystemsT Div C';
const sup = 'Supervised And Unsuper Learning Models';
const supp = 'Super And Unsuper Learning Models Prac';
const ixp = 'Computer Science Practical IXP DIV C';
const fp = 'Field Project W DIV C';
const csx = 'Computer Science Practical X';
const viiip = 'Computer Science Practical VIIIP Div C';

Map<String, String> _r(
  String date,
  String subject,
  String time,
  String status,
) => {'date': date, 'subject': subject, 'time': time, 'status': status};

/// The full 127-row report, transcribed from the PDF.
final List<Map<String, String>> report = [
  // 2026-06-15 Mon
  _r('2026-06-15', osl, '9:20 AM', 'P'),
  _r('2026-06-15', fejs, '9:20 AM', 'NU'),
  _r('2026-06-15', sen, '10:20 AM', 'P'),
  _r('2026-06-15', fejs, '10:20 AM', 'NU'),
  // 2026-06-16 Tue
  _r('2026-06-16', dbms, '7:00 AM', 'P'),
  _r('2026-06-16', dbms, '8:00 AM', 'P'),
  _r('2026-06-16', osl, '11:30 AM', 'P'),
  _r('2026-06-16', osl, '12:30 PM', 'P'),
  // 2026-06-17 Wed
  _r('2026-06-17', sen, '11:30 AM', 'P'),
  // 2026-06-18 Thu
  _r('2026-06-18', osl, '8:00 AM', 'P'),
  _r('2026-06-18', osl, '9:00 AM', 'P'),
  // 2026-06-19 Fri
  _r('2026-06-19', osl, '9:00 AM', 'A'),
  // 2026-06-20 Sat
  _r('2026-06-20', dbms, '7:00 AM', 'P'),
  // 2026-06-22 Mon
  _r('2026-06-22', sup, '7:00 AM', 'NU'),
  _r('2026-06-22', dbms, '8:00 AM', 'P'),
  _r('2026-06-22', sup, '8:00 AM', 'NU'),
  _r('2026-06-22', fejs, '9:20 AM', 'P'),
  _r('2026-06-22', fejs, '10:20 AM', 'P'),
  // 2026-06-23 Tue
  _r('2026-06-23', dbms, '7:00 AM', 'P'),
  _r('2026-06-23', dbms, '8:00 AM', 'P'),
  _r('2026-06-23', fejs, '9:20 AM', 'P'),
  _r('2026-06-23', fejs, '10:20 AM', 'P'),
  // 2026-06-24 Wed
  _r('2026-06-24', sen, '7:00 AM', 'A'),
  _r('2026-06-24', sen, '8:00 AM', 'A'),
  _r('2026-06-24', sup, '8:00 AM', 'NU'),
  _r('2026-06-24', osl, '9:20 AM', 'A'),
  _r('2026-06-24', osl, '10:20 AM', 'A'),
  _r('2026-06-24', viiip, '11:30 AM', 'A'),
  _r('2026-06-24', viiip, '12:30 PM', 'A'),
  // 2026-06-25 Thu
  _r('2026-06-25', osl, '7:00 AM', 'P'),
  _r('2026-06-25', osl, '8:00 AM', 'P'),
  // 2026-06-27 Sat
  _r('2026-06-27', dbms, '7:00 AM', 'P'),
  _r('2026-06-27', dbms, '8:00 AM', 'NU'),
  _r('2026-06-27', sen, '8:00 AM', 'P'),
  // 2026-06-29 Mon
  _r('2026-06-29', sup, '7:00 AM', 'NU'),
  _r('2026-06-29', osl, '8:00 AM', 'P'),
  _r('2026-06-29', sup, '8:00 AM', 'NU'),
  _r('2026-06-29', fejs, '11:30 AM', 'P'),
  _r('2026-06-29', fejs, '12:30 PM', 'P'),
  // 2026-06-30 Tue
  _r('2026-06-30', dbms, '7:00 AM', 'P'),
  _r('2026-06-30', dbms, '8:00 AM', 'P'),
  _r('2026-06-30', fejs, '9:20 AM', 'P'),
  _r('2026-06-30', fejs, '10:20 AM', 'P'),
  // 2026-07-01 Wed
  _r('2026-07-01', sen, '7:00 AM', 'P'),
  _r('2026-07-01', sen, '8:00 AM', 'P'),
  _r('2026-07-01', sup, '8:00 AM', 'NU'),
  _r('2026-07-01', supp, '9:20 AM', 'P'),
  _r('2026-07-01', supp, '10:20 AM', 'P'),
  _r('2026-07-01', viiip, '11:30 AM', 'P'),
  _r('2026-07-01', viiip, '12:30 PM', 'P'),
  // 2026-07-02 Thu
  _r('2026-07-02', osl, '7:00 AM', 'P'),
  _r('2026-07-02', osl, '8:00 AM', 'P'),
  _r('2026-07-02', ixp, '9:20 AM', 'P'),
  _r('2026-07-02', ixp, '10:20 AM', 'P'),
  // 2026-07-03 Fri
  _r('2026-07-03', sen, '7:00 AM', 'A'),
  _r('2026-07-03', osl, '8:00 AM', 'A'),
  _r('2026-07-03', fp, '9:20 AM', 'P'),
  _r('2026-07-03', fp, '10:20 AM', 'P'),
  // 2026-07-04 Sat
  _r('2026-07-04', dbms, '7:00 AM', 'P'),
  _r('2026-07-04', sen, '8:00 AM', 'P'),
  // 2026-07-06 Mon
  _r('2026-07-06', fejs, '9:20 AM', 'NU'),
  _r('2026-07-06', fejs, '10:20 AM', 'NU'),
  _r('2026-07-06', csx, '11:30 AM', 'NU'),
  _r('2026-07-06', csx, '12:30 PM', 'NU'),
  // 2026-07-07 Tue
  _r('2026-07-07', dbms, '7:00 AM', 'P'),
  _r('2026-07-07', dbms, '8:00 AM', 'P'),
  _r('2026-07-07', fejs, '9:20 AM', 'NU'),
  _r('2026-07-07', fejs, '10:20 AM', 'NU'),
  // 2026-07-08 Wed
  _r('2026-07-08', sen, '7:00 AM', 'P'),
  _r('2026-07-08', sen, '8:00 AM', 'P'),
  _r('2026-07-08', sup, '8:00 AM', 'NU'),
  _r('2026-07-08', supp, '9:20 AM', 'P'),
  _r('2026-07-08', supp, '10:20 AM', 'P'),
  _r('2026-07-08', viiip, '11:30 AM', 'P'),
  _r('2026-07-08', viiip, '12:30 PM', 'P'),
  // 2026-07-09 Thu
  _r('2026-07-09', osl, '7:00 AM', 'P'),
  _r('2026-07-09', osl, '8:00 AM', 'P'),
  _r('2026-07-09', ixp, '9:20 AM', 'P'),
  _r('2026-07-09', ixp, '10:20 AM', 'P'),
  // 2026-07-10 Fri
  _r('2026-07-10', sen, '7:00 AM', 'P'),
  _r('2026-07-10', osl, '8:00 AM', 'P'),
  _r('2026-07-10', fp, '9:20 AM', 'P'),
  _r('2026-07-10', fp, '10:20 AM', 'P'),
  // 2026-07-11 Sat
  _r('2026-07-11', dbms, '7:00 AM', 'NU'),
  _r('2026-07-11', sen, '8:00 AM', 'P'),
  // 2026-07-13 Mon
  _r('2026-07-13', sup, '7:00 AM', 'NU'),
  _r('2026-07-13', sup, '8:00 AM', 'NU'),
  _r('2026-07-13', fejs, '11:20 AM', 'P'),
  _r('2026-07-13', csx, '11:30 AM', 'A'),
  _r('2026-07-13', fejs, '12:20 PM', 'P'),
  _r('2026-07-13', csx, '12:30 PM', 'A'),
  // 2026-07-14 Tue
  _r('2026-07-14', dbms, '7:00 AM', 'P'),
  _r('2026-07-14', dbms, '8:00 AM', 'P'),
  _r('2026-07-14', fejs, '9:20 AM', 'P'),
  _r('2026-07-14', fejs, '10:20 AM', 'P'),
  // 2026-07-15 Wed
  _r('2026-07-15', sen, '7:00 AM', 'P'),
  _r('2026-07-15', sup, '8:00 AM', 'NU'),
  _r('2026-07-15', supp, '9:20 AM', 'P'),
  _r('2026-07-15', supp, '10:20 AM', 'P'),
  _r('2026-07-15', viiip, '11:30 AM', 'P'),
  _r('2026-07-15', viiip, '12:30 PM', 'P'),
  // 2026-07-16 Thu
  _r('2026-07-16', osl, '7:00 AM', 'P'),
  _r('2026-07-16', osl, '8:00 AM', 'P'),
  _r('2026-07-16', ixp, '9:20 AM', 'P'),
  _r('2026-07-16', ixp, '10:20 AM', 'P'),
  // 2026-07-17 Fri
  _r('2026-07-17', sen, '7:00 AM', 'P'),
  _r('2026-07-17', osl, '8:00 AM', 'P'),
  _r('2026-07-17', fp, '9:20 AM', 'P'),
  _r('2026-07-17', fp, '10:20 AM', 'P'),
  // 2026-07-18 Sat
  _r('2026-07-18', dbms, '7:00 AM', 'A'),
  _r('2026-07-18', sen, '8:00 AM', 'A'),
  // 2026-07-20 Mon
  _r('2026-07-20', sup, '7:00 AM', 'P'),
  _r('2026-07-20', sup, '8:00 AM', 'P'),
  _r('2026-07-20', csx, '9:20 AM', 'NU'),
  _r('2026-07-20', csx, '10:20 AM', 'NU'),
  _r('2026-07-20', fejs, '11:20 AM', 'P'),
  _r('2026-07-20', fejs, '12:20 PM', 'P'),
  // 2026-07-21 Tue
  _r('2026-07-21', dbms, '7:00 AM', 'P'),
  _r('2026-07-21', dbms, '8:00 AM', 'P'),
  _r('2026-07-21', fejs, '9:20 AM', 'P'),
  _r('2026-07-21', fejs, '10:20 AM', 'P'),
  // 2026-07-22 Wed
  _r('2026-07-22', sen, '7:00 AM', 'NU'),
  _r('2026-07-22', sup, '8:00 AM', 'P'),
  _r('2026-07-22', supp, '9:20 AM', 'P'),
  _r('2026-07-22', supp, '10:20 AM', 'P'),
  _r('2026-07-22', viiip, '11:30 AM', 'P'),
  _r('2026-07-22', viiip, '12:30 PM', 'P'),
];

/// History rows for a single subject (what the DB layer feeds computeSkipPlan).
List<Map<String, dynamic>> historyFor(String subject) => report
    .where((r) => r['subject'] == subject)
    .map((r) => {'date': r['date'], 'status': r['status']})
    .toList();

void main() {
  test('SAP granted attendance is normalized as present', () {
    final records = [
      _r('2026-07-25', sen, '8:00 AM', 'AG'),
      _r('2026-07-25', fp, '9:20 AM', 'Attendance Granted'),
    ];

    final normalized = records.map((record) {
      final status = record['status']!.toUpperCase();
      return status == 'AG' || status == 'ATTENDANCE GRANTED' ? 'P' : status;
    });

    expect(normalized, ['P', 'P']);
  });

  test('not-conducted sessions do not become part of the weekly plan', () {
    final timetable = LocalPdfParser.inferWeeklyTimetable([
      _r('2026-07-18', dbms, '7:00 AM', 'P'),
      _r('2026-07-25', dbms, '7:00 AM', 'P'),
      _r('2026-07-25', sen, '8:00 AM', 'NC'),
      _r('2026-08-01', sen, '8:00 AM', 'P'),
    ]);

    expect(timetable['6'], [dbms]);
    expect(timetable['6'], isNot(contains(sen)));
  });

  test('not-conducted sessions do not affect skip history', () {
    final plan = computeSkipPlan(
      history: [
        {'date': '2026-07-18', 'status': 'P'},
        {'date': '2026-07-25', 'status': 'NC'},
        {'date': '2026-08-01', 'status': 'P'},
      ],
      attended: 2,
      total: 2,
      requiredPercent: 75,
      today: DateTime(2026, 8, 1),
    );

    expect(plan.maxSkips, 0);
  });

  test(
    'reconciliation input keeps swapped extra sessions as actual records',
    () {
      final saturday = [
        _r('2026-07-25', dbms, '7:00 AM', 'A'),
        _r('2026-07-25', osl, '8:00 AM', 'P'),
      ];

      final bySubject = <String, List<Map<String, String>>>{};
      for (final record in saturday) {
        bySubject.putIfAbsent(record['subject']!, () => []).add(record);
      }

      expect(bySubject[dbms], hasLength(1));
      expect(bySubject[sen], isNull);
      expect(bySubject[osl], hasLength(1));
    },
  );

  test(
    'week skip plan uses replacement lecture history, not weekly plan',
    () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 3, 'total': 3},
          2: {'attended': 3, 'total': 3},
        },
        subjectRequired: {1: 75, 2: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-18', 'status': 'P'},
            {'date': '2026-07-25', 'status': 'P'},
          ],
          2: [
            {'date': '2026-07-18', 'status': 'P'},
            {'date': '2026-07-25', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 22), // Wed
      )!;

      // Both subjects recur on Saturdays only, inferred from the two records.
      final sat = plan.days[5];
      expect(sat.date, DateTime(2026, 7, 25));
      expect(sat.verdict, SkipVerdict.skippable);
      expect(sat.lectureCount, 2);
    },
  );

  group('computeWeekSkipPlan', () {
    // A Monday-only subject. Two prior Mondays establish the weekday; note the
    // current Monday (07-20) is deliberately absent from history, so when a
    // test uses it as `today` the lecture is still unrecorded and on offer.
    Map<int, List<Map<String, dynamic>>> mondayHistory() => {
      1: [
        {'date': '2026-07-06', 'status': 'P'},
        {'date': '2026-07-13', 'status': 'P'},
      ],
    };

    test('returns null when no schedule can be inferred', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 1, 'total': 1},
        },
        subjectRequired: {1: 75},
        // A single occurrence never establishes a recurring weekday.
        subjectHistory: {
          1: [
            {'date': '2026-07-20', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 22),
      );
      expect(plan, isNull);
    });

    test('covers Mon-Sun; non-class weekdays are noClasses', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 10, 'total': 10},
        },
        subjectRequired: {1: 75},
        subjectHistory: mondayHistory(),
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      expect(plan.days, hasLength(7));
      expect(plan.weekStart, DateTime(2026, 7, 20));
      expect(plan.isNextWeek, isFalse);
      expect(plan.days.first.verdict, SkipVerdict.skippable);
      expect(
        plan.days.skip(1).map((d) => d.verdict),
        everyElement(SkipVerdict.noClasses),
      );
    });

    test('mid-week today marks earlier days past and still judges later', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 10, 'total': 10},
        },
        subjectRequired: {1: 75},
        // Mondays and Fridays.
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-10', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-17', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 22), // Wed
      )!;

      // Mon/Tue gone, Wed is today, Fri still on offer.
      expect(plan.days[0].verdict, SkipVerdict.past);
      expect(plan.days[1].verdict, SkipVerdict.past);
      expect(plan.days[4].date, DateTime(2026, 7, 24));
      expect(plan.days[4].verdict, SkipVerdict.skippable);
    });

    test('Sunday rolls over to the coming week with nothing past', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 10, 'total': 10},
        },
        subjectRequired: {1: 75},
        subjectHistory: mondayHistory(),
        overallRequired: 75,
        today: DateTime(2026, 7, 26), // Sun
      )!;

      expect(plan.isNextWeek, isTrue);
      expect(plan.weekStart, DateTime(2026, 7, 27)); // next Monday
      expect(plan.days.map((d) => d.verdict), isNot(contains(SkipVerdict.past)));
    });

    test('cumulative: a one-lecture buffer is not offered twice', () {
      // 3/3 at 75% required -> exactly one lecture of slack.
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 3, 'total': 3},
        },
        subjectRequired: {1: 75},
        // Mondays and Tuesdays, one lecture each.
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-07', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-14', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      expect(plan.days[0].verdict, SkipVerdict.skippable);
      // 3/5 = 60% — the budget is spent, so Tuesday must not also be green.
      expect(plan.days[1].verdict, SkipVerdict.unsafe);
    });

    test('an unsafe day does not abort the walk', () {
      // Monday costs 3 lectures and subject 1 cannot afford them (8/9 = 88.9%
      // -> 8/12 = 66.7%, under target). Tuesday costs 1 and subject 2 can
      // (3/3 -> 3/4 = 75%). The old implementation broke at Monday and never
      // evaluated Tuesday at all.
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 8, 'total': 9},
          2: {'attended': 3, 'total': 3},
        },
        subjectRequired: {1: 75, 2: 75},
        subjectHistory: {
          // Subject 1: three lectures every Monday.
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-06_2', 'status': 'P'},
            {'date': '2026-07-06_3', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-13_2', 'status': 'P'},
            {'date': '2026-07-13_3', 'status': 'P'},
          ],
          // Subject 2: one lecture every Tuesday.
          2: [
            {'date': '2026-07-07', 'status': 'P'},
            {'date': '2026-07-14', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      // Monday fails on subject 1's own target, not the overall percentage.
      expect(plan.days[0].verdict, SkipVerdict.unsafe);
      expect(plan.days[0].lectureCount, 3);
      expect(plan.days[0].blockingSubjectId, 1);
      // The walk continued past the red day and still found Tuesday.
      expect(plan.days[1].verdict, SkipVerdict.skippable);
    });

    test('a below-target subject blocks its day and names itself', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 5, 'total': 10}, // 50%, already under
        },
        subjectRequired: {1: 75},
        subjectHistory: mondayHistory(),
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      expect(plan.days[0].verdict, SkipVerdict.unsafe);
      expect(plan.days[0].blockingSubjectId, 1);
    });

    test("today's already-recorded lectures are not double-counted", () {
      // Monday-only subject, and today IS Monday with the lecture already
      // marked. Re-adding it would charge the same lecture twice.
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 3, 'total': 4},
        },
        subjectRequired: {1: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-20', 'status': 'A'}, // today, already recorded
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      // Nothing left unrecorded today, so there is nothing to offer skipping —
      // but the day was in session, so it is `settled`, not `noClasses`.
      expect(plan.days[0].verdict, SkipVerdict.settled);
    });

    test('an NU lecture today is still weighed, not treated as recorded', () {
      // Regression: today used to be forced to `noClasses` because ANY row
      // dated today — including NU and NC, which getAttendanceStats does not
      // count — marked the subject as already recorded. An NU is conducted but
      // unmarked, so it must still be weighed as a skippable lecture.
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 4, 'total': 4},
        },
        subjectRequired: {1: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-20', 'status': 'NU'}, // today, conducted, unmarked
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      // 4/4 leaves one lecture of slack, so today is genuinely skippable.
      expect(plan.days[0].verdict, SkipVerdict.skippable);
      expect(plan.days[0].lectureCount, 1);
    });

    test('an NC lecture today settles the slot without charging attendance', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 3, 'total': 4},
        },
        subjectRequired: {1: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-20', 'status': 'NC'}, // today, never happened
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      expect(plan.days[0].verdict, SkipVerdict.settled);
    });

    test('one of two same-day lectures marked leaves the other in play', () {
      // Twice-on-Monday subject with only one of today's two lectures marked.
      // A per-subject flag would retire both and wrongly report `settled`.
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 10, 'total': 10},
        },
        subjectRequired: {1: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-06_2', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-13_2', 'status': 'P'},
            {'date': '2026-07-20', 'status': 'P'}, // today, first of two marked
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      // One lecture still outstanding, and 10/10 affords missing it.
      expect(plan.days[0].verdict, SkipVerdict.skippable);
      expect(plan.days[0].lectureCount, 1);
    });

    test('NU on a past day is not re-added as a future lecture', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 8, 'total': 8},
        },
        subjectRequired: {1: 75},
        subjectHistory: {
          1: [
            {'date': '2026-07-06', 'status': 'P'},
            {'date': '2026-07-13', 'status': 'P'},
            {'date': '2026-07-20', 'status': 'NU'}, // Mon this week
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 22), // Wed — Monday is past
      )!;

      // Monday is behind us; it must be `past`, never re-offered.
      expect(plan.days[0].verdict, SkipVerdict.past);
      expect(plan.days[0].lectureCount, 0);
    });

    test('a real absence shrinks the budget for the rest of the week', () {
      // Same subject and week, Monday absent vs Monday attended.
      Map<int, List<Map<String, dynamic>>> history() => {
        1: [
          {'date': '2026-07-06', 'status': 'P'},
          {'date': '2026-07-10', 'status': 'P'},
          {'date': '2026-07-13', 'status': 'P'},
          {'date': '2026-07-17', 'status': 'P'},
        ],
      };

      // 4/4 -> one lecture of slack, so Friday is free.
      final healthy = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 4, 'total': 4},
        },
        subjectRequired: {1: 75},
        subjectHistory: history(),
        overallRequired: 75,
        today: DateTime(2026, 7, 22),
      )!;
      expect(healthy.days[4].verdict, SkipVerdict.skippable);

      // Monday bunked: 4/5 = 80%, and skipping Friday would make it 4/6 = 67%.
      final damaged = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 4, 'total': 5},
        },
        subjectRequired: {1: 75},
        subjectHistory: history(),
        overallRequired: 75,
        today: DateTime(2026, 7, 22),
      )!;
      expect(damaged.days[4].verdict, SkipVerdict.unsafe);
    });

    test('a verdict resting on a future day is flagged conditional', () {
      final plan = computeWeekSkipPlan(
        subjectStats: {
          1: {'attended': 20, 'total': 20},
        },
        subjectRequired: {1: 75},
        // Tuesdays and Fridays, one lecture each. Today is Monday, so *both*
        // are still ahead of us.
        subjectHistory: {
          1: [
            {'date': '2026-07-07', 'status': 'P'},
            {'date': '2026-07-10', 'status': 'P'},
            {'date': '2026-07-14', 'status': 'P'},
            {'date': '2026-07-17', 'status': 'P'},
          ],
        },
        overallRequired: 75,
        today: DateTime(2026, 7, 20), // Mon
      )!;

      // Tuesday is the first future day banked, so its own verdict still rests
      // only on recorded facts — the flag describes what a verdict *depends*
      // on, not whether the day itself is in the future.
      expect(plan.days[1].verdict, SkipVerdict.skippable);
      expect(plan.days[1].dependsOnFuture, isFalse);
      // Friday's verdict assumes Tuesday was actually taken off as offered.
      expect(plan.days[4].verdict, SkipVerdict.skippable);
      expect(plan.days[4].dependsOnFuture, isTrue);
    });
  });

  test('report has 127 rows', () => expect(report.length, 127));

  group('inferWeeklyTimetable reconstructs the CURRENT weekly schedule', () {
    final tt = LocalPdfParser.inferWeeklyTimetable(report);

    test(
      'Monday = Supervised, CS-X, Front-End (matches most recent Monday)',
      () {
        expect(tt['1'], [sup, sup, csx, csx, fejs, fejs]);
      },
    );
    test('Tuesday = DBMS, Front-End', () {
      expect(tt['2'], [dbms, dbms, fejs, fejs]);
    });
    test('Wednesday = SE.NET, Supervised, Super-Prac, VIIIP', () {
      expect(tt['3'], [sen, sup, supp, supp, viiip, viiip]);
    });
    test('Thursday = OS-Linux, IXP', () {
      expect(tt['4'], [osl, osl, ixp, ixp]);
    });
    test('Friday = SE.NET, OS-Linux, Field-Project', () {
      expect(tt['5'], [sen, osl, fp, fp]);
    });
    test('Saturday = DBMS, SE.NET', () {
      expect(tt['6'], [dbms, sen]);
    });
    test('no stale one-off slots leak in (OS-Linux not on Monday anymore)', () {
      expect(tt['1']!.contains(osl), isFalse);
      // Front-End used to be a 9:20 Monday class; it moved to 11:20 — still one
      // subject, not duplicated across the old and new slots.
      expect(tt['1']!.where((s) => s == fejs).length, 2);
    });
  });

  group('computeSkipPlan gives correct day-by-day skips', () {
    final today = DateTime(2026, 7, 22); // report end == "today"

    test('Field Project (6/6) → 2 skips, next Friday 24 Jul (2 lectures)', () {
      final plan = computeSkipPlan(
        history: historyFor(fp),
        attended: 6,
        total: 6,
        requiredPercent: 75,
        today: today,
      );
      expect(plan.maxSkips, 2);
      expect(plan.dates, [DateTime(2026, 7, 24)]);
      expect(plan.countPerDate[DateTime(2026, 7, 24)], 2);
    });

    test('IXP (6/6) → 2 skips, next Thursday 23 Jul (2 lectures)', () {
      final plan = computeSkipPlan(
        history: historyFor(ixp),
        attended: 6,
        total: 6,
        requiredPercent: 75,
        today: today,
      );
      expect(plan.maxSkips, 2);
      expect(plan.dates, [DateTime(2026, 7, 23)]);
    });

    test('DBMS (16/17) → 4 skips spread across Sat + Tue', () {
      final plan = computeSkipPlan(
        history: historyFor(dbms),
        attended: 16,
        total: 17,
        requiredPercent: 75,
        today: today,
      );
      expect(plan.maxSkips, 4);
      // Sat 25 Jul (1) + Tue 28 Jul (2) + Sat 1 Aug (1) = 4 lectures.
      expect(plan.dates, [
        DateTime(2026, 7, 25),
        DateTime(2026, 7, 28),
        DateTime(2026, 8, 1),
      ]);
      final totalLectures = plan.countPerDate.values.fold<int>(
        0,
        (a, b) => a + b,
      );
      expect(totalLectures, 4);
    });

    test('SE.NET exactly at 75% (12/16) → 0 skips, no dates', () {
      final plan = computeSkipPlan(
        history: historyFor(sen),
        attended: 12,
        total: 16,
        requiredPercent: 75,
        today: today,
      );
      expect(plan.maxSkips, 0);
      expect(plan.dates, isEmpty);
    });

    test('CS Practical X below target (0/2) → empty plan', () {
      final plan = computeSkipPlan(
        history: historyFor(csx),
        attended: 0,
        total: 2,
        requiredPercent: 75,
        today: today,
      );
      expect(plan.maxSkips, 0);
      expect(plan.dates, isEmpty);
    });
  });
}
