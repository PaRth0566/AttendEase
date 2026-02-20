import 'package:sqflite/sqflite.dart';

import 'db_helper.dart';

class AttendanceDao {
  // ================================
  // DASHBOARD STATS (SUBJECT-WISE)
  // ================================
  Future<Map<int, Map<String, int>>> getAttendanceStats() async {
    final db = await DBHelper.instance.database;

    final result = await db.rawQuery('''
      SELECT t.subject_id,
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) AS attended,
             COUNT(a.id) AS total
      FROM attendance_records a
      JOIN timetable t ON a.timetable_entry_id = t.id
      GROUP BY t.subject_id
    ''');

    final Map<int, Map<String, int>> stats = {};

    for (final row in result) {
      stats[row['subject_id'] as int] = {
        'attended': (row['attended'] as int?) ?? 0,
        'total': (row['total'] as int?) ?? 0,
      };
    }

    return stats;
  }

  // ================================
  // INSERT / UPDATE ATTENDANCE (PER LECTURE)
  // ================================
  Future<void> upsertAttendance({
    required int timetableId,
    required String date,
    required String status,
  }) async {
    final db = await DBHelper.instance.database;

    await db.insert('attendance_records', {
      'timetable_entry_id': timetableId,
      'date': date,
      'status': status,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ================================
  // DELETE ATTENDANCE
  // ================================
  Future<void> deleteAttendance(int timetableId, String date) async {
    final db = await DBHelper.instance.database;

    await db.delete(
      'attendance_records',
      where: 'timetable_entry_id = ? AND date = ?',
      whereArgs: [timetableId, date],
    );
  }

  // ================================
  // GET ATTENDANCE FOR A DATE
  // ================================
  Future<Map<int, String>> getAttendanceForDate(String date) async {
    final db = await DBHelper.instance.database;

    final result = await db.query(
      'attendance_records',
      where: 'date = ?',
      whereArgs: [date],
    );

    final Map<int, String> data = {};
    for (final row in result) {
      data[row['timetable_entry_id'] as int] = row['status'] as String;
    }

    return data;
  }

  // ================================
  // FETCH ATTENDANCE FOR A SPECIFIC DATE RANGE AND SEMESTER (REPORTING)
  // ================================
  Future<Map<int, Map<String, int>>> getAttendanceStatsForDateRange(
    String startDate,
    String endDate,
    int semester,
  ) async {
    final Database db = await DBHelper.instance.database;

    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT t.subject_id, 
             COUNT(a.id) as total, 
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) as attended
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id
      INNER JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date >= ? AND a.date <= ?
      GROUP BY t.subject_id
    ''',
      [semester, startDate, endDate],
    );

    final Map<int, Map<String, int>> stats = {};
    for (final row in result) {
      stats[row['subject_id'] as int] = {
        'total': row['total'] as int,
        'attended': row['attended'] != null ? row['attended'] as int : 0,
      };
    }
    return stats;
  }

  // ================================
  // FETCH ATTENDANCE STATUSES FOR A SPECIFIC DATE RANGE (CALENDAR HEATMAP)
  // ================================
  Future<Map<String, List<String>>> getMonthlyAttendanceStatus(
    String startDate,
    String endDate,
    int semester,
  ) async {
    final db = await DBHelper.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT a.date, a.status 
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id
      INNER JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date >= ? AND a.date <= ?
    ''',
      [semester, startDate, endDate],
    );

    final Map<String, List<String>> dateStatuses = {};
    for (final row in result) {
      final date = row['date'] as String;
      final status = row['status'] as String;
      if (!dateStatuses.containsKey(date)) {
        dateStatuses[date] = [];
      }
      dateStatuses[date]!.add(status);
    }
    return dateStatuses;
  }
}
