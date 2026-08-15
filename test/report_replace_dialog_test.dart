// The one gate in front of an irreversible wipe, so what is pinned here is the
// behaviour that makes it safe: it says whose report it is and what disappears,
// it only returns true for a deliberate tap on the destructive button, and a
// stray tap on the barrier cannot get through it.

import 'package:attend_ease/services/report_owner_check.dart';
import 'package:attend_ease/theme/app_theme.dart';
import 'package:attend_ease/widgets/report_replace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A friend's report opened on your install: different person, different course,
/// no subjects in common. The realistic case.
const _differentStudent = ReportOwnerMismatch(
  semester: 3,
  storedName: 'Parth Mehta',
  reportName: 'Riya Sharma',
  storedCourse: 'Bachelor of Technology',
  reportCourse: 'Bachelor of Commerce',
  storedYear: 'Second Year',
  reportYear: 'Second Year',
  differentStudent: true,
  differentCourse: true,
  storedSubjectCount: 6,
  reportSubjectCount: 5,
);

/// Same name, different programme — the transfer case, and the only one where
/// the course wording should lead.
const _differentCourse = ReportOwnerMismatch(
  semester: 5,
  storedName: 'Parth Mehta',
  reportName: 'Parth Mehta',
  storedCourse: 'Bachelor of Technology',
  reportCourse: 'Bachelor of Commerce',
  storedYear: 'Third Year',
  reportYear: 'Third Year',
  differentStudent: false,
  differentCourse: true,
  storedSubjectCount: 6,
  reportSubjectCount: 5,
);

/// Where the dialog's result lands, so a test can assert on the answer the sync
/// service would actually receive. Null until the dialog resolves.
class _Answer {
  bool? value;
}

/// Pumps a bare app, opens the dialog on it and settles the entry animation.
Future<_Answer> _open(
  WidgetTester tester,
  ReportOwnerMismatch mismatch,
) async {
  final answer = _Answer();
  late BuildContext ctx;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );

  // Deliberately not awaited: the dialog is still open at this point, and the
  // test drives it to an answer before reading the holder.
  confirmReportReplace(ctx, mismatch).then((value) => answer.value = value);
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  testWidgets('names the student whose report it is, and what goes', (
    tester,
  ) async {
    await _open(tester, _differentStudent);

    expect(find.text('This report is for a different student'), findsOneWidget);
    // Both sides named, so the user can tell which way round the swap goes.
    expect(
      find.textContaining('Riya Sharma'),
      findsWidgets,
      reason: 'the incoming report must be identified',
    );
    expect(find.textContaining('Parth Mehta'), findsWidgets);
    // The size of what is being thrown away, in the only unit that is visible.
    expect(find.textContaining('6 subjects'), findsOneWidget);
    // The backup warning is the part users cannot discover any other way.
    expect(
      find.textContaining('cloud backup will be replaced'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  testWidgets('leads with the course when the student is the same', (
    tester,
  ) async {
    await _open(tester, _differentCourse);

    expect(find.text('This report is for a different course'), findsOneWidget);
    expect(find.textContaining('Bachelor of Commerce'), findsWidgets);
    expect(find.textContaining('Bachelor of Technology'), findsWidgets);
  });

  testWidgets('Cancel resolves false — nothing is imported', (tester) async {
    final answer = await _open(tester, _differentStudent);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(answer.value, isFalse);
  });

  testWidgets('"Replace all data" resolves true', (tester) async {
    final answer = await _open(tester, _differentStudent);

    await tester.tap(find.widgetWithText(FilledButton, 'Replace all data'));
    await tester.pumpAndSettle();

    expect(answer.value, isTrue);
  });

  testWidgets('a tap on the barrier cannot trigger the wipe', (tester) async {
    final answer = await _open(tester, _differentStudent);

    // Top-left corner: outside the dialog, on the modal barrier.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(
      find.text('This report is for a different student'),
      findsOneWidget,
      reason: 'the dialog must survive a stray tap',
    );
    expect(
      answer.value,
      isNull,
      reason: 'an undismissed dialog has not answered yet',
    );
  });
}
