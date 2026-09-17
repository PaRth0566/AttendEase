import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/database/subject_dao.dart';
import 'package:attend_ease/services/attendance_report_sync_service.dart';
import 'package:attend_ease/services/local_pdf_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> initTestDb() async {
    DBHelper.databaseFileName = 'sync_routing_test.db';
    await DBHelper.resetForTest();
    await databaseFactory.deleteDatabase(
      '${await getDatabasesPath()}/${DBHelper.databaseFileName}',
    );
  }

  Map<String, dynamic> sampleFyjcReportData({String studentName = 'NEEL DOLIA'}) {
    return {
      'name': studentName,
      'year': '2026-2027',
      'course': 'H.S.C.- Commerce (MBC)',
      'semester': '',
      'semesterNumber': null,
      'collegeType': 'junior',
      'term': 'FYJC',
      'startDate': '2026-08-01',
      'endDate': '2026-09-01',
      'subjects': ['Book Keeping & Accountancy', 'Organisation of Commerce'],
      'attendanceRecords': [
        {
          'date': '2026-08-10',
          'subject': 'Book Keeping & Accountancy',
          'status': 'P',
        },
        {
          'date': '2026-08-11',
          'subject': 'Organisation of Commerce',
          'status': 'A',
        },
      ],
      'inferredTimetable': <String, dynamic>{},
    };
  }

  Map<String, dynamic> sampleSyjcReportData({String studentName = 'NEEL DOLIA'}) {
    return {
      'name': studentName,
      'year': '2026-2027',
      'course': 'H.S.C.- Commerce (MBC)',
      'semester': '',
      'semesterNumber': null,
      'collegeType': 'junior',
      'term': 'SYJC',
      'startDate': '2026-08-01',
      'endDate': '2026-09-01',
      'subjects': ['Secretarial Practice', 'Economics'],
      'attendanceRecords': [
        {
          'date': '2026-08-12',
          'subject': 'Secretarial Practice',
          'status': 'P',
        },
        {
          'date': '2026-08-13',
          'subject': 'Economics',
          'status': 'P',
        },
      ],
      'inferredTimetable': <String, dynamic>{},
    };
  }

  Map<String, dynamic> sampleDegreeReportData({
    required int semesterNumber,
    String studentName = 'PARTH MEHTA',
  }) {
    return {
      'name': studentName,
      'year': '2026-2027',
      'course': 'Bachelor of Science (Computer Science)',
      'semester': 'Semester $semesterNumber',
      'semesterNumber': semesterNumber,
      'collegeType': 'degree',
      'term': null,
      'startDate': '2026-06-01',
      'endDate': '2026-10-01',
      'subjects': ['Cloud Computing', 'Artificial Intelligence'],
      'attendanceRecords': [
        {
          'date': '2026-06-15',
          'subject': 'Cloud Computing',
          'status': 'P',
        },
      ],
      'inferredTimetable': <String, dynamic>{},
    };
  }

  group('Sync Report Period Routing Tests', () {
    const syncService = AttendanceReportSyncService();
    final subjectDao = SubjectDao();
    final attendanceDao = AttendanceDao();

    test('TEST 1: Current = Junior + SYJC, Upload = FYJC PDF -> routes to FYJC, SYJC unchanged', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'SYJC',
        'semester': 12,
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
      });

      final result = await syncService.applyDataForTesting(sampleFyjcReportData());

      expect(result, isNotNull);
      expect(result!.semester, 11);
      expect(result.term, 'FYJC');
      expect(result.collegeType, 'junior');

      // Verify FYJC subjects and attendance exist
      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      expect(fyjcSubjects.map((s) => s.name).toSet(), {
        'Book Keeping & Accountancy',
        'Organisation of Commerce',
      });
      final fyjcStats = await attendanceDao.getAttendanceStats(11);
      expect(fyjcStats.isNotEmpty, isTrue);

      // Verify SYJC (semester 12) remains completely untouched
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      expect(syjcSubjects, isEmpty);
      final syjcStats = await attendanceDao.getAttendanceStats(12);
      expect(syjcStats, isEmpty);

      // Verify preferences updated to FYJC
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('semester'), 11);
      expect(prefs.getString('term'), 'FYJC');
      expect(prefs.getString('junior_term_start_FYJC'), '2026-08-01');
      expect(prefs.getString('junior_term_end_FYJC'), '2026-09-01');
    });

    test('TEST 2: Current = Junior + FYJC, Upload = SYJC PDF -> routes to SYJC, FYJC unchanged', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'semester': 11,
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
      });

      final result = await syncService.applyDataForTesting(sampleSyjcReportData());

      expect(result, isNotNull);
      expect(result!.semester, 12);
      expect(result.term, 'SYJC');
      expect(result.collegeType, 'junior');

      // Verify SYJC subjects and attendance exist
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      expect(syjcSubjects.map((s) => s.name).toSet(), {
        'Secretarial Practice',
        'Economics',
      });
      final syjcStats = await attendanceDao.getAttendanceStats(12);
      expect(syjcStats.isNotEmpty, isTrue);

      // Verify FYJC (semester 11) remains completely untouched
      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      expect(fyjcSubjects, isEmpty);
      final fyjcStats = await attendanceDao.getAttendanceStats(11);
      expect(fyjcStats, isEmpty);

      // Verify preferences updated to SYJC
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('semester'), 12);
      expect(prefs.getString('term'), 'SYJC');
      expect(prefs.getString('junior_term_start_SYJC'), '2026-08-01');
      expect(prefs.getString('junior_term_end_SYJC'), '2026-09-01');
    });

    test('TEST 3: Current = Junior + SYJC, Upload = FYJC PDF twice -> no duplicate records', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'SYJC',
        'semester': 12,
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
      });

      // Upload FYJC first time
      await syncService.applyDataForTesting(sampleFyjcReportData());
      final firstStats = await attendanceDao.getAttendanceStats(11);

      // Upload FYJC second time
      await syncService.applyDataForTesting(sampleFyjcReportData());
      final secondStats = await attendanceDao.getAttendanceStats(11);

      // Ensure stats and record counts match exactly (no duplicates)
      expect(secondStats.length, firstStats.length);
      for (final subId in firstStats.keys) {
        expect(secondStats[subId]!['total'], firstStats[subId]!['total']);
        expect(secondStats[subId]!['attended'], firstStats[subId]!['attended']);
      }

      // SYJC remains untouched
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      expect(syjcSubjects, isEmpty);
    });

    test('TEST 4: Current = Degree + Sem 3, Upload = Degree Sem 5 report -> behaves exactly as existing Degree routing', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'degree',
        'semester': 3,
        'full_name': 'PARTH MEHTA',
        'course': 'Bachelor of Science (Computer Science)',
      });

      final result = await syncService.applyDataForTesting(
        sampleDegreeReportData(semesterNumber: 5),
      );

      expect(result, isNotNull);
      expect(result!.semester, 5);
      expect(result.collegeType, 'degree');
      expect(result.term, isNull);

      final sem5Subjects = await subjectDao.getSubjectsBySemester(5);
      expect(sem5Subjects.map((s) => s.name).toSet(), {
        'Cloud Computing',
        'Artificial Intelligence',
      });
      final sem3Subjects = await subjectDao.getSubjectsBySemester(3);
      expect(sem3Subjects, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('semester'), 5);
    });

    test('TEST 5: Upload an unknown/inconclusive report while in Junior College -> aborts safely and does not import into current term', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'SYJC',
        'semester': 12,
        'full_name': 'NEEL DOLIA',
      });

      final inconclusiveData = {
        'name': 'NEEL DOLIA',
        'year': '2026-2027',
        'course': 'Unknown Course',
        'semester': '',
        'semesterNumber': null,
        'collegeType': null,
        'term': null,
        'startDate': '2026-08-01',
        'endDate': '2026-09-01',
        'subjects': ['Mysterious Subject'],
        'attendanceRecords': [
          {'date': '2026-08-10', 'subject': 'Mysterious Subject', 'status': 'P'},
        ],
      };

      expect(
        () => syncService.applyDataForTesting(inconclusiveData),
        throwsA(isA<FormatException>()),
      );

      // Verify no records or subjects were imported into SYJC (12) or FYJC (11)
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      expect(syjcSubjects, isEmpty);
      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      expect(fyjcSubjects, isEmpty);
    });

    test('TEST 6: After importing FYJC while currently viewing SYJC: Open FYJC -> present, Open SYJC -> not present', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'SYJC',
        'semester': 12,
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
      });

      await syncService.applyDataForTesting(sampleFyjcReportData());

      // Open FYJC (semester 11)
      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      final fyjcStats = await attendanceDao.getAttendanceStats(11);
      expect(fyjcSubjects.isNotEmpty, isTrue);
      expect(fyjcStats.isNotEmpty, isTrue);

      // Open SYJC (semester 12)
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      final syjcStats = await attendanceDao.getAttendanceStats(12);
      expect(syjcSubjects, isEmpty);
      expect(syjcStats, isEmpty);
    });

    test('TEST 7: After importing SYJC while currently viewing FYJC: Open SYJC -> present, Open FYJC -> not present', () async {
      await initTestDb();
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'semester': 11,
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
      });

      await syncService.applyDataForTesting(sampleSyjcReportData());

      // Open SYJC (semester 12)
      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      final syjcStats = await attendanceDao.getAttendanceStats(12);
      expect(syjcSubjects.isNotEmpty, isTrue);
      expect(syjcStats.isNotEmpty, isTrue);

      // Open FYJC (semester 11)
      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      final fyjcStats = await attendanceDao.getAttendanceStats(11);
      expect(fyjcSubjects, isEmpty);
      expect(fyjcStats, isEmpty);
    });

    test('Actual PDF header text parsing yields junior collegeType and correct term', () {
      const fyjcHeaderText =
          'Page 1 of 8Attendance Report NEEL DOLIAStudent Name '
          '40104260737Student Number G018Roll No. '
          '2026-2027, F.Y.J.CAcademic Year & Academic Session '
          'H.S.C.- Commerce (MBC)Program Name '
          'From 01.08.2026 to 01.09.2026';

      const syjcHeaderText =
          'Page 1 of 8Attendance Report NEEL DOLIAStudent Name '
          '40104260737Student Number G018Roll No. '
          '2026-2027, S.Y.J.CAcademic Year & Academic Session '
          'H.S.C.- Commerce (MBC)Program Name '
          'From 01.08.2026 to 01.09.2026';

      expect(LocalPdfParser.detectCollegeType(fyjcHeaderText), 'junior');
      expect(LocalPdfParser.extractJuniorCollegeTerm(fyjcHeaderText), 'FYJC');

      expect(LocalPdfParser.detectCollegeType(syjcHeaderText), 'junior');
      expect(LocalPdfParser.extractJuniorCollegeTerm(syjcHeaderText), 'SYJC');
    });

    test('AttendanceReportSyncResult returns correct periodLabel for junior and degree', () {
      const jcResult = AttendanceReportSyncResult(
        semester: 11,
        term: 'FYJC',
        collegeType: 'junior',
      );
      expect(jcResult.periodLabel, 'FYJC');

      const degResult = AttendanceReportSyncResult(
        semester: 5,
        collegeType: 'degree',
      );
      expect(degResult.periodLabel, 'Sem 5');
    });
  });
}
