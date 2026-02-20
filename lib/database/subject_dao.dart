import 'package:sqflite/sqflite.dart';

import '../models/subject.dart';
import 'db_helper.dart';

class SubjectDao {
  // INSERT SUBJECT
  Future<int> insertSubject(Subject subject) async {
    final Database db = await DBHelper.instance.database;
    return await db.insert(
      'subjects',
      subject.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ✅ GET SUBJECTS ONLY FOR A SPECIFIC SEMESTER
  Future<List<Subject>> getSubjectsBySemester(int semester) async {
    final Database db = await DBHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'subjects',
      where: 'semester = ?',
      whereArgs: [semester],
    );

    return maps.map((map) => Subject.fromMap(map)).toList();
  }

  // GET ALL SUBJECTS (USED FOR REPORTING)
  Future<List<Subject>> getAllSubjects() async {
    final Database db = await DBHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('subjects');
    return maps.map((map) => Subject.fromMap(map)).toList();
  }

  // DELETE SUBJECT
  Future<int> deleteSubject(int id) async {
    final Database db = await DBHelper.instance.database;
    return await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  // UPDATE SUBJECT
  Future<int> updateSubject(Subject subject) async {
    final Database db = await DBHelper.instance.database;
    return await db.update(
      'subjects',
      subject.toMap(),
      where: 'id = ?',
      whereArgs: [subject.id],
    );
  }
}
