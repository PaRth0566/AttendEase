import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attend_ease/services/attendance_report_sync_service.dart';

/// The basic info on the profile — name, course, academic year — is read off the
/// same report header as the semester and its start/end dates. Those already
/// followed the PDF on every sync; these three did not, so a student moving into
/// a new year kept a stale header above freshly-synced attendance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A parsed report as `LocalPdfParser` emits it, trimmed to the header fields.
  Map<String, dynamic> reportHeader({
    String name = 'PARTH MEHTA',
    String course = 'Bachelor of Science (Information Technology)',
    String year = '2025-2026',
  }) => {'name': name, 'course': course, 'year': year};

  test('a synced report refreshes name, course and year', () async {
    SharedPreferences.setMockInitialValues({
      'full_name': 'Old Name',
      'course': 'Old Course',
      'year': '2024-2025',
    });
    final prefs = await SharedPreferences.getInstance();

    await AttendanceReportSyncService.applyProfileFields(
      reportHeader(),
      prefs,
    );

    expect(prefs.getString('full_name'), 'PARTH MEHTA');
    expect(
      prefs.getString('course'),
      'Bachelor of Science (Information Technology)',
    );
    expect(prefs.getString('year'), '2025-2026');
  });

  test('fields the parser could not find leave existing values alone', () async {
    // The header regexes fall back to '' on an unusual layout. Blanking a name
    // the student typed during setup is far worse than leaving it stale, so an
    // empty parse must be treated as "no information", not as "clear it".
    SharedPreferences.setMockInitialValues({
      'full_name': 'Typed By Hand',
      'course': 'Typed Course',
      'year': '2024-2025',
    });
    final prefs = await SharedPreferences.getInstance();

    await AttendanceReportSyncService.applyProfileFields(
      {'name': '', 'course': '   ', 'year': '2025-2026'},
      prefs,
    );

    expect(prefs.getString('full_name'), 'Typed By Hand');
    expect(prefs.getString('course'), 'Typed Course');
    // The one field the report did carry still updates.
    expect(prefs.getString('year'), '2025-2026');
  });

  test('missing keys are ignored rather than written as "null"', () async {
    // A parse that omits a key entirely must not stringify null into prefs —
    // the profile would render the literal text "null".
    SharedPreferences.setMockInitialValues({'full_name': 'Keep Me'});
    final prefs = await SharedPreferences.getInstance();

    await AttendanceReportSyncService.applyProfileFields(
      <String, dynamic>{},
      prefs,
    );

    expect(prefs.getString('full_name'), 'Keep Me');
    expect(prefs.getString('course'), isNull);
    expect(prefs.getString('year'), isNull);
  });

  test('values are trimmed before they reach the profile', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await AttendanceReportSyncService.applyProfileFields(
      reportHeader(name: '  PARTH MEHTA  ', year: ' 2025-2026 '),
      prefs,
    );

    expect(prefs.getString('full_name'), 'PARTH MEHTA');
    expect(prefs.getString('year'), '2025-2026');
  });
}
