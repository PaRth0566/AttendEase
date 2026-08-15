import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/database/subject_dao.dart';
import 'package:attend_ease/database/timetable_dao.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/models/timetable_entry.dart';
import 'package:attend_ease/services/local_data_reset_service.dart';
import 'package:attend_ease/services/pdf_attendance_import_service.dart';
import 'package:attend_ease/services/report_owner_check.dart';

/// Importing a report that belongs to somebody else used to *union* the two
/// courses: their subjects appeared beside yours on the dashboard and one
/// timetable was layered over the other, with no way back short of a reinstall.
///
/// The fix is two halves — notice that the report is not a continuation
/// ([ReportOwnerCheck]), and on the user's say-so wipe before importing
/// ([LocalDataResetService]). Both halves are asserted here, plus the union
/// itself as the regression guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  /// Course A: the data already in the app.
  const storedSubjects = ['Data Structures', 'Operating Systems'];

  /// Course B: a friend's report, sharing nothing with A.
  const reportSubjects = ['Financial Accounting', 'Business Law'];

  /// A clean private database. Test files run concurrently and would otherwise
  /// fight over the shared default name; the cached connection is dropped before
  /// the file goes, so DBHelper is never left pointing at a deleted database.
  Future<void> freshDatabase() async {
    DBHelper.databaseFileName = 'report_course_replacement_test.db';
    await DBHelper.resetForTest();
    final databasePath = p.join(
      await getDatabasesPath(),
      DBHelper.databaseFileName,
    );
    await deleteDatabase(databasePath);
  }

  /// Seeds course A: two subjects, a Monday timetable and a week of records.
  Future<List<int>> seedCourseA({int semester = 3}) async {
    final subjectDao = SubjectDao();
    final timetableDao = TimetableDao();
    final ids = <int>[];
    for (final name in storedSubjects) {
      ids.add(
        await subjectDao.insertSubject(
          Subject(name: name, requiredPercent: 75, semester: semester),
        ),
      );
    }
    for (var i = 0; i < ids.length; i++) {
      await timetableDao.insertEntry(
        TimetableEntry(
          dayOfWeek: DateTime.monday,
          subjectId: ids[i],
          lectureOrder: i,
        ),
      );
    }
    // Attendance hangs off the timetable, so it needs the seed slots the import
    // would otherwise create.
    final db = await DBHelper.instance.database;
    for (final id in ids) {
      final entryId = await timetableDao.ensureSeedEntry(id);
      await db.insert('attendance_records', {
        'timetable_entry_id': entryId,
        'date': '2026-07-06',
        'status': 'P',
        'source': 'pdf',
      });
    }
    return ids;
  }

  /// The parsed shape `LocalPdfParser` hands over, for course B.
  Map<String, dynamic> reportForCourseB() => {
    'name': 'RIYA SHARMA',
    'course': 'Bachelor of Commerce',
    'year': 'Second Year',
    'startDate': '2026-07-01',
    'endDate': '2026-07-08',
    'subjects': reportSubjects,
    'attendanceRecords': [
      {'date': '2026-07-01', 'subject': 'Financial Accounting', 'status': 'P'},
      {'date': '2026-07-01', 'subject': 'Business Law', 'status': 'A'},
      {'date': '2026-07-08', 'subject': 'Financial Accounting', 'status': 'P'},
      {'date': '2026-07-08', 'subject': 'Business Law', 'status': 'P'},
    ],
    'inferredTimetable': {
      '${DateTime.wednesday}': reportSubjects,
    },
  };

  group('ReportOwnerCheck', () {
    test('stays quiet for the same student\'s next report', () async {
      await freshDatabase();
      await seedCourseA();
      SharedPreferences.setMockInitialValues({
        'full_name': 'Parth Mehta',
        'course': 'Bachelor of Technology',
        'year': 'Second Year',
      });

      final mismatch = await ReportOwnerCheck().detect(
        targetSemester: 3,
        data: {
          // The name as SAP spells it — same person, different casing.
          'name': 'PARTH MEHTA',
          'course': 'Bachelor of Technology',
          'subjects': storedSubjects,
        },
      );

      expect(
        mismatch,
        isNull,
        reason: 'a routine sync must not offer to wipe the app',
      );
    });

    test('flags a different student, with the counts filled in', () async {
      await freshDatabase();
      await seedCourseA();
      SharedPreferences.setMockInitialValues({
        'full_name': 'Parth Mehta',
        'course': 'Bachelor of Technology',
        'year': 'Second Year',
      });

      final mismatch = await ReportOwnerCheck().detect(
        targetSemester: 3,
        data: reportForCourseB(),
      );

      expect(mismatch, isNotNull);
      expect(mismatch!.differentStudent, isTrue);
      expect(mismatch.storedName, 'Parth Mehta');
      expect(mismatch.reportName, 'RIYA SHARMA');
      // What the dialog quotes back to the user.
      expect(mismatch.storedSubjectCount, storedSubjects.length);
      expect(mismatch.reportSubjectCount, reportSubjects.length);
      expect(mismatch.semester, 3);
    });

    test('stays quiet on an empty database — the setup path', () async {
      await freshDatabase();
      SharedPreferences.setMockInitialValues({
        'full_name': 'Parth Mehta',
        'course': 'Bachelor of Technology',
      });

      final mismatch = await ReportOwnerCheck().detect(
        targetSemester: 1,
        data: reportForCourseB(),
      );

      expect(
        mismatch,
        isNull,
        reason: 'there is nothing to overwrite during onboarding',
      );
    });

    test(
      'a renamed course alone is not enough when the subjects still match',
      () async {
        await freshDatabase();
        await seedCourseA();
        SharedPreferences.setMockInitialValues({
          // What a student typed by hand at setup; the report spells it in full.
          'full_name': 'Parth Mehta',
          'course': 'BTech IT',
        });

        final mismatch = await ReportOwnerCheck().detect(
          targetSemester: 3,
          data: {
            'name': 'Parth Mehta',
            'course': 'Bachelor of Technology (Information Technology)',
            'subjects': storedSubjects,
          },
        );

        expect(
          mismatch,
          isNull,
          reason: 'the curriculum lines up, so it is the same course',
        );
      },
    );
  });

  group('replacing one course with another', () {
    test('the reset leaves nothing of the old course behind', () async {
      await freshDatabase();
      await seedCourseA();
      SharedPreferences.setMockInitialValues({
        'full_name': 'Parth Mehta',
        'course': 'Bachelor of Technology',
        'year': 'Second Year',
        'semester': 3,
        'semester_start_3': '2026-06-01',
        'semester_end_3': '2026-10-31',
        // Device preferences, which the swap must not touch.
        'overall_required_attendance': 80.0,
        'is_setup_complete': true,
      });

      await const LocalDataResetService().clearAllAcademicData();

      final db = await DBHelper.instance.database;
      for (final table in [
        'subjects',
        'timetable',
        'attendance_records',
        'imported_report_dates',
      ]) {
        expect(
          await db.query(table),
          isEmpty,
          reason: '$table must be emptied by the reset',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'full_name',
        'course',
        'year',
        'semester',
        'semester_start_3',
        'semester_end_3',
      ]) {
        expect(
          prefs.get(key),
          isNull,
          reason: '$key is re-derived from the incoming report',
        );
      }
      // The thresholds and the completed-setup flag belong to the device, not to
      // the report — a student swapping reports is not re-onboarding.
      expect(prefs.getDouble('overall_required_attendance'), 80.0);
      expect(prefs.getBool('is_setup_complete'), isTrue);
    });

    test('after the reset, the import carries only the new course', () async {
      await freshDatabase();
      await seedCourseA();
      SharedPreferences.setMockInitialValues({});

      await const LocalDataResetService().clearAllAcademicData();
      await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
        data: reportForCourseB(),
        semester: 3,
      );

      final subjects = await SubjectDao().getAllSubjects();
      expect(
        subjects.map((s) => s.name).toSet(),
        reportSubjects.toSet(),
        reason: "only the new report's subjects may survive the replacement",
      );

      // The timetable is re-inferred rather than left layered over the old one:
      // course A ran on Monday, course B runs on Wednesday.
      final weekly = await TimetableDao().getWeeklyTimetable(3);
      expect(weekly.keys, [DateTime.wednesday]);
      expect(weekly[DateTime.wednesday], hasLength(reportSubjects.length));

      // Course A's 2026-07-06 rows are gone — and not merely hidden by the
      // import's date-range delete, which would not have reached a subject that
      // no longer exists.
      final db = await DBHelper.instance.database;
      final dates = await db.rawQuery(
        'SELECT DISTINCT substr(date, 1, 10) AS d FROM attendance_records '
        'ORDER BY d',
      );
      expect(
        dates.map((row) => row['d']).toList(),
        ['2026-07-01', '2026-07-08'],
        reason: "no record of the old course's week may remain",
      );
    });

    test(
      'REGRESSION: importing without the reset unions the two courses',
      () async {
        // The bug, pinned. If this ever stops producing four subjects, the
        // import has changed shape and the reset above may no longer be what
        // keeps the two courses apart.
        await freshDatabase();
        await seedCourseA();
        SharedPreferences.setMockInitialValues({});

        await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
          data: reportForCourseB(),
          semester: 3,
        );

        final subjects = await SubjectDao().getAllSubjects();
        expect(
          subjects.map((s) => s.name).toSet(),
          {...storedSubjects, ...reportSubjects},
          reason: 'the import merges by design — the reset is what prevents it',
        );
      },
    );
  });
}
