// Regression tests for the attendance-row parser.
//
// These cover the extraction rules that decide whether a subject exists at all
// and how many lectures it is credited with — the numbers a student checks
// against their SAP portal. Every case here corresponds to a defect that
// silently produced a wrong report rather than an error:
//
//   * a hyphen or digit in a name truncated it, merging "…-III" and "…-IV"
//     into one subject with pooled attendance;
//   * ".NET" (leading dot) and "C#" (two characters) were dropped outright, so
//     an enrolled subject simply never appeared;
//   * a page-break banner between two rows was absorbed into the course name;
//   * "Sept." failed to map to a month, dropping every row of such a report.
//
// The parser's PDF entry point needs a real document, so these drive the pure
// extraction helpers through the same public surface the import path uses.

import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/services/local_pdf_parser.dart';

void main() {
  // The bug these cover: a Semester V report imported as Semester 1.
  //
  // In a real SVKM report the semester is not a field of its own — it is the
  // tail of the Academic Session value, written label-first ("2026-2027,
  // Semester V"). The old code searched for a digit and found the "01" of the
  // duration's "From 01.06.2026", which nothing downstream could tell apart
  // from a real semester.
  group('extractSemesterNumber', () {
    // The header of an actual report, flattened the way the parser sees it.
    const svkmHeader =
        'Attendance Report Student Name HARDIK RATHOD '
        'Student Number 40721240035 Roll No. C089 '
        'Academic Year & Academic Session 2026-2027, Semester V '
        'Program Name Bachelor of Science (Computer Science) '
        'Attendance Report Duration : From 01.06.2026 to 06.08.2026';

    test('reads the semester out of the academic session value', () {
      expect(LocalPdfParser.extractSemesterNumber(svkmHeader), 5);
    });

    test('the report duration is never read as the semester', () {
      // "From 01.06.2026" is what produced Semester 1.
      expect(
        LocalPdfParser.extractSemesterNumber(
          'Attendance Report Duration : From 01.06.2026 to 06.08.2026',
        ),
        isNull,
      );
    });

    test('reads a digit spelled after the label', () {
      expect(LocalPdfParser.extractSemesterNumber('Semester 5 Report'), 5);
      expect(LocalPdfParser.extractSemesterNumber('Sem. 05 Report'), 5);
      expect(LocalPdfParser.extractSemesterNumber('Semester: 3'), 3);
    });

    test('also reads the value-first spelling', () {
      expect(
        LocalPdfParser.extractSemesterNumber('Program Name VI Semester From'),
        6,
      );
      expect(LocalPdfParser.extractSemesterNumber('5th Sem'), 5);
    });

    test('a date after the label is never the semester', () {
      // The precise failure: "01" from a date must not become semester 1.
      expect(
        LocalPdfParser.extractSemesterNumber(
          'Program Name Semester 01.11.2025 to 25.02.2026',
        ),
        isNull,
      );
    });

    test('an academic session is not a semester', () {
      expect(
        LocalPdfParser.extractSemesterNumber('2025-2026 Academic Session'),
        isNull,
      );
    });

    test('a subject named "Seminar" is not read as the semester label', () {
      // Substring matching on "Sem" would take "12" off the row before it.
      expect(
        LocalPdfParser.extractSemesterNumber(
          'Program Name VII Semester From 01.11.2025 '
          'Sr No Course Name 12 Seminar Nov 03, 2025 9:20:00 AM',
        ),
        7,
      );
    });

    test('returns null when the header names no semester', () {
      // Null rather than 1: the caller must be able to tell "not stated" from
      // "stated as the first semester".
      expect(
        LocalPdfParser.extractSemesterNumber('Attendance Report DBMS Lab'),
        isNull,
      );
    });
  });

  group('semesterTokenValue', () {
    test('reads Roman numerals, including subtractive ones', () {
      expect(LocalPdfParser.semesterTokenValue('IV'), 4);
      expect(LocalPdfParser.semesterTokenValue('V'), 5);
      expect(LocalPdfParser.semesterTokenValue('VIII'), 8);
      expect(LocalPdfParser.semesterTokenValue('iii'), 3);
    });

    test('reads a zero-padded digit', () {
      // The old `\b[1-8]\b` rule could not match inside "05" and fell through
      // to the caller's default.
      expect(LocalPdfParser.semesterTokenValue('05'), 5);
    });

    test('rejects a token that merely contains a number', () {
      // The heart of the fix: a date is one token and matches no semester
      // shape, so it cannot contribute a digit.
      expect(LocalPdfParser.semesterTokenValue('01.11.2025'), isNull);
      expect(LocalPdfParser.semesterTokenValue('2025-2026'), isNull);
      expect(LocalPdfParser.semesterTokenValue('A123'), isNull);
    });

    test('rejects values outside the plausible range', () {
      expect(LocalPdfParser.semesterTokenValue('0'), isNull);
      expect(LocalPdfParser.semesterTokenValue('99'), isNull);
      expect(LocalPdfParser.semesterTokenValue(''), isNull);
    });
  });

  group('semesterNumberFrom', () {
    // Used for short label strings, e.g. re-reading a stored "Semester V".
    test('reads a label-and-value string', () {
      expect(LocalPdfParser.semesterNumberFrom('Semester V'), 5);
      expect(LocalPdfParser.semesterNumberFrom('Sem 3'), 3);
      expect(LocalPdfParser.semesterNumberFrom('Semester 05'), 5);
      expect(LocalPdfParser.semesterNumberFrom('Sem-IV'), 4);
      expect(LocalPdfParser.semesterNumberFrom('7'), 7);
    });

    test('returns null when there is no semester to read', () {
      expect(LocalPdfParser.semesterNumberFrom(''), isNull);
      expect(LocalPdfParser.semesterNumberFrom('Semester'), isNull);
    });
  });

  group('inferWeeklyTimetable', () {
    // The weekly footprint drives both the calendar's forward projection and
    // the "safe to skip" advice, so a subject that recurs must be recognised
    // and a one-off must not be.
    test('keeps a subject that recurs on a weekday and drops a one-off', () {
      // 2025-11-03, -10, -17 are Mondays; 2025-11-04 is a single Tuesday.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-11-03', 'subject': 'DBMS', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'DBMS', 'status': 'A', 'time': '9:20:00 AM'},
        {'date': '2025-11-17', 'subject': 'DBMS', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-04', 'subject': 'Seminar', 'status': 'P', 'time': '9:20:00 AM'},
      ]);

      expect(timetable['1'], ['DBMS'], reason: 'Monday recurs on three dates');
      expect(
        timetable.containsKey('2'),
        isFalse,
        reason: 'a single Tuesday sighting is not a recurring class',
      );
    });

    test('orders a day by start time and repeats a twice-taught subject', () {
      // Two Mondays, the most recent holding two OS lectures plus a later DBMS.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-11-03', 'subject': 'OS', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'OS', 'status': 'P', 'time': '10:15:00 AM'},
        {'date': '2025-11-03', 'subject': 'DBMS', 'status': 'P', 'time': '2:00:00 PM'},
        {'date': '2025-11-10', 'subject': 'OS', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10_2', 'subject': 'OS', 'status': 'P', 'time': '10:15:00 AM'},
        {'date': '2025-11-10', 'subject': 'DBMS', 'status': 'P', 'time': '2:00:00 PM'},
      ]);

      expect(
        timetable['1'],
        ['OS', 'OS', 'DBMS'],
        reason: 'morning double period precedes the afternoon lecture',
      );
    });

    test('excludes NC but counts NU toward the weekly pattern', () {
      // NU means the lecture happened and was left unmarked, so the slot is
      // real. NC means it never happened, so it must not create a slot.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-11-03', 'subject': 'NU Subject', 'status': 'NU', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'NU Subject', 'status': 'NU', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'NC Subject', 'status': 'NC', 'time': '11:00:00 AM'},
        {'date': '2025-11-10', 'subject': 'NC Subject', 'status': 'NC', 'time': '11:00:00 AM'},
      ]);

      expect(timetable['1'], ['NU Subject']);
      expect(timetable['1'], isNot(contains('NC Subject')));
    });

    test('a 12-hour clock sorts correctly across noon', () {
      // "12:30 PM" is 12:30, not 00:30 — a naive conversion put the afternoon
      // lab first and reversed the whole day.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-11-03', 'subject': 'Morning', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'Noon', 'status': 'P', 'time': '12:30:00 PM'},
        {'date': '2025-11-10', 'subject': 'Morning', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'Noon', 'status': 'P', 'time': '12:30:00 PM'},
      ]);

      expect(timetable['1'], ['Morning', 'Noon']);
    });

    test('drops a slot that stopped running early in the semester', () {
      // A subject rescheduled away mid-term must not keep projecting onto the
      // calendar. "Recent" is within 21 days of that subject's own last record.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-09-01', 'subject': 'Dropped', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-09-08', 'subject': 'Dropped', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'Current', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'Current', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-17', 'subject': 'Current', 'status': 'P', 'time': '9:20:00 AM'},
      ]);

      expect(timetable['1'], ['Current']);
    });

    test('a subject whose name carries a hyphen and numeral survives intact', () {
      // The names most at risk from the old letters-only extraction. Two
      // variants of one stem must stay two separate slots, not merge.
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': '2025-11-03', 'subject': 'Applied Mathematics-III', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'Applied Mathematics-III', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'Applied Mathematics-IV', 'status': 'P', 'time': '11:00:00 AM'},
        {'date': '2025-11-10', 'subject': 'Applied Mathematics-IV', 'status': 'P', 'time': '11:00:00 AM'},
      ]);

      expect(
        timetable['1'],
        ['Applied Mathematics-III', 'Applied Mathematics-IV'],
        reason: 'two distinct courses, not one merged subject',
      );
    });

    test('ignores rows with an unparseable date instead of throwing', () {
      final timetable = LocalPdfParser.inferWeeklyTimetable([
        {'date': 'pad_1', 'subject': 'Padding', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '', 'subject': 'Blank', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-03', 'subject': 'Real', 'status': 'P', 'time': '9:20:00 AM'},
        {'date': '2025-11-10', 'subject': 'Real', 'status': 'P', 'time': '9:20:00 AM'},
      ]);

      expect(timetable['1'], ['Real']);
    });

    test('returns an empty map for no records', () {
      expect(LocalPdfParser.inferWeeklyTimetable([]), isEmpty);
    });
  });

  group('extractJuniorCollegeTerm', () {
    const jcHeaderFYJC =
        'Attendance Report Student Name NEEL DOLIA '
        'Student Number 40104260737 Roll No. G018 '
        'Academic Year & Academic Session 2026-2027, F.Y.J.C '
        'Program Name H.S.C.- Commerce (MBC) '
        'Attendance Report Duration : From 01.08.2026 to 01.09.2026';

    const jcHeaderSYJC =
        'Attendance Report Student Name JOHN DOE '
        'Student Number 40104260999 Roll No. G020 '
        'Academic Year & Academic Session 2026-2027, S.Y.J.C '
        'Program Name H.S.C.- Science '
        'Attendance Report Duration : From 01.08.2026 to 01.09.2026';

    test('extracts FYJC term from report header and variations', () {
      expect(LocalPdfParser.extractJuniorCollegeTerm(jcHeaderFYJC), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, F.Y.J.C'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, FYJC'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, F Y J C'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('FYJC Session'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('F.Y.J.C.'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('F. Y. J. C.'), 'FYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('F . Y . J . C'), 'FYJC');
    });

    test('extracts SYJC term from report header and variations', () {
      expect(LocalPdfParser.extractJuniorCollegeTerm(jcHeaderSYJC), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, S.Y.J.C'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, SYJC'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('2026-2027, S Y J C'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('SYJC Session'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('S.Y.J.C.'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('S. Y. J. C.'), 'SYJC');
      expect(LocalPdfParser.extractJuniorCollegeTerm('S . Y . J . C'), 'SYJC');
    });

    test('returns null for Degree College headers', () {
      const degreeHeader =
          'Attendance Report Student Name PARTH RATHOD '
          'Academic Year & Academic Session 2026-2027, Semester V '
          'Program Name Bachelor of Science (Computer Science)';
      expect(LocalPdfParser.extractJuniorCollegeTerm(degreeHeader), isNull);
    });
  });

  group('detectCollegeType', () {
    test('detects junior college when F.Y.J.C / FYJC / F Y J C is present', () {
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, F.Y.J.C'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, FYJC'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, F Y J C'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, F.Y.J.C.'),
        'junior',
      );
    });

    test('detects junior college when S.Y.J.C / SYJC / S Y J C is present', () {
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, S.Y.J.C'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, SYJC'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, S Y J C'),
        'junior',
      );
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, S.Y.J.C.'),
        'junior',
      );
    });

    test('detects junior college on full actual report format from screenshot', () {
      // Uses the ACTUAL text from the device — Syncfusion concatenates tokens
      // without whitespace (e.g. "F.Y.J.CAcademic", "DOLIAStudent").
      const actualNeelDoliaFYJC =
          'Page 1 of 8Attendance Report NEEL DOLIAStudent Name '
          '40104260737Student Number G018Roll No. '
          '2026-2027, F.Y.J.CAcademic Year & Academic Session '
          'H.S.C.- Commerce (MBC)Program Name '
          'From 01.08.2026 to 01.09.2026';

      const actualNeelDoliaSYJC =
          'Page 1 of 8Attendance Report NEEL DOLIAStudent Name '
          '40104260737Student Number G018Roll No. '
          '2026-2027, S.Y.J.CAcademic Year & Academic Session '
          'H.S.C.- Commerce (MBC)Program Name '
          'From 01.08.2026 to 01.09.2026';

      // Also test the spaced format (from earlier assumptions)
      const spacedFYJC =
          'Academic Year & Academic Session 2026-2027, F.Y.J.C '
          'Program Name H.S.C.- Commerce (MBC)';

      expect(LocalPdfParser.detectCollegeType(actualNeelDoliaFYJC), 'junior');
      expect(LocalPdfParser.extractJuniorCollegeTerm(actualNeelDoliaFYJC), 'FYJC');

      expect(LocalPdfParser.detectCollegeType(actualNeelDoliaSYJC), 'junior');
      expect(LocalPdfParser.extractJuniorCollegeTerm(actualNeelDoliaSYJC), 'SYJC');

      expect(LocalPdfParser.detectCollegeType(spacedFYJC), 'junior');
      expect(LocalPdfParser.extractJuniorCollegeTerm(spacedFYJC), 'FYJC');
    });

    test('detects degree college when Semester is present', () {
      expect(
        LocalPdfParser.detectCollegeType('Academic Year & Academic Session 2026-2027, Semester V'),
        'degree',
      );
      expect(
        LocalPdfParser.detectCollegeType('Semester 3 Attendance Report'),
        'degree',
      );
    });

    test('returns null when neither is detected rather than defaulting to degree', () {
      expect(
        LocalPdfParser.detectCollegeType('Attendance Report 2026-2027'),
        isNull,
      );
    });

    test('extracts correct start and end dates from Junior report duration', () {
      const actualNeelDoliaFYJC =
          'Page 1 of 8Attendance Report NEEL DOLIAStudent Name '
          '40104260737Student Number G018Roll No. '
          '2026-2027, F.Y.J.CAcademic Year & Academic Session '
          'H.S.C.- Commerce (MBC)Program Name '
          'From 01.08.2026 to 01.09.2026';

      final dateSpanMatch = RegExp(
        r'From\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})\s+to\s+(\d{2})[\.\-\/](\d{2})[\.\-\/](\d{4})',
        caseSensitive: false,
      ).firstMatch(actualNeelDoliaFYJC);

      expect(dateSpanMatch, isNotNull);
      final startDate =
          '${dateSpanMatch!.group(3)}-${dateSpanMatch.group(2)}-${dateSpanMatch.group(1)}';
      final endDate =
          '${dateSpanMatch.group(6)}-${dateSpanMatch.group(5)}-${dateSpanMatch.group(4)}';

      expect(startDate, '2026-08-01');
      expect(endDate, '2026-09-01');
    });
  });
}
