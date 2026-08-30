import 'package:flutter_test/flutter_test.dart';

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
  });
}
