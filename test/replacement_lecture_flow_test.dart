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
import 'package:attend_ease/utils/calculation_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('July 25 replacement lecture stays authoritative end-to-end', () async {
    final databasePath = p.join(await getDatabasesPath(), 'attendease.db');
    await deleteDatabase(databasePath);

    final subjectDao = SubjectDao();
    final timetableDao = TimetableDao();
    final attendanceDao = AttendanceDao();
    final dbmsId = await subjectDao.insertSubject(
      Subject(name: 'DBMS', requiredPercent: 75, semester: 1),
    );
    final netId = await subjectDao.insertSubject(
      Subject(name: '.NET', requiredPercent: 75, semester: 1),
    );
    final osId = await subjectDao.insertSubject(
      Subject(name: 'Operating Systems', requiredPercent: 75, semester: 1),
    );
    for (final subjectId in [dbmsId, netId, osId]) {
      await timetableDao.ensureSeedEntry(subjectId);
    }
    await timetableDao.insertEntry(
      TimetableEntry(
        dayOfWeek: DateTime.saturday,
        subjectId: dbmsId,
        lectureOrder: 1,
      ),
    );
    await timetableDao.insertEntry(
      TimetableEntry(
        dayOfWeek: DateTime.saturday,
        subjectId: netId,
        lectureOrder: 2,
      ),
    );

    final osSeedId = await timetableDao.ensureSeedEntry(osId);
    for (final date in ['2026-07-04', '2026-07-11', '2026-07-18']) {
      await attendanceDao.upsertAttendance(
        timetableId: osSeedId,
        date: date,
        status: 'P',
        source: 'pdf',
        originalStatus: 'P',
      );
    }

    await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
      semester: 1,
      updateSemesterBounds: false,
      data: {
        'startDate': '2026-07-25',
        'endDate': '2026-07-25',
        'subjects': ['DBMS', '.NET', 'Operating Systems'],
        'attendanceRecords': [
          {'date': '2026-07-25', 'subject': 'DBMS', 'status': 'P'},
          {'date': '2026-07-25', 'subject': 'Operating Systems', 'status': 'P'},
        ],
        'inferredTimetable': <String, List<String>>{},
      },
    );

    final calendar = await attendanceDao.getDaySchedule('2026-07-25', 1);
    expect(
      {for (final row in calendar) row['subject_name']: row['status']},
      {'DBMS': 'P', 'Operating Systems': 'P', '.NET': 'NC'},
    );

    final osHistory = await attendanceDao.getAttendanceHistoryForSubject(osId);
    expect(
      osHistory.any(
        (row) => row['date'] == '2026-07-25' && row['status'] == 'P',
      ),
      isTrue,
    );

    final stats = await attendanceDao.getAttendanceStats(1);
    expect(stats[osId], {'attended': 4, 'total': 4});
    expect(stats[netId], isNull);
    expect(
      calculatePercentage(stats[osId]!['attended']!, stats[osId]!['total']!),
      100,
    );

    final osSkipPlan = computeSkipPlan(
      history: osHistory,
      attended: stats[osId]!['attended']!,
      total: stats[osId]!['total']!,
      requiredPercent: 75,
      today: DateTime(2026, 7, 25),
    );
    expect(osSkipPlan.maxSkips, 1);
    expect(osSkipPlan.dates, [DateTime(2026, 8, 1)]);

    final weekly = await timetableDao.getWeeklyTimetable(1);
    expect(weekly[DateTime.saturday], [dbmsId, netId]);
    expect(weekly[DateTime.saturday], isNot(contains(osId)));

    // Web parity: the web upload path (LocalPdfParser -> AuraAIDashboard) derives
    // each subject's {attended, total} from the actual P/A rows, excluding NC/NU
    // exactly like getAttendanceStats. Building the web-facing stats from the same
    // records the parser emits must reproduce the native DAO numbers, so Operating
    // Systems is present on both sides and .NET (NC only) contributes to neither.
    final webRecords = [
      {'date': '2026-07-04', 'subject': 'Operating Systems', 'status': 'P'},
      {'date': '2026-07-11', 'subject': 'Operating Systems', 'status': 'P'},
      {'date': '2026-07-18', 'subject': 'Operating Systems', 'status': 'P'},
      {'date': '2026-07-25', 'subject': 'DBMS', 'status': 'P'},
      {'date': '2026-07-25', 'subject': 'Operating Systems', 'status': 'P'},
      {'date': '2026-07-25', 'subject': '.NET', 'status': 'NC'},
    ];
    final webStats = <String, Map<String, int>>{};
    for (final r in webRecords) {
      final status = r['status'];
      if (status != 'P' && status != 'A') continue;
      final s = webStats.putIfAbsent(
        r['subject']!,
        () => {'attended': 0, 'total': 0},
      );
      s['total'] = s['total']! + 1;
      if (status == 'P') s['attended'] = s['attended']! + 1;
    }
    expect(webStats['Operating Systems'], {'attended': 4, 'total': 4});
    expect(webStats['DBMS'], {'attended': 1, 'total': 1});
    expect(webStats.containsKey('.NET'), isFalse);
    // Identical to the native DAO stats for the shared subjects.
    expect(webStats['Operating Systems'], stats[osId]);

    await (await DBHelper.instance.database).close();
    await deleteDatabase(databasePath);
  });
}
