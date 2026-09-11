import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/database/db_helper.dart';
import 'package:attend_ease/database/subject_dao.dart';
import 'package:attend_ease/models/subject.dart';
import 'package:attend_ease/services/attendance_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBHelper.resetForTest();
    DBHelper.databaseFileName =
        'attendance_preferences_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    final path = '${await getDatabasesPath()}/${DBHelper.databaseFileName}';
    await DBHelper.resetForTest();
    await databaseFactory.deleteDatabase(path);
  });

  test(
    'saving targets updates preferences and every existing subject',
    () async {
      final subjectDao = SubjectDao();
      await subjectDao.insertSubject(
        Subject(name: 'Mathematics', requiredPercent: 75, semester: 1),
      );
      await subjectDao.insertSubject(
        Subject(name: 'Physics', requiredPercent: 65, semester: 2),
      );

      await AttendancePreferencesService(
        subjectDao: subjectDao,
      ).save(overallPercent: 84.5, subjectPercent: 79.5);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(AttendancePreferencesService.overallKey), 84.5);
      expect(prefs.getDouble(AttendancePreferencesService.subjectKey), 79.5);

      final subjects = await subjectDao.getAllSubjects();
      expect(subjects.map((subject) => subject.semester), containsAll([1, 2]));
      expect(
        subjects.every((subject) => subject.requiredPercent == 79.5),
        isTrue,
        reason: 'all attendance consumers read the target from subject rows',
      );
    },
  );
}
