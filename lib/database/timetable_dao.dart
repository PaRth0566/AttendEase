import 'package:sqflite/sqflite.dart';

import '../models/timetable_entry.dart';
import 'db_helper.dart';

class TimetableDao {
  // INSERT TIMETABLE ENTRY
  Future<void> insertEntry(TimetableEntry entry) async {
    final Database db = await DBHelper.instance.database;
    await db.insert('timetable', entry.toMap());
  }

  // ✅ GET ENTRIES ONLY FOR THE ACTIVE SEMESTER
  Future<List<TimetableEntry>> getEntriesForDay(
    int dayOfWeek,
    int semester,
  ) async {
    final Database db = await DBHelper.instance.database;

    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT timetable.* FROM timetable
      INNER JOIN subjects ON timetable.subject_id = subjects.id
      WHERE timetable.day_of_week = ? AND subjects.semester = ?
      ORDER BY timetable.lecture_order ASC
    ''',
      [dayOfWeek, semester],
    );

    return result.map((e) => TimetableEntry.fromMap(e)).toList();
  }

  // ✅ DELETE ENTRIES ONLY FOR THE ACTIVE SEMESTER
  Future<void> deleteEntriesForDay(int dayOfWeek, int semester) async {
    final Database db = await DBHelper.instance.database;

    await db.rawDelete(
      '''
      DELETE FROM timetable 
      WHERE day_of_week = ? AND subject_id IN (
        SELECT id FROM subjects WHERE semester = ?
      )
    ''',
      [dayOfWeek, semester],
    );
  }

  // Ensures each subject has a seed timetable slot (day=0) used for storing
  // attendance records when no real timetable is configured.
  // Creates one if it doesn't exist, then returns the entry id.
  Future<int> ensureSeedEntry(int subjectId) async {
    final Database db = await DBHelper.instance.database;
    final existing = await db.rawQuery(
      'SELECT id FROM timetable WHERE day_of_week = 0 AND subject_id = ?',
      [subjectId],
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('timetable', {
      'day_of_week': 0,
      'subject_id': subjectId,
      'lecture_order': 0,
    });
  }
}
