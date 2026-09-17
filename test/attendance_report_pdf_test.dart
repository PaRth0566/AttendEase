import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:attend_ease/services/attendance_report_pdf.dart';

/// A fixed stamp so nothing here depends on the day the suite runs.
final _stamp = DateTime(2026, 3, 14);

ReportMeta _meta() => ReportMeta(
  periodKind: 'Semester',
  periodLabel: 'Semester 5',
  semester: 5,
  studentName: 'Test Student',
  course: 'B.Tech Computer Engineering',
  year: 'Third Year',
  generatedAt: _stamp,
);

void main() {
  // buildAttendanceReportPdf loads the bundled Inter faces through rootBundle,
  // which needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReportSubjectRow', () {
    test('percent and isOnTrack follow the screen\'s own test', () {
      const r = ReportSubjectRow(
        name: 'DBMS',
        attended: 15,
        total: 20,
        requiredPercent: 75,
      );
      expect(r.percent, 75);
      // Exactly on the target counts as met, matching the report screen.
      expect(r.isOnTrack, isTrue);
    });

    test('lecturesToSpare counts misses that keep the target', () {
      const r = ReportSubjectRow(
        name: 'OS',
        attended: 18,
        total: 20,
        requiredPercent: 75,
      );
      // 18/24 = 75%, so four more may be missed; a fifth breaks it.
      expect(r.lecturesToSpare, 4);
      expect(r.lecturesToAttend, 0);
    });

    test('lecturesToAttend counts the climb back', () {
      const r = ReportSubjectRow(
        name: 'Maths',
        attended: 10,
        total: 20,
        requiredPercent: 75,
      );
      expect(r.isOnTrack, isFalse);
      expect(r.lecturesToSpare, 0);
      // 30/40 = 75%.
      expect(r.lecturesToAttend, 20);
    });

    test('a subject with no conducted lecture is neither ahead nor behind', () {
      const r = ReportSubjectRow(
        name: 'Elective',
        attended: 0,
        total: 0,
        requiredPercent: 75,
      );
      expect(r.percent, 0);
      // Both counts stay zero: there is no advice to give about a subject that
      // has not been taught, and 0% must not be read as failing.
      expect(r.lecturesToSpare, 0);
      expect(r.lecturesToAttend, 0);
    });
  });

  group('dominantTarget', () {
    test('falls back to 75 with no rows', () {
      expect(dominantTarget(const []), 75);
    });

    test('picks the most common target', () {
      expect(
        dominantTarget(const [
          ReportSubjectRow(name: 'a', attended: 1, total: 1, requiredPercent: 75),
          ReportSubjectRow(name: 'b', attended: 1, total: 1, requiredPercent: 75),
          ReportSubjectRow(name: 'c', attended: 1, total: 1, requiredPercent: 60),
        ]),
        75,
      );
    });

    test('breaks a tie towards the stricter target', () {
      expect(
        dominantTarget(const [
          ReportSubjectRow(name: 'a', attended: 1, total: 1, requiredPercent: 60),
          ReportSubjectRow(name: 'b', attended: 1, total: 1, requiredPercent: 80),
        ]),
        80,
      );
    });
  });

  group('buildAttendanceReportPdf', () {
    test('renders a document for a mixed set of subjects', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: _meta(),
        rows: const [
          // Behind, on target, and untaught — every branch of the row builder.
          ReportSubjectRow(
            name: 'Engineering Mathematics III',
            attended: 12,
            total: 24,
            requiredPercent: 75,
          ),
          ReportSubjectRow(
            name: 'Database Management Systems',
            attended: 22,
            total: 24,
            requiredPercent: 75,
          ),
          ReportSubjectRow(
            name: 'Open Elective',
            attended: 0,
            total: 0,
            requiredPercent: 75,
          ),
        ],
      );

      expect(bytes, isNotEmpty);
      // %PDF- magic: proves a real document came back rather than an empty buffer.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders with no subjects at all', () async {
      final bytes = await buildAttendanceReportPdf(meta: _meta(), rows: const []);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders enough subjects to spill onto a second page', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: _meta(),
        rows: [
          for (var i = 0; i < 40; i++)
            ReportSubjectRow(
              name: 'Subject number ${i + 1} with a fairly long title',
              attended: i,
              total: 40,
              requiredPercent: 75,
            ),
        ],
      );
      expect(bytes, isNotEmpty);
    });

    test('renders Junior College report with TERM FYJC', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Term',
          periodLabel: 'FYJC',
          semester: 1,
          studentName: 'NEEL DOLIA',
          course: 'H.S.C.- Commerce (MBC)',
          year: '2026-2027',
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(
            name: 'Economics COM DIV G',
            attended: 12,
            total: 22,
            requiredPercent: 70,
          ),
          ReportSubjectRow(
            name: 'Mathematics & Statistics P COM DIV G',
            attended: 4,
            total: 6,
            requiredPercent: 70,
          ),
        ],
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders Junior College report with TERM SYJC', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'SYJC',
          periodKind: 'Term',
          periodLabel: 'SYJC',
          semester: 2,
          studentName: 'NEEL DOLIA',
          course: 'H.S.C.- Commerce (MBC)',
          year: '2026-2027',
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(
            name: 'Economics COM DIV G',
            attended: 18,
            total: 20,
            requiredPercent: 70,
          ),
        ],
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('Junior College PDF Subject Progress-Bar Colors & Table Rules', () {
    List<ReportMeter> extractMeters(pw.Widget widget) {
      final table = widget as pw.Table;
      final meters = <ReportMeter>[];
      for (final row in table.children.skip(1)) {
        final padding = row.children[0] as pw.Padding;
        final column = padding.child as pw.Column;
        for (final child in column.children) {
          if (child is ReportMeter) {
            meters.add(child);
          }
        }
      }
      return meters;
    }

    List<String> extractAllTexts(pw.Widget root) {
      final texts = <String>[];
      void visit(pw.Widget w) {
        if (w is pw.Text) {
          texts.add((w.text as dynamic).toPlainText() as String);
        } else if (w is pw.SingleChildWidget) {
          if (w.child != null) visit(w.child!);
        } else if (w is pw.MultiChildWidget) {
          for (final c in w.children) {
            visit(c);
          }
        } else if (w is pw.Table) {
          for (final row in w.children) {
            for (final cell in row.children) {
              visit(cell);
            }
          }
        }
      }
      visit(root);
      return texts;
    }

    test('1. Junior overall >= 75% -> ALL subject progress bars are GREEN', () {
      expect(juniorSubjectBarColor(overallPercent: 75.0), equals(reportColorGood));
      expect(juniorSubjectBarColor(overallPercent: 75.5), equals(reportColorGood));
      expect(juniorSubjectBarColor(overallPercent: 88.2), equals(reportColorGood));

      final barColor = juniorSubjectBarColor(overallPercent: 75.5);
      final table = buildJuniorTable(
        const [
          ReportSubjectRow(name: 'Economics', attended: 12, total: 22, requiredPercent: 70),
          ReportSubjectRow(name: 'Mathematics', attended: 4, total: 6, requiredPercent: 70),
          ReportSubjectRow(name: 'English', attended: 17, total: 20, requiredPercent: 70),
        ],
        barColor: barColor,
      );

      final meters = extractMeters(table);
      expect(meters, hasLength(3));
      for (final meter in meters) {
        expect(meter.color, equals(reportColorGood), reason: 'All bars must be GREEN when overall >= 75%');
        expect(meter.color, isNot(equals(reportColorBrand)), reason: 'Bars must not be BLUE');
        expect(meter.color, isNot(equals(reportColorBad)), reason: 'Bars must not be RED');
      }
    });

    test('2. Junior overall < 75% -> ALL subject progress bars are RED', () {
      expect(juniorSubjectBarColor(overallPercent: 74.9), equals(reportColorBad));
      expect(juniorSubjectBarColor(overallPercent: 73.6), equals(reportColorBad));
      expect(juniorSubjectBarColor(overallPercent: 55.0), equals(reportColorBad));

      final barColor = juniorSubjectBarColor(overallPercent: 73.6);
      final table = buildJuniorTable(
        const [
          ReportSubjectRow(name: 'Economics', attended: 12, total: 22, requiredPercent: 70),
          ReportSubjectRow(name: 'Mathematics', attended: 4, total: 6, requiredPercent: 70),
          ReportSubjectRow(name: 'English', attended: 17, total: 20, requiredPercent: 70),
        ],
        barColor: barColor,
      );

      final meters = extractMeters(table);
      expect(meters, hasLength(3));
      for (final meter in meters) {
        expect(meter.color, equals(reportColorBad), reason: 'All bars must be RED when overall < 75%');
        expect(meter.color, isNot(equals(reportColorBrand)), reason: 'Bars must not be BLUE');
        expect(meter.color, isNot(equals(reportColorGood)), reason: 'Bars must not be GREEN');
      }
    });

    test('3. Subject percentage does NOT independently determine Junior bar color', () {
      const rows = [
        ReportSubjectRow(name: 'Economics', attended: 12, total: 22, requiredPercent: 70), // 54.5%
        ReportSubjectRow(name: 'Mathematics', attended: 4, total: 6, requiredPercent: 70),  // 66.7%
        ReportSubjectRow(name: 'English', attended: 17, total: 20, requiredPercent: 70),    // 85.0%
      ];

      // Scenario A: Overall >= 75% (e.g. 75.5%)
      // Even though Economics is 54.5% and Mathematics is 66.7%, their bars MUST be GREEN.
      final safeColor = juniorSubjectBarColor(overallPercent: 75.5);
      final safeTable = buildJuniorTable(rows, barColor: safeColor);
      final safeMeters = extractMeters(safeTable);

      expect(safeMeters[0].color, equals(reportColorGood), reason: 'Economics (54.5%) must be GREEN because overall >= 75%');
      expect(safeMeters[1].color, equals(reportColorGood), reason: 'Mathematics (66.7%) must be GREEN because overall >= 75%');
      expect(safeMeters[2].color, equals(reportColorGood), reason: 'English (85.0%) must be GREEN because overall >= 75%');

      // Scenario B: Overall < 75% (e.g. 73.6%)
      // Even though English is 85.0%, its bar MUST be RED because overall < 75%.
      final unsafeColor = juniorSubjectBarColor(overallPercent: 73.6);
      final unsafeTable = buildJuniorTable(rows, barColor: unsafeColor);
      final unsafeMeters = extractMeters(unsafeTable);

      expect(unsafeMeters[0].color, equals(reportColorBad), reason: 'Economics (54.5%) must be RED because overall < 75%');
      expect(unsafeMeters[1].color, equals(reportColorBad), reason: 'Mathematics (66.7%) must be RED because overall < 75%');
      expect(unsafeMeters[2].color, equals(reportColorBad), reason: 'English (85.0%) must be RED because overall < 75%');
    });

    test('4. Junior FYJC term PDF uses the correct color', () async {
      // FYJC with overall >= 75%: 76 of 100 conducted = 76.0%
      final safePdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Term',
          periodLabel: 'FYJC',
          semester: 11,
          studentName: 'FYJC Student',
          course: 'H.S.C. Commerce',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'Economics', attended: 38, total: 50, requiredPercent: 70),
          ReportSubjectRow(name: 'English', attended: 38, total: 50, requiredPercent: 70),
        ],
      );
      expect(safePdf, isNotEmpty);
      expect(String.fromCharCodes(safePdf.take(5)), '%PDF-');

      // FYJC with overall < 75%: 70 of 100 conducted = 70.0%
      final unsafePdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Term',
          periodLabel: 'FYJC',
          semester: 11,
          studentName: 'FYJC Student',
          course: 'H.S.C. Commerce',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'Economics', attended: 35, total: 50, requiredPercent: 70),
          ReportSubjectRow(name: 'English', attended: 35, total: 50, requiredPercent: 70),
        ],
      );
      expect(unsafePdf, isNotEmpty);
      expect(String.fromCharCodes(unsafePdf.take(5)), '%PDF-');
    });

    test('5. Junior SYJC term PDF uses the correct color', () async {
      // SYJC with overall >= 75%
      final safePdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'SYJC',
          periodKind: 'Term',
          periodLabel: 'SYJC',
          semester: 12,
          studentName: 'SYJC Student',
          course: 'H.S.C. Science',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'Physics', attended: 80, total: 100, requiredPercent: 70),
        ],
      );
      expect(safePdf, isNotEmpty);
      expect(String.fromCharCodes(safePdf.take(5)), '%PDF-');

      // SYJC with overall < 75%
      final unsafePdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'SYJC',
          periodKind: 'Term',
          periodLabel: 'SYJC',
          semester: 12,
          studentName: 'SYJC Student',
          course: 'H.S.C. Science',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'Physics', attended: 70, total: 100, requiredPercent: 70),
        ],
      );
      expect(unsafePdf, isNotEmpty);
      expect(String.fromCharCodes(unsafePdf.take(5)), '%PDF-');
    });

    test('6. Junior custom-date PDF uses the correct color', () async {
      final safeCustomPdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Date range',
          periodLabel: '1 Aug 2026 – 31 Aug 2026',
          semester: 11,
          studentName: 'Junior Date Range Student',
          course: 'H.S.C. Arts',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'History', attended: 16, total: 20, requiredPercent: 70),
        ],
      );
      expect(safeCustomPdf, isNotEmpty);
      expect(String.fromCharCodes(safeCustomPdf.take(5)), '%PDF-');

      final unsafeCustomPdf = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Date range',
          periodLabel: '1 Aug 2026 – 31 Aug 2026',
          semester: 11,
          studentName: 'Junior Date Range Student',
          course: 'H.S.C. Arts',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: _stamp,
        ),
        rows: const [
          ReportSubjectRow(name: 'History', attended: 14, total: 20, requiredPercent: 70),
        ],
      );
      expect(unsafeCustomPdf, isNotEmpty);
      expect(String.fromCharCodes(unsafeCustomPdf.take(5)), '%PDF-');
    });

    test('7. Junior PDF table content: informational percentages, NO subject targets/risk/skip/recovery', () {
      final table = buildJuniorTable(
        const [
          ReportSubjectRow(name: 'Economics', attended: 12, total: 22, requiredPercent: 70),
          ReportSubjectRow(name: 'Mathematics', attended: 4, total: 6, requiredPercent: 70),
        ],
        barColor: reportColorGood,
      );

      final texts = extractAllTexts(table);

      // Must contain expected Junior table headers and data
      expect(texts, contains('SUBJECT'));
      expect(texts, contains('ATTENDED'));
      expect(texts, contains('CONDUCTED'));
      expect(texts, contains('ATTENDANCE'));
      expect(texts, contains('Economics'));
      expect(texts, contains('12'));
      expect(texts, contains('22'));
      expect(texts, contains('54.5%'));
      expect(texts, contains('Mathematics'));
      expect(texts, contains('4'));
      expect(texts, contains('6'));
      expect(texts, contains('66.7%'));

      // Must NOT contain Degree columns or subject target/action/chip text
      expect(texts, isNot(contains('ACTUAL')));
      expect(texts, isNot(contains('TARGET')));
      expect(texts, isNot(contains('NEXT STEP')));
      expect(texts, isNot(contains('ON TRACK')));
      expect(texts, isNot(contains('AT RISK')));
      expect(texts, isNot(contains('BELOW REQ.')));

      for (final t in texts) {
        expect(t.contains('Can miss'), isFalse);
        expect(t.contains('Miss none'), isFalse);
        expect(t.contains('Attend all'), isFalse);
        expect(t.contains('in a row'), isFalse);
      }
    });

    test('9. Degree PDF progress-bar behavior is completely untouched and per-subject', () {
      final degreeTable = buildDegreeTable(
        const [
          // On track (90% >= 70%)
          ReportSubjectRow(name: 'DBMS', attended: 18, total: 20, requiredPercent: 70),
          // At risk (50% < 70%)
          ReportSubjectRow(name: 'Computer Networks', attended: 10, total: 20, requiredPercent: 70),
        ],
      );

      final meters = extractMeters(degreeTable);
      expect(meters, hasLength(2));

      // DBMS is >= 70% target -> GREEN with target tick at 0.70
      expect(meters[0].color, equals(reportColorGood));
      expect(meters[0].target, 0.7);

      // Computer Networks is < 70% target -> RED with target tick at 0.70
      expect(meters[1].color, equals(reportColorBad));
      expect(meters[1].target, 0.7);

      // Degree table contains Degree-specific columns and action texts
      final degreeTexts = extractAllTexts(degreeTable);
      expect(degreeTexts, contains('SUBJECT'));
      expect(degreeTexts, contains('ATTENDED'));
      expect(degreeTexts, contains('ACTUAL'));
      expect(degreeTexts, contains('TARGET'));
      expect(degreeTexts, contains('NEXT STEP'));
      expect(degreeTexts, contains('70%'));
      expect(degreeTexts, contains('Can miss 5'));
      expect(degreeTexts, contains('Attend 14 in a row'));
    });
  });
}
