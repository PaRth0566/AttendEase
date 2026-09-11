import 'package:shared_preferences/shared_preferences.dart';

import '../database/subject_dao.dart';
import '../models/subject.dart';

/// Persists the attendance targets consumed across the app.
class AttendancePreferencesService {
  static const overallKey = 'overall_required_attendance';
  static const subjectKey = 'subject_required_attendance';
  static const defaultOverall = 75.0;
  static const defaultSubject = 70.0;

  final SubjectDao _subjectDao;

  AttendancePreferencesService({SubjectDao? subjectDao})
    : _subjectDao = subjectDao ?? SubjectDao();

  Future<void> save({
    required double overallPercent,
    required double subjectPercent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble(overallKey, overallPercent),
      prefs.setDouble(subjectKey, subjectPercent),
    ]);

    // Reports and skip planners read the target from each subject row, while
    // preferences are the default for subjects created later. Update both.
    final subjects = await _subjectDao.getAllSubjects();
    await Future.wait(
      subjects
          .where((subject) => subject.id != null)
          .map(
            (subject) => _subjectDao.updateSubject(
              Subject(
                id: subject.id,
                name: subject.name,
                requiredPercent: subjectPercent,
                semester: subject.semester,
              ),
            ),
          ),
    );
  }
}
