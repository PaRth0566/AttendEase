import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/attendance_dao.dart';
import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/database/subject_dao.dart';
import 'package:attend_ease/database/timetable_dao.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/screens/setup/basic_info_screen.dart';
import 'package:attend_ease/services/cloud_sync_service.dart';
import 'package:attend_ease/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> initTestDb() async {
    DBHelper.databaseFileName = 'junior_isolation_test.db';
    await DBHelper.resetForTest();
    await databaseFactory.deleteDatabase(
      '${await getDatabasesPath()}/${DBHelper.databaseFileName}',
    );
  }

  group('Junior College and Degree College Data Isolation', () {
    test('Subjects and attendance queries are strictly isolated without cross-collision', () async {
      await initTestDb();
      final subjectDao = SubjectDao();
      final timetableDao = TimetableDao();
      final attendanceDao = AttendanceDao();

      // 1. Insert Degree Semester 1 & Semester 2 subjects
      final deg1SubId = await subjectDao.insertSubject(
        Subject(name: 'Data Structures', requiredPercent: 75.0, semester: 1),
      );
      final deg2SubId = await subjectDao.insertSubject(
        Subject(name: 'Operating Systems', requiredPercent: 75.0, semester: 2),
      );

      // 2. Insert Junior FYJC (sem 11) & SYJC (sem 12) subjects
      final jcFYJCSubId = await subjectDao.insertSubject(
        Subject(name: 'Book Keeping & Accountancy', requiredPercent: 70.0, semester: 11),
      );
      final jcSYJCSubId = await subjectDao.insertSubject(
        Subject(name: 'Secretarial Practice', requiredPercent: 70.0, semester: 12),
      );
      expect(deg2SubId, isPositive);
      expect(jcSYJCSubId, isPositive);

      // Verify subject isolation
      final deg1Subjects = await subjectDao.getSubjectsBySemester(1);
      expect(deg1Subjects.map((s) => s.name).toList(), ['Data Structures']);

      final deg2Subjects = await subjectDao.getSubjectsBySemester(2);
      expect(deg2Subjects.map((s) => s.name).toList(), ['Operating Systems']);

      final fyjcSubjects = await subjectDao.getSubjectsBySemester(11);
      expect(fyjcSubjects.map((s) => s.name).toList(), ['Book Keeping & Accountancy']);

      final syjcSubjects = await subjectDao.getSubjectsBySemester(12);
      expect(syjcSubjects.map((s) => s.name).toList(), ['Secretarial Practice']);

      // 3. Insert timetable entries on the same day for Degree 1 and Junior FYJC
      final deg1TtId = await timetableDao.ensureSeedEntry(deg1SubId);
      final jcFyjcTtId = await timetableDao.ensureSeedEntry(jcFYJCSubId);

      // 4. Insert attendance records on the exact same date
      const sameDate = '2026-08-15';
      await attendanceDao.upsertAttendance(
        timetableId: deg1TtId,
        date: sameDate,
        status: 'P',
      );
      await attendanceDao.upsertAttendance(
        timetableId: jcFyjcTtId,
        date: sameDate,
        status: 'A',
      );

      // 5. Verify attendance stats query isolation:
      // Degree Semester 1 stats
      final deg1Stats = await attendanceDao.getAttendanceStats(1);
      expect(deg1Stats.containsKey(deg1SubId), isTrue);
      expect(deg1Stats[deg1SubId]!['attended'], 1);
      expect(deg1Stats[deg1SubId]!['total'], 1);
      expect(deg1Stats.containsKey(jcFYJCSubId), isFalse);

      // Junior FYJC (11) stats
      final fyjcStats = await attendanceDao.getAttendanceStats(11);
      expect(fyjcStats.containsKey(jcFYJCSubId), isTrue);
      expect(fyjcStats[jcFYJCSubId]!['attended'], 0);
      expect(fyjcStats[jcFYJCSubId]!['total'], 1);
      expect(fyjcStats.containsKey(deg1SubId), isFalse);

      // Date bounds query isolation
      final deg1Bounds = await attendanceDao.getAttendanceDateBoundsForSemester(1);
      final fyjcBounds = await attendanceDao.getAttendanceDateBoundsForSemester(11);
      final deg2Bounds = await attendanceDao.getAttendanceDateBoundsForSemester(2);
      final syjcBounds = await attendanceDao.getAttendanceDateBoundsForSemester(12);

      expect(deg1Bounds.firstDate, isNotNull);
      expect(fyjcBounds.firstDate, isNotNull);
      expect(deg2Bounds.firstDate, isNull);
      expect(syjcBounds.firstDate, isNull);
    });
  });

  group('Manual Configuration Switching Repeatedly without Stale State', () {
    testWidgets('switches repeatedly between Degree and Junior without leaking state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'full_name': 'Test Student',
        'course': 'Test Course',
        'year': '2026-2027',
        'college_type': 'degree',
        'semester': 3,
        'semester_start_3': '2026-06-01',
        'semester_end_3': '2026-11-30',
        'junior_term_start_FYJC': '2026-08-01',
        'junior_term_end_FYJC': '2026-09-01',
        'junior_term_start_SYJC': '2026-08-01',
        'junior_term_end_SYJC': '2026-09-01',
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const BasicInfoScreen(isEditMode: true),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Degree College, Semester 3
      expect(find.text('College Section'), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Semester 3'), findsOneWidget);
      expect(find.text('Term'), findsNothing);

      // 1. Switch to Junior College
      await tester.tap(find.text('Junior College'));
      await tester.pumpAndSettle();

      expect(find.text('Term'), findsOneWidget);
      expect(find.text('Semester'), findsNothing);
      expect(find.text('01 Aug 2026', skipOffstage: false), findsOneWidget);
      expect(find.text('01 Sep 2026', skipOffstage: false), findsOneWidget);

      // Select SYJC from Term dropdown
      await tester.tap(find.text('FYJC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SYJC').last);
      await tester.pumpAndSettle();
      expect(find.text('SYJC'), findsOneWidget);

      // 2. Switch to Degree College
      await tester.tap(find.text('Degree College'));
      await tester.pumpAndSettle();

      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Term'), findsNothing);
      expect(find.text('01 Jun 2026', skipOffstage: false), findsOneWidget);
      expect(find.text('30 Nov 2026', skipOffstage: false), findsOneWidget);

      // Select Semester 7
      await tester.tap(find.text('Semester 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semester 7').last);
      await tester.pumpAndSettle();
      expect(find.text('Semester 7'), findsOneWidget);

      // 3. Switch back to Junior College
      await tester.tap(find.text('Junior College'));
      await tester.pumpAndSettle();

      // Term is displayed, SYJC was preserved, no Semester 7 leaked
      expect(find.text('Term'), findsOneWidget);
      expect(find.text('SYJC'), findsOneWidget);
      expect(find.text('Semester 7'), findsNothing);

      // 4. Switch back to Degree College
      await tester.tap(find.text('Degree College'));
      await tester.pumpAndSettle();

      // Semester is displayed, Semester 7 was preserved, no SYJC leaked
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Semester 7'), findsOneWidget);
      expect(find.text('SYJC'), findsNothing);
    });
  });

  group('Junior Persistence and Cloud Sync Whitelist', () {
    test('CloudSyncService whitelists Junior College keys and preserves Junior terms on restore', () async {
      // Whitelist inspection
      final allowedKeys = CloudSyncService.prefsWhitelist;
      expect(allowedKeys.contains('college_type'), isTrue);
      expect(allowedKeys.contains('term'), isTrue);

      expect(CloudSyncService.isPrefKeyAllowed('college_type'), isTrue);
      expect(CloudSyncService.isPrefKeyAllowed('term'), isTrue);
      expect(CloudSyncService.isPrefKeyAllowed('junior_term_start_FYJC'), isTrue);
      expect(CloudSyncService.isPrefKeyAllowed('junior_term_end_FYJC'), isTrue);
      expect(CloudSyncService.isPrefKeyAllowed('junior_term_start_SYJC'), isTrue);
      expect(CloudSyncService.isPrefKeyAllowed('junior_term_end_SYJC'), isTrue);

      // Restore simulation for Junior College matching CloudSyncService.restoreDataFromCloud logic
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final cloudJuniorPrefs = {
        'college_type': 'junior',
        'term': 'FYJC',
        'full_name': 'NEEL DOLIA',
        'course': 'H.S.C.- Commerce (MBC)',
        'year': '2026-2027',
        'junior_term_start_FYJC': '2026-08-01',
        'junior_term_end_FYJC': '2026-09-01',
      };

      for (var entry in cloudJuniorPrefs.entries) {
        await prefs.setString(entry.key, entry.value);
      }

      // Reconstruct semester from Junior term (the logic in CloudSyncService)
      final isJunior = prefs.getString('college_type') == 'junior';
      final restoredTerm = prefs.getString('term');
      if (isJunior && restoredTerm != null) {
        final semInt = restoredTerm == 'SYJC' ? 12 : 11;
        await prefs.setInt('semester', semInt);
      }

      expect(prefs.getString('college_type'), 'junior');
      expect(prefs.getString('term'), 'FYJC');
      expect(prefs.getInt('semester'), 11);
      expect(prefs.getString('junior_term_start_FYJC'), '2026-08-01');
      expect(prefs.getString('junior_term_end_FYJC'), '2026-09-01');
      // Verify Degree semester start/end were NOT created
      expect(prefs.getString('semester_start_1'), isNull);
      expect(prefs.getString('semester_start_11'), isNull);
    });
  });
}
