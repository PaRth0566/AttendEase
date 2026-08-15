import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/subject_dao.dart';
import 'pdf_attendance_import_service.dart';

/// What the app holds versus what an incoming report describes, when the two do
/// not look like the same student on the same course.
///
/// A normal sync folds a report into the data already present: new subjects are
/// added, the planned timetable is left alone, records outside the report's span
/// survive. That is right for *your* next report and completely wrong for
/// somebody else's — the two curricula end up unioned, and the dashboard shows
/// one person's subjects next to another's. This is the signal that a sync must
/// stop and ask before it writes anything.
class ReportOwnerMismatch {
  const ReportOwnerMismatch({
    required this.semester,
    required this.storedName,
    required this.reportName,
    required this.storedCourse,
    required this.reportCourse,
    required this.storedYear,
    required this.reportYear,
    required this.differentStudent,
    required this.differentCourse,
    required this.storedSubjectCount,
    required this.reportSubjectCount,
  });

  /// The semester the report would land in.
  final int semester;

  final String storedName;
  final String reportName;
  final String storedCourse;
  final String reportCourse;
  final String storedYear;
  final String reportYear;

  /// The header names a student the app's profile does not.
  final bool differentStudent;

  /// The header names a programme the app's profile does not.
  final bool differentCourse;

  /// How many subjects the app currently holds in [semester], and how many the
  /// report carries — the size of what a replacement would throw away.
  final int storedSubjectCount;
  final int reportSubjectCount;
}

/// Decides whether an incoming report belongs to the student whose data the app
/// already holds.
///
/// The check is deliberately conservative: a false positive interrupts a routine
/// sync with a destructive-sounding dialog, so a report is only ever flagged
/// when it names a *different person*, or names a different programme **and**
/// carries a subject list that does not line up with the stored one.
///
/// Why the student name carries the decision on its own: the realistic way two
/// courses collide in one install is a friend's report being opened to check
/// their attendance, not a student transferring programmes mid-degree. The name
/// is also the only signal that works when the report is for a semester the app
/// has no subjects for yet, where "the subjects don't match" says nothing —
/// a student's own next semester has an entirely new subject list too.
class ReportOwnerCheck {
  ReportOwnerCheck({SubjectDao? subjectDao})
    : _subjectDao = subjectDao ?? SubjectDao();

  final SubjectDao _subjectDao;

  /// The mismatch an import should confirm before proceeding, or null when the
  /// report looks like a continuation of the data already present.
  ///
  /// [targetSemester] is the semester the import would write into — resolved
  /// from the report's own header, so a report for a future semester is compared
  /// against that semester's subjects rather than the one currently on screen.
  Future<ReportOwnerMismatch?> detect({
    required Map<String, dynamic> data,
    required int targetSemester,
  }) async {
    final allSubjects = await _subjectDao.getAllSubjects();
    // Nothing imported yet: there is nothing to overwrite and nothing to warn
    // about. This is also the setup wizard's path.
    if (allSubjects.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString('full_name')?.trim() ?? '';
    final storedCourse = prefs.getString('course')?.trim() ?? '';
    final storedYear = prefs.getString('year')?.trim() ?? '';
    final reportName = data['name']?.toString().trim() ?? '';
    final reportCourse = data['course']?.toString().trim() ?? '';
    final reportYear = data['year']?.toString().trim() ?? '';

    final differentStudent = describesSomethingElse(storedName, reportName);
    final differentCourse = describesSomethingElse(storedCourse, reportCourse);

    final storedForSemester = [
      for (final subject in allSubjects)
        if (subject.semester == targetSemester) subject.name,
    ];
    final reportSubjects = _reportSubjects(data);

    // The course string alone is not enough to act on: a student who typed
    // "BSc IT" during manual setup has a header that will never match SAP's
    // "Bachelor of Science (Information Technology)", and their own first sync
    // must not offer to wipe the timetable they just built by hand. A curriculum
    // that genuinely does not overlap is what turns a different course name into
    // a different course.
    final conflictingCurriculum = _curriculumConflicts(
      storedForSemester,
      reportSubjects,
    );

    if (!differentStudent && !(differentCourse && conflictingCurriculum)) {
      return null;
    }

    return ReportOwnerMismatch(
      semester: targetSemester,
      storedName: storedName,
      reportName: reportName,
      storedCourse: storedCourse,
      reportCourse: reportCourse,
      storedYear: storedYear,
      reportYear: reportYear,
      differentStudent: differentStudent,
      differentCourse: differentCourse,
      storedSubjectCount: storedForSemester.length,
      reportSubjectCount: reportSubjects.length,
    );
  }

  static List<String> _reportSubjects(Map<String, dynamic> data) {
    final raw = data['subjects'];
    if (raw is! List) return const [];
    return [
      for (final subject in raw)
        if (subject.toString().trim().isNotEmpty) subject.toString().trim(),
    ];
  }

  /// Whether two subject lists describe different curricula.
  ///
  /// False when either side is empty: an empty stored list means the semester is
  /// new (nothing to conflict with), and an empty report list means the parser
  /// found no subjects, which is a parse problem rather than evidence about
  /// whose report it is.
  ///
  /// "Different" is fewer than half the smaller list matching, so a report that
  /// adds an elective or drops a finished subject still reads as the same course.
  static bool _curriculumConflicts(
    List<String> stored,
    List<String> incoming,
  ) {
    final storedKeys = {
      for (final name in stored) PdfAttendanceImportService.nameKey(name),
    }..remove('');
    final incomingKeys = {
      for (final name in incoming) PdfAttendanceImportService.nameKey(name),
    }..remove('');
    if (storedKeys.isEmpty || incomingKeys.isEmpty) return false;

    final shared = storedKeys.intersection(incomingKeys).length;
    final smaller = storedKeys.length < incomingKeys.length
        ? storedKeys.length
        : incomingKeys.length;
    return shared * 2 < smaller;
  }

  /// Whether [stored] and [incoming] name different things, for the loose
  /// header strings a name or a programme comes as.
  ///
  /// Both sides must say something: an empty value is "unknown", not "different",
  /// and treating a header the parser could not read as a mismatch would flag
  /// every unusually-laid-out report.
  ///
  /// One value being a subset of the other's words counts as the same thing, so
  /// the "Parth" typed at setup still matches the "PARTH MEHTA" the report
  /// carries. Word order and punctuation are ignored.
  @visibleForTesting
  static bool describesSomethingElse(String stored, String incoming) {
    final a = _words(stored);
    final b = _words(incoming);
    if (a.isEmpty || b.isEmpty) return false;
    return !a.containsAll(b) && !b.containsAll(a);
  }

  static Set<String> _words(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toSet();
}
