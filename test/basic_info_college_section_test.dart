import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attend_ease/screens/setup/basic_info_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createWidget({Map<String, dynamic>? prefilledData, bool isEditMode = false}) {
    return MaterialApp(
      home: BasicInfoScreen(
        isEditMode: isEditMode,
        prefilledData: prefilledData,
      ),
    );
  }

  group('BasicInfoScreen - College Section and Period', () {
    testWidgets('auto-selects Junior College and Term when report is from Junior College', (tester) async {
      await tester.pumpWidget(
        createWidget(
          prefilledData: {
            'name': 'NEEL DOLIA',
            'course': 'H.S.C.- Commerce (MBC)',
            'year': '2026-2027',
            'collegeType': 'junior',
            'term': 'FYJC',
            'startDate': '2026-08-01',
            'endDate': '2026-09-01',
          },
        ),
      );
      await tester.pumpAndSettle();

      // Verify Name, Course, Year
      expect(find.text('NEEL DOLIA'), findsOneWidget);
      expect(find.text('H.S.C.- Commerce (MBC)'), findsOneWidget);
      expect(find.text('2026-2027'), findsOneWidget);

      // Verify College Section exists and Junior College is selected
      expect(find.text('College Section'), findsOneWidget);
      expect(find.text('Junior College'), findsOneWidget);
      expect(find.text('Degree College'), findsOneWidget);

      // Verify Term field exists with FYJC
      expect(find.text('Term'), findsOneWidget);
      expect(find.text('FYJC'), findsOneWidget);
      expect(find.text('Detected from your report'), findsOneWidget);

      // Verify date values
      expect(find.text('01 Aug 2026'), findsOneWidget);
      expect(find.text('01 Sep 2026'), findsOneWidget);
    });

    testWidgets('auto-selects Junior College and Term when report is S.Y.J.C', (tester) async {
      await tester.pumpWidget(
        createWidget(
          prefilledData: {
            'name': 'NEEL DOLIA',
            'course': 'H.S.C.- Commerce (MBC)',
            'year': '2026-2027',
            'collegeType': 'junior',
            'term': 'SYJC',
            'startDate': '2026-08-01',
            'endDate': '2026-09-01',
          },
        ),
      );
      await tester.pumpAndSettle();

      // Verify Name, Course, Year
      expect(find.text('NEEL DOLIA'), findsOneWidget);
      expect(find.text('H.S.C.- Commerce (MBC)'), findsOneWidget);
      expect(find.text('2026-2027'), findsOneWidget);

      // Verify College Section exists and Junior College is selected
      expect(find.text('College Section'), findsOneWidget);
      expect(find.text('Junior College'), findsOneWidget);

      // Verify Term field exists with SYJC
      expect(find.text('Term'), findsOneWidget);
      expect(find.text('SYJC'), findsOneWidget);
      expect(find.text('Detected from your report'), findsOneWidget);

      // Verify date values
      expect(find.text('01 Aug 2026'), findsOneWidget);
      expect(find.text('01 Sep 2026'), findsOneWidget);
    });

    testWidgets('auto-selects Degree College and Semester when report is from Degree College', (tester) async {
      await tester.pumpWidget(
        createWidget(
          prefilledData: {
            'name': 'PARTH RATHOD',
            'course': 'Bachelor of Science (Computer Science)',
            'year': '2026-2027',
            'collegeType': 'degree',
            'semesterNumber': 5,
            'semester': 'Semester 5',
            'startDate': '2026-06-15',
            'endDate': '2026-08-31',
          },
        ),
      );
      await tester.pumpAndSettle();

      // Verify Name, Course, Year
      expect(find.text('PARTH RATHOD'), findsOneWidget);
      expect(find.text('Bachelor of Science (Computer Science)'), findsOneWidget);

      // Verify College Section exists
      expect(find.text('College Section'), findsOneWidget);

      // Verify Semester dropdown exists with Semester 5
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Semester 5'), findsOneWidget);
      expect(find.text('Detected from your report'), findsOneWidget);

      // Verify dates
      expect(find.text('15 Jun 2026'), findsOneWidget);
      expect(find.text('31 Aug 2026'), findsOneWidget);
    });

    testWidgets('manual mode defaults to Degree College and switches cleanly to Junior College', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Defaults to Degree College
      expect(find.text('College Section'), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Semester 1'), findsOneWidget);
      expect(find.text('Semester Start Date *'), findsOneWidget);
      expect(find.text('Semester End Date *'), findsOneWidget);

      // Tap Junior College
      await tester.tap(find.text('Junior College'));
      await tester.pumpAndSettle();

      // Now displays Term dropdown and Term dates
      expect(find.text('Term'), findsOneWidget);
      expect(find.text('FYJC'), findsOneWidget);
      expect(find.text('Term Start Date *'), findsOneWidget);
      expect(find.text('Term End Date *'), findsOneWidget);

      // Tap Degree College to switch back
      await tester.tap(find.text('Degree College'));
      await tester.pumpAndSettle();

      // Displays Semester dropdown and Semester dates again
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Semester 1'), findsOneWidget);
      expect(find.text('Semester Start Date *'), findsOneWidget);
      expect(find.text('Semester End Date *'), findsOneWidget);
    });
  });
}
