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

Map<String, String> _r(String date, String subject, String time, String status) =>
    {'date': date, 'subject': subject, 'time': time, 'status': status};

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
  test('report has 127 rows', () => expect(report.length, 127));

  group('inferWeeklyTimetable reconstructs the CURRENT weekly schedule', () {
    final tt = LocalPdfParser.inferWeeklyTimetable(report);

    test('Monday = Supervised, CS-X, Front-End (matches most recent Monday)', () {
      expect(tt['1'], [sup, sup, csx, csx, fejs, fejs]);
    });
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
      final totalLectures =
          plan.countPerDate.values.fold<int>(0, (a, b) => a + b);
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
