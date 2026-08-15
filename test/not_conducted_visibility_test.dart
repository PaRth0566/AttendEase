import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/database/subject_dao.dart';
import 'package:attend_ease/database/timetable_dao.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/models/timetable_entry.dart';
import 'package:attend_ease/services/pdf_attendance_import_service.dart';

/// "Not Conducted" has to survive the whole trip: it is created by the import,
/// read back by the calendar's day schedule, and read back again by the subject
/// detail timeline. Two separate breaks used to swallow it — a first upload
/// never generated the rows, and the subject history query filtered them out —
/// so both ends are asserted here rather than only the DAO in the middle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  /// A Saturday the report covers, with DBMS and .NET both planned.
  const importedDate = '2026-07-25';

  Future<({int dbmsId, int netId})> seedSemester() async {
    // Private database: test files run concurrently and would otherwise fight
    // over the shared default name. Drop the cached connection before deleting
    // the file, so DBHelper is never left pointing at a deleted database.
    DBHelper.databaseFileName = 'not_conducted_visibility_test.db';
    await DBHelper.resetForTest();
    final databasePath = p.join(
      await getDatabasesPath(),
      DBHelper.databaseFileName,
    );
    await deleteDatabase(databasePath);

    final subjectDao = SubjectDao();
    final dbmsId = await subjectDao.insertSubject(
      Subject(name: 'DBMS', requiredPercent: 75, semester: 1),
    );
    final netId = await subjectDao.insertSubject(
      Subject(name: '.NET', requiredPercent: 75, semester: 1),
    );
    return (dbmsId: dbmsId, netId: netId);
  }

  test(
    'first upload materializes NC for a planned lecture the report omits',
    () async {
      // No timetable is inserted here on purpose: this is the very first upload,
      // so the only weekly plan that exists is the one the import infers from
      // the report itself. Reconciliation used to be skipped entirely in this
      // case, which is what made NC invisible until a *second* report arrived.
      final ids = await seedSemester();
      final attendanceDao = AttendanceDao();

      await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
        semester: 1,
        updateSemesterBounds: false,
        data: {
          'startDate': '2026-07-04',
          'endDate': importedDate,
          'subjects': ['DBMS', '.NET'],
          'attendanceRecords': [
            // Both subjects run on the three earlier Saturdays, which is what
            // gives the inferred timetable a two-lecture Saturday to expect.
            {'date': '2026-07-04', 'subject': 'DBMS', 'status': 'P'},
            {'date': '2026-07-04', 'subject': '.NET', 'status': 'P'},
            {'date': '2026-07-11', 'subject': 'DBMS', 'status': 'P'},
            {'date': '2026-07-11', 'subject': '.NET', 'status': 'P'},
            {'date': '2026-07-18', 'subject': 'DBMS', 'status': 'P'},
            {'date': '2026-07-18', 'subject': '.NET', 'status': 'A'},
            // On the last Saturday .NET is absent from the report while DBMS
            // still ran: a planned lecture that was not conducted.
            {'date': importedDate, 'subject': 'DBMS', 'status': 'P'},
          ],
          'inferredTimetable': {
            '${DateTime.saturday}': ['DBMS', '.NET'],
          },
        },
      );

      final day = await attendanceDao.getDaySchedule(importedDate, 1);
      expect(
        {for (final row in day) row['subject_name']: row['status']},
        {'DBMS': 'P', '.NET': 'NC'},
        reason: 'a first upload must gap-fill the omitted planned lecture',
      );

      // The NC row is the point of the timeline entry — it explains why .NET's
      // total is lower than the four Saturdays would suggest.
      final netHistory = await attendanceDao.getAttendanceHistoryForSubject(
        ids.netId,
      );
      expect(
        netHistory.any(
          (row) => row['date'] == importedDate && row['status'] == 'NC',
        ),
        isTrue,
        reason: 'subject detail must show the not-conducted lecture',
      );

      // NC is not attendance: it must not move either half of the fraction.
      final stats = await attendanceDao.getAttendanceStats(1);
      expect(stats[ids.netId], {'attended': 2, 'total': 3});
      expect(stats[ids.dbmsId], {'attended': 4, 'total': 4});
    },
  );

  test('re-importing the same report does not duplicate NC rows', () async {
    // The dashboard button and the Sync New Report screen run the same import,
    // and a student re-syncing the report they already have is routine. NC rows
    // are generated rather than parsed, so a non-idempotent reconcile would pile
    // a fresh one up on every sync.
    final ids = await seedSemester();
    final timetableDao = TimetableDao();
    final attendanceDao = AttendanceDao();
    for (final subjectId in [ids.dbmsId, ids.netId]) {
      await timetableDao.ensureSeedEntry(subjectId);
    }
    for (final (order, subjectId) in [ids.dbmsId, ids.netId].indexed) {
      await timetableDao.insertEntry(
        TimetableEntry(
          dayOfWeek: DateTime.saturday,
          subjectId: subjectId,
          lectureOrder: order + 1,
        ),
      );
    }

    final data = {
      'startDate': importedDate,
      'endDate': importedDate,
      'subjects': ['DBMS', '.NET'],
      'attendanceRecords': [
        {'date': importedDate, 'subject': 'DBMS', 'status': 'P'},
      ],
      'inferredTimetable': <String, List<String>>{},
    };

    for (var i = 0; i < 3; i++) {
      await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
        semester: 1,
        updateSemesterBounds: false,
        data: data,
      );
    }

    final netHistory = await attendanceDao.getAttendanceHistoryForSubject(
      ids.netId,
    );
    final ncRows = netHistory.where((row) => row['status'] == 'NC').toList();
    expect(
      ncRows.length,
      1,
      reason: 'three syncs of one report must leave exactly one NC row',
    );
  });
}
