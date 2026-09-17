import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/screens/report/report_screen.dart';
import 'package:attend_ease/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBHelper.databaseFileName = 'report_college_section_test.db';
    await DBHelper.resetForTest();
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await databaseFactory.deleteDatabase(path);
    await DBHelper.instance.database;
  });

  tearDownAll(() async {
    await DBHelper.resetForTest();
  });

  Future<void> settleAfterIo(WidgetTester tester, [int millis = 300]) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: millis)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ReportScreen renders Term and FYJC for Junior College', (tester) async {
    SharedPreferences.setMockInitialValues({
      'college_type': 'junior',
      'term': 'FYJC',
      'semester': 1,
      'junior_term_start_FYJC': '2026-08-01',
      'junior_term_end_FYJC': '2026-09-01',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ReportScreen(),
      ),
    );
    await settleAfterIo(tester);

    // Verify Radio displays 'Term' (not 'Semester')
    expect(find.text('Term'), findsOneWidget);
    // Verify prompt says 'Select Term: '
    expect(find.text('Select Term: '), findsOneWidget);
    // Verify button shows 'FYJC'
    expect(find.text('FYJC'), findsOneWidget);

    // Tap the picker button
    await tester.tap(find.text('FYJC'));
    await tester.pumpAndSettle();

    // Verify modal sheet title is 'Select Term'
    expect(find.text('Select Term'), findsOneWidget);
    // Verify options are FYJC and SYJC
    expect(find.text('SYJC'), findsOneWidget);

    // Pick SYJC
    await tester.tap(find.text('SYJC'));
    await settleAfterIo(tester);

    // Button should now show SYJC
    expect(find.text('SYJC'), findsOneWidget);
    await settleAfterIo(tester);
  });

  testWidgets('ReportScreen renders Semester and Semester 3 for Degree College', (tester) async {
    SharedPreferences.setMockInitialValues({
      'college_type': 'degree',
      'semester': 3,
      'semester_start_3': '2026-06-15',
      'semester_end_3': '2026-11-30',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ReportScreen(),
      ),
    );
    await settleAfterIo(tester);

    // Verify Radio displays 'Semester'
    expect(find.text('Semester'), findsOneWidget);
    // Verify prompt says 'Select Semester: '
    expect(find.text('Select Semester: '), findsOneWidget);
    // Verify button shows 'Semester 3'
    expect(find.text('Semester 3'), findsOneWidget);

    // Tap the picker button
    await tester.tap(find.text('Semester 3'));
    await tester.pumpAndSettle();

    // Verify modal sheet title is 'Select Semester'
    expect(find.text('Select Semester'), findsOneWidget);
    // Verify options include Semester 1..8
    expect(find.text('Semester 1'), findsOneWidget);
    expect(find.text('Semester 8'), findsOneWidget);

    // Pick Semester 5
    await tester.tap(find.text('Semester 5'));
    await settleAfterIo(tester);

    expect(find.text('Semester 5'), findsOneWidget);
    await settleAfterIo(tester);
  });

  testWidgets('ReportScreen does not silently default missing Junior term to FYJC and prompts on generate', (tester) async {
    SharedPreferences.setMockInitialValues({
      'college_type': 'junior',
      // 'term' is omitted!
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ReportScreen()),
      ),
    );
    await settleAfterIo(tester);

    // Button should show 'Select Term', NOT 'FYJC'
    expect(find.text('Select Term'), findsOneWidget);
    expect(find.text('FYJC'), findsNothing);

    // Attempting to generate report without selecting a term should show an error
    await tester.tap(find.text('Generate Report'));
    await tester.pumpAndSettle();
    expect(find.text('Please select a term before generating report'), findsOneWidget);

    // Select FYJC explicitly
    await tester.tap(find.text('Select Term'));
    await tester.pumpAndSettle();

    expect(find.text('Select Term'), findsWidgets); // title and/or sheet
    await tester.tap(find.text('FYJC'));
    await settleAfterIo(tester);

    // Now button shows 'FYJC'
    expect(find.text('FYJC'), findsOneWidget);
    await settleAfterIo(tester);
  });

  testWidgets('ReportScreen in Custom Dates requires explicit term selection before picking dates', (tester) async {
    SharedPreferences.setMockInitialValues({
      'college_type': 'junior',
      // 'term' is omitted!
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ReportScreen()),
      ),
    );
    await settleAfterIo(tester);

    // Switch to Custom Dates mode
    await tester.tap(find.text('Custom Dates'));
    await tester.pumpAndSettle();
    expect(find.text('Please select a term above to see available dates.'), findsOneWidget);

    // Attempting to pick date without selecting a term
    await tester.tap(find.text('Start Date'));
    await tester.pumpAndSettle();
    expect(find.text('Please select a term (FYJC or SYJC) first'), findsOneWidget);
    await settleAfterIo(tester);
  });
}

