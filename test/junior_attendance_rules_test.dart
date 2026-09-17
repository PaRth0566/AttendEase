import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/screens/dashboard/dashboard_screen.dart';
import 'package:attend_ease/screens/report/report_screen.dart';
import 'package:attend_ease/screens/report/subject_detail_screen.dart';
import 'package:attend_ease/screens/setup/attendance_criteria_screen.dart';
import 'package:attend_ease/services/attendance_preferences_service.dart';
import 'package:attend_ease/services/attendance_report_pdf.dart';
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/utils/calculation_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Junior Attendance Rules - Overall Compliance & Skip Math', () {
    test('Junior overall target defaults to 75%', () {
      expect(AttendancePreferencesService.defaultOverall, 75.0);
    });

    test('Degree per-subject target default remains 70%', () {
      expect(AttendancePreferencesService.defaultSubject, 70.0);
    });

    test('Junior overall attendance compliance threshold: 75%', () {
      bool isJuniorOnTrack(int attended, int total, [double req = 75.0]) {
        if (total == 0) return true;
        final pct = (attended / total) * 100;
        return pct >= req - 1e-9;
      }

      // 74.9% is below requirement
      expect(isJuniorOnTrack(749, 1000), isFalse);
      // 75.0% is on track
      expect(isJuniorOnTrack(75, 100), isTrue);
      // 75.1% is on track
      expect(isJuniorOnTrack(751, 1000), isTrue);
      // 0 conducted lectures handled gracefully
      expect(isJuniorOnTrack(0, 0), isTrue);
    });

    test('Junior overall max skips formula: floor(P / R - T)', () {
      int juniorMaxSkips(int present, int total, [double reqPercent = 75.0]) {
        final reqFrac = reqPercent / 100.0;
        if (total == 0 || reqFrac <= 0) return 0;
        final skips = ((present / reqFrac) - total).floor();
        return skips < 0 ? 0 : skips;
      }

      // Present = 105, Total = 139, Req = 75%
      // 105 / 0.75 - 139 = 140 - 139 = 1 skip
      // 105 / 140 = 75.0% (still >= 75%)
      // 105 / 141 = 74.46% (< 75%)
      expect(juniorMaxSkips(105, 139, 75.0), 1);

      // Present = 80, Total = 100, Req = 75%
      // 80 / 0.75 = 106.666 -> floor(106.666 - 100) = 6 skips
      // 80 / 106 = 75.47%, 80 / 107 = 74.76%
      expect(juniorMaxSkips(80, 100, 75.0), 6);

      // When attendance < 75%, skips = 0
      expect(juniorMaxSkips(74, 100, 75.0), 0);
    });

    test('Junior overall recovery formula: ceil((R * T - P) / (1 - R))', () {
      int juniorRecoveryLectures(int present, int total, [double reqPercent = 75.0]) {
        final reqFrac = reqPercent / 100.0;
        if (total == 0 || reqFrac >= 1.0) return 0;
        final currentPct = (present / total) * 100.0;
        if (currentPct >= reqPercent - 1e-9) return 0;
        final needed = (((reqFrac * total) - present) / (1.0 - reqFrac)).ceil();
        return needed < 0 ? 0 : needed;
      }

      // Present = 70, Total = 100, Req = 75%
      // (0.75 * 100 - 70) / (1 - 0.75) = (75 - 70) / 0.25 = 5 / 0.25 = 20 lectures
      // After attending 20: 90 / 120 = 75.0%
      expect(juniorRecoveryLectures(70, 100, 75.0), 20);

      // Present = 89, Total = 121, Req = 75%
      // R * T = 0.75 * 121 = 90.75. 90.75 - 89 = 1.75.
      // 1.75 / 0.25 = 7 lectures.
      // After attending 7: (89 + 7) / (121 + 7) = 96 / 128 = 75.0%
      expect(juniorRecoveryLectures(89, 121, 75.0), 7);

      // Already above requirement -> 0
      expect(juniorRecoveryLectures(75, 100, 75.0), 0);
      expect(juniorRecoveryLectures(80, 100, 75.0), 0);
    });
  });

  group('Junior Weekly Simulator vs Degree Weekly Simulator', () {
    test('Junior weekly planner ignores low subject percentage if overall holds >= 75%', () {
      // Sub 1 has low attendance (e.g. 50%), but overall is 85%
      // On Saturday, missing a lecture of Sub 1:
      // In Degree mode: Sub 1 was < 70%, so skipping Sub 1 is BLOCKED (breach).
      // In Junior mode: Sub 1 has no threshold, and overall is 85% -> safely skippable!
      final today = DateTime(2026, 7, 20); // Monday

      // Create history on Tuesdays for sub 1 and sub 2
      final tuesday1 = '2026-07-07';
      final tuesday2 = '2026-07-14';

      final history = {
        1: [
          {'date': tuesday1, 'status': 'P'},
          {'date': tuesday2, 'status': 'P'},
        ],
        2: [
          {'date': tuesday1, 'status': 'P'},
          {'date': tuesday2, 'status': 'P'},
        ],
      };

      // Sub 1: 5 attended, 10 total (50%) -> below 70%
      // Sub 2: 90 attended, 90 total (100%)
      // Overall: 95 attended / 100 total = 95%
      // Missing Tuesday (1 lecture of sub 1 and 1 of sub 2):
      // Sub 1 becomes 5/11 (45.45%), Sub 2 becomes 90/91 (98.9%)
      // Overall becomes 95/102 = 93.13% >= 75%
      final stats = {
        1: {'attended': 5, 'total': 10},
        2: {'attended': 90, 'total': 90},
      };

      // Degree mode (isJunior = false):
      // Sub 1 is below 70%, so firstBreach returns 1 (subject breach)
      final degreePlan = computeWeekSkipPlan(
        subjectStats: stats,
        subjectRequired: {1: 70.0, 2: 70.0},
        subjectHistory: history,
        overallRequired: 75.0,
        today: today,
        isJunior: false,
      );
      expect(degreePlan, isNotNull);
      final degreeTuesday = degreePlan!.days.firstWhere(
        (d) => d.date.weekday == DateTime.tuesday,
      );
      expect(
        degreeTuesday.verdict,
        SkipVerdict.unsafe,
        reason: 'Degree blocks because Sub 1 < 70%',
      );
      expect(degreeTuesday.blockingSubjectId, 1);

      // Junior mode (isJunior = true):
      // Sub 1 has NO subject threshold; overall 93.13% >= 75%, so Tuesday IS SAFE!
      final juniorPlan = computeWeekSkipPlan(
        subjectStats: stats,
        subjectRequired: {1: 70.0, 2: 70.0},
        subjectHistory: history,
        overallRequired: 75.0,
        today: today,
        isJunior: true,
      );
      expect(juniorPlan, isNotNull);
      final juniorTuesday = juniorPlan!.days.firstWhere(
        (d) => d.date.weekday == DateTime.tuesday,
      );
      expect(
        juniorTuesday.verdict,
        SkipVerdict.skippable,
        reason: 'Junior only checks overall >= 75%',
      );
      expect(juniorTuesday.blockingSubjectId, isNull);
    });

    test('Junior weekly planner BLOCKS day when overall projected drops below 75%', () {
      final today = DateTime(2026, 7, 20); // Monday
      final tuesday1 = '2026-07-07';
      final tuesday2 = '2026-07-14';

      final history = {
        1: [
          {'date': tuesday1, 'status': 'P'},
          {'date': tuesday2, 'status': 'P'},
        ],
      };

      // Sub 1: 75 attended, 100 total = 75.0%
      // Missing 1 lecture drops overall to 75/101 = 74.25% < 75%
      final stats = {
        1: {'attended': 75, 'total': 100},
      };

      final juniorPlan = computeWeekSkipPlan(
        subjectStats: stats,
        subjectRequired: {1: 70.0},
        subjectHistory: history,
        overallRequired: 75.0,
        today: today,
        isJunior: true,
      );

      expect(juniorPlan, isNotNull);
      final juniorTuesday = juniorPlan!.days.firstWhere(
        (d) => d.date.weekday == DateTime.tuesday,
      );
      expect(juniorTuesday.verdict, SkipVerdict.unsafe);
      expect(juniorTuesday.blockingSubjectId, isNull, reason: 'Overall breach has no specific subject id');
    });
  });

  group('Junior PDF Report vs Degree PDF Report', () {
    test('buildAttendanceReportPdf generates valid PDF with Junior rules for FYJC', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Term',
          periodLabel: 'FYJC',
          semester: 11,
          studentName: 'NEEL DOLIA',
          course: 'H.S.C.- Commerce (MBC)',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: DateTime(2026, 8, 31),
        ),
        rows: const [
          ReportSubjectRow(
            name: 'Economics COM DIV G',
            attended: 12,
            total: 22,
            requiredPercent: 70, // Informational only in DB, ignored in Junior PDF
          ),
          ReportSubjectRow(
            name: 'Mathematics & Statistics P COM DIV G',
            attended: 4,
            total: 6,
            requiredPercent: 70,
          ),
          ReportSubjectRow(
            name: 'Organization of Commerce G',
            attended: 13,
            total: 18,
            requiredPercent: 70,
          ),
        ],
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('buildAttendanceReportPdf generates valid PDF with Junior rules for custom date range', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'junior',
          term: 'FYJC',
          periodKind: 'Date range',
          periodLabel: '4 Aug 2026 – 31 Aug 2026',
          semester: 11,
          studentName: 'NEEL DOLIA',
          course: 'H.S.C.- Commerce (MBC)',
          year: '2026-2027',
          overallRequiredPercent: 75.0,
          generatedAt: DateTime(2026, 8, 31),
        ),
        rows: const [
          ReportSubjectRow(
            name: 'Economics',
            attended: 10,
            total: 19,
            requiredPercent: 70,
          ),
          ReportSubjectRow(
            name: 'Mathematics & Statistics',
            attended: 4,
            total: 6,
            requiredPercent: 70,
          ),
        ],
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('Degree PDF report remains completely functional and preserves 70% subject targets', () async {
      final bytes = await buildAttendanceReportPdf(
        meta: ReportMeta(
          collegeType: 'degree',
          periodKind: 'Semester',
          periodLabel: 'Semester 5',
          semester: 5,
          studentName: 'Degree Student',
          course: 'B.Tech CS',
          year: 'Third Year',
          generatedAt: DateTime(2026, 8, 31),
        ),
        rows: const [
          ReportSubjectRow(
            name: 'DBMS',
            attended: 18,
            total: 20,
            requiredPercent: 70,
          ),
          ReportSubjectRow(
            name: 'Computer Networks',
            attended: 10,
            total: 20,
            requiredPercent: 70,
          ),
        ],
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('AttendanceCriteriaScreen UI - Junior vs Degree', () {
    testWidgets('Junior College hides per-subject attendance requirement field', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'overall_required_attendance': 75.0,
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AttendanceCriteriaScreen(isEditMode: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overall Attendance Required (%)'), findsOneWidget);
      expect(find.text('Minimum Attendance Per Subject (%)'), findsNothing);
      expect(
        find.text('Default requirement is 75% overall — edit it to match your college requirements.'),
        findsOneWidget,
      );
    });

    testWidgets('Degree College shows both overall and per-subject attendance fields', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'degree',
        'semester': 1,
        'overall_required_attendance': 75.0,
        'subject_required_attendance': 70.0,
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AttendanceCriteriaScreen(isEditMode: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overall Attendance Required (%)'), findsOneWidget);
      expect(find.text('Minimum Attendance Per Subject (%)'), findsOneWidget);
      expect(
        find.text('Default values are pre-filled — edit them to match your college requirements.'),
        findsOneWidget,
      );
    });
  });

  group('SubjectDetailScreen UI - Junior vs Degree', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    testWidgets('Junior College suppresses subject requirement text and safe-to-skip card', (tester) async {
      await tester.runAsync(() async {
        DBHelper.databaseFileName = 'junior_subj_detail_test.db';
        await DBHelper.resetForTest();
        await databaseFactory.deleteDatabase(
          '${await getDatabasesPath()}/${DBHelper.databaseFileName}',
        );
        await DBHelper.instance.database;
      });

      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
      });

      final subject = Subject(
        id: 101,
        name: 'Economics',
        requiredPercent: 70.0,
        semester: 11,
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: SubjectDetailScreen(subject: subject),
          ),
        );
        for (
          var i = 0;
          i < 120 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();

      // Subject name and attendance are shown
      expect(find.text('Economics'), findsWidgets);
      // 'Required: 70.0%' should NOT be shown for Junior
      expect(find.text('Required: 70.0%'), findsNothing);
      expect(find.text('Required: 70%'), findsNothing);
      // 'Safe to Skip' card should NOT be shown
      expect(find.text('Safe to Skip'), findsNothing);
    });

    tearDown(() async {
      await DBHelper.resetForTest();
    });
  });

  group('Junior Dashboard UI - Overall Status Ring and Visuals', () {
    final juniorSubjects = [
      Subject(id: 1, name: 'Economics COM DIV G', semester: 11, requiredPercent: 70.0),
      Subject(id: 2, name: 'Mathematics & Statistics P COM DIV G', semester: 11, requiredPercent: 70.0),
    ];

    testWidgets('>= 75% overall displays green ring, green Target: 75.0%, green subject bars, no badges', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'overall_required_attendance': 75.0,
      });

      // 76/100 = 76.0% overall (>= 75%)
      final stats = {
        1: {'attended': 40, 'total': 50}, // 80%
        2: {'attended': 36, 'total': 50}, // 72%
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DashboardScreen(
            overrideSubjects: juniorSubjects,
            overrideStats: stats,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Target text shows 75.0%
      expect(find.text('Target: 75.0%'), findsOneWidget);
      // Verify Overall percentage
      expect(find.text('76.0%'), findsOneWidget);

      // Checkmark icon shown for >= 75%
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Check color of target text is success green (0xFF358D3E)
      final targetText = tester.widget<Text>(find.text('Target: 75.0%'));
      expect(targetText.style?.color, const Color(0xFF358D3E));

      // Check ring indicator has success green color
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(of: find.byType(Stack), matching: find.byType(CircularProgressIndicator)),
      );
      expect(ring.color, const Color(0xFF358D3E));

      // All Junior subject progress bars are GREEN (0xFF49AD4F), matching overall status
      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressBars.length, greaterThanOrEqualTo(2));
      for (final pb in progressBars) {
        expect(pb.color, const Color(0xFF49AD4F));
      }

      // No Safe or Risk badges for Junior
      expect(find.text('Safe'), findsNothing);
      expect(find.text('Risk'), findsNothing);

      // Subject percentages are displayed
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('72.0%'), findsOneWidget);

      // Subject lecture counts are displayed
      expect(find.text('40/50 lectures'), findsOneWidget);
      expect(find.text('36/50 lectures'), findsOneWidget);

      // No per-subject target, skip, or recovery messages
      expect(find.textContaining('Required:'), findsNothing);
      expect(find.textContaining('Can skip'), findsNothing);
      expect(find.textContaining('Attend next'), findsNothing);
    });

    testWidgets('< 75% overall displays red ring, red Target: 75.0%, red subject bars, no badges', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'overall_required_attendance': 75.0,
      });

      // 68/100 = 68.0% overall (< 75%)
      final stats = {
        1: {'attended': 30, 'total': 50}, // 60.0%
        2: {'attended': 38, 'total': 50}, // 76.0%
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DashboardScreen(
            overrideSubjects: juniorSubjects,
            overrideStats: stats,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Target text shows 75.0%
      expect(find.text('Target: 75.0%'), findsOneWidget);
      // Verify Overall percentage
      expect(find.text('68.0%'), findsOneWidget);

      // Close (cross) icon shown for < 75%
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      // Check color of target text is danger red (0xFFF34032)
      final targetText = tester.widget<Text>(find.text('Target: 75.0%'));
      expect(targetText.style?.color, const Color(0xFFF34032));

      // Check ring indicator has danger red color
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(of: find.byType(Stack), matching: find.byType(CircularProgressIndicator)),
      );
      expect(ring.color, const Color(0xFFF34032));

      // All Junior subject progress bars are RED (0xFFF14134), matching overall status
      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressBars.length, greaterThanOrEqualTo(2));
      for (final pb in progressBars) {
        expect(pb.color, const Color(0xFFF14134));
      }

      // No Safe or Risk badges for Junior
      expect(find.text('Safe'), findsNothing);
      expect(find.text('Risk'), findsNothing);

      // Subject percentages are displayed
      expect(find.text('60.0%'), findsOneWidget);
      expect(find.text('76.0%'), findsOneWidget);

      // Subject lecture counts are displayed
      expect(find.text('30/50 lectures'), findsOneWidget);
      expect(find.text('38/50 lectures'), findsOneWidget);

      // No per-subject target, skip, or recovery messages
      expect(find.textContaining('Required:'), findsNothing);
      expect(find.textContaining('Can skip'), findsNothing);
      expect(find.textContaining('Attend next'), findsNothing);
    });

    testWidgets('Degree dashboard subject bars use per-subject color logic, not overall status', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'degree',
        'semester': 1,
        'overall_required_attendance': 75.0,
        'subject_required_attendance': 70.0,
      });

      final degreeSubjects = [
        Subject(id: 1, name: 'Data Structures', semester: 1, requiredPercent: 70.0),
        Subject(id: 2, name: 'Algorithms', semester: 1, requiredPercent: 70.0),
      ];

      // Overall = 76/100 = 76% (>= 75%), but subject 1 is below 70%
      final stats = {
        1: {'attended': 30, 'total': 50}, // 60% — below 70% → red bar
        2: {'attended': 40, 'total': 50}, // 80% — above 70% → green bar
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DashboardScreen(
            overrideSubjects: degreeSubjects,
            overrideStats: stats,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Degree shows per-subject Safe/Risk badges
      expect(find.text('Safe'), findsOneWidget);
      expect(find.text('Risk'), findsOneWidget);

      // Find all LinearProgressIndicators
      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(progressBars.length, greaterThanOrEqualTo(2));

      // Subject bars should have mixed colors: one red, one green
      final colors = progressBars.map((pb) => pb.color).toSet();
      expect(colors.contains(const Color(0xFF49AD4F)), isTrue,
          reason: 'Degree safe subject should have green bar');
      expect(colors.contains(const Color(0xFFF14134)), isTrue,
          reason: 'Degree at-risk subject should have red bar');
    });
  });

  group('Junior Report UI - Subject Progress Bar Colors and Visuals', () {
    final juniorSubjects = [
      Subject(id: 1, name: 'Economics COM DIV G', semester: 11, requiredPercent: 70.0),
      Subject(id: 2, name: 'Mathematics & Statistics P COM DIV G', semester: 11, requiredPercent: 70.0),
    ];

    testWidgets('Junior Report overall >= 75% displays green overall text, all green subject bars, no badges', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'overall_required_attendance': 75.0,
      });

      // Overall: 76/100 = 76.0% (>= 75%)
      // Sub 1: 30/50 = 60.0% (even though < 75%, bar must be GREEN because overall is >= 75%)
      // Sub 2: 46/50 = 92.0%
      final stats = {
        1: {'attended': 30, 'total': 50},
        2: {'attended': 46, 'total': 50},
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ReportScreen(
              overrideSubjects: juniorSubjects,
              overrideStats: stats,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overall percentage is shown and styled as success green
      expect(find.text('76.00%'), findsOneWidget);
      final overallText = tester.widget<Text>(find.text('76.00%'));
      expect(overallText.style?.color, const Color(0xFF358D3E));

      // Subject percentages are displayed
      expect(find.text('60.00%'), findsOneWidget);
      expect(find.text('92.00%'), findsOneWidget);

      // All Junior subject progress bars on Report are GREEN (0xFF49AD4F)
      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(progressBars.length, equals(2));
      for (final pb in progressBars) {
        expect(pb.color, const Color(0xFF49AD4F));
      }

      // No Safe/Risk badges on Junior Report
      expect(find.text('Safe'), findsNothing);
      expect(find.text('Risk'), findsNothing);
    });

    testWidgets('Junior Report overall < 75% displays red overall text, all red subject bars, no badges', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
        'overall_required_attendance': 75.0,
      });

      // Overall: 68/100 = 68.0% (< 75%)
      // Sub 1: 28/50 = 56.0%
      // Sub 2: 40/50 = 80.0% (even though >= 75%, bar must be RED because overall is < 75%)
      final stats = {
        1: {'attended': 28, 'total': 50},
        2: {'attended': 40, 'total': 50},
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ReportScreen(
              overrideSubjects: juniorSubjects,
              overrideStats: stats,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overall percentage is shown and styled as danger red
      expect(find.text('68.00%'), findsOneWidget);
      final overallText = tester.widget<Text>(find.text('68.00%'));
      expect(overallText.style?.color, const Color(0xFFF34032));

      // Subject percentages are displayed
      expect(find.text('56.00%'), findsOneWidget);
      expect(find.text('80.00%'), findsOneWidget);

      // All Junior subject progress bars on Report are RED (0xFFF14134)
      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(progressBars.length, equals(2));
      for (final pb in progressBars) {
        expect(pb.color, const Color(0xFFF14134));
      }

      // No Safe/Risk badges on Junior Report
      expect(find.text('Safe'), findsNothing);
      expect(find.text('Risk'), findsNothing);
    });

    testWidgets('Degree Report subject bars retain per-subject compliance logic', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'degree',
        'semester': 1,
        'overall_required_attendance': 75.0,
        'subject_required_attendance': 70.0,
      });

      final degreeSubjects = [
        Subject(id: 1, name: 'Data Structures', semester: 1, requiredPercent: 70.0),
        Subject(id: 2, name: 'Algorithms', semester: 1, requiredPercent: 70.0),
      ];

      // Overall: 75/100 = 75.0%, but Sub 1 is 60% (< 70%) and Sub 2 is 90% (>= 70%)
      final stats = {
        1: {'attended': 30, 'total': 50},
        2: {'attended': 45, 'total': 50},
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ReportScreen(
              overrideSubjects: degreeSubjects,
              overrideStats: stats,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final progressBars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(progressBars.length, equals(2));
      final colors = progressBars.map((pb) => pb.color).toSet();
      expect(colors.contains(const Color(0xFF49AD4F)), isTrue, reason: 'Degree safe subject has green bar');
      expect(colors.contains(const Color(0xFFF14134)), isTrue, reason: 'Degree at-risk subject has red bar');
    });
  });

  group('Junior Analytics (SubjectDetailScreen) UI - Subject Progress Bar Colors', () {
    testWidgets('Junior SubjectDetailScreen with overall >= 75% shows green bar even if subject < 75%', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
      });

      final subject = Subject(
        id: 101,
        name: 'Economics',
        requiredPercent: 70.0,
        semester: 11,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SubjectDetailScreen(
            subject: subject,
            collegeType: 'junior',
            juniorOverallSafe: true, // Term overall is >= 75%
            overrideAttended: 30,
            overrideTotal: 50, // 60.0% (< 75%, yet bar is GREEN!)
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find LinearProgressIndicator
      final progressBar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressBar.color, const Color(0xFF49AD4F));

      // Suppresses Required: 70% and Safe to Skip
      expect(find.textContaining('Required:'), findsNothing);
      expect(find.text('Safe to Skip'), findsNothing);
    });

    testWidgets('Junior SubjectDetailScreen with overall < 75% shows red bar even if subject >= 75%', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'junior',
        'term': 'FYJC',
      });

      final subject = Subject(
        id: 101,
        name: 'Economics',
        requiredPercent: 70.0,
        semester: 11,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SubjectDetailScreen(
            subject: subject,
            collegeType: 'junior',
            juniorOverallSafe: false, // Term overall is < 75%
            overrideAttended: 40,
            overrideTotal: 50, // 80.0% (>= 75%, yet bar is RED!)
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find LinearProgressIndicator
      final progressBar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressBar.color, const Color(0xFFF14134));

      // Suppresses Required: 70% and Safe to Skip
      expect(find.textContaining('Required:'), findsNothing);
      expect(find.text('Safe to Skip'), findsNothing);
    });

    testWidgets('Degree SubjectDetailScreen subject bar uses per-subject compliance', (tester) async {
      SharedPreferences.setMockInitialValues({
        'college_type': 'degree',
        'semester': 1,
      });

      final safeSubject = Subject(
        id: 101,
        name: 'Data Structures',
        requiredPercent: 70.0,
        semester: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SubjectDetailScreen(
            subject: safeSubject,
            collegeType: 'degree',
            overrideAttended: 40,
            overrideTotal: 50, // 80% >= 70% -> safe
          ),
        ),
      );
      await tester.pumpAndSettle();

      final progressBarSafe = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressBarSafe.color, const Color(0xFF358D3E)); // c.success
    });
  });
}

