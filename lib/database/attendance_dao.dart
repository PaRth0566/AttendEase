import 'package:sqflite/sqflite.dart';

import 'db_helper.dart';

class AttendanceDao {
  // ================================
  // DASHBOARD STATS (SUBJECT-WISE)
  // ================================
  Future<Map<int, Map<String, int>>> getAttendanceStats(int semester) async {
    final db = await DBHelper.instance.database;

    final result = await db.rawQuery('''
      SELECT t.subject_id,
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) AS attended,
             COUNT(a.id) AS total
      FROM attendance_records a
      JOIN timetable t ON a.timetable_entry_id = t.id
      JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ?
      GROUP BY t.subject_id
    ''', [semester]);

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
        AND a.date NOT LIKE 'pad_%'
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
  // FETCH HISTORY FOR A SPECIFIC SUBJECT (DEEP-DIVE)
  // ================================
  // Only returns real-dated records (yyyy-MM-dd) — pseudo-dates used for
  // stats padding are excluded so the UI never crashes on DateTime.parse.
  Future<List<Map<String, dynamic>>> getAttendanceHistoryForSubject(
    int subjectId,
  ) async {
    final db = await DBHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT a.timetable_entry_id, a.date, a.status
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id
      WHERE t.subject_id = ?
        AND a.date NOT LIKE 'pad_%'
      ORDER BY a.date DESC
    ''',
      [subjectId],
    );
    return maps;
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
        AND a.date NOT LIKE 'pad_%'
    ''',
      [semester, startDate, endDate],
    );

    final Map<String, List<String>> dateStatuses = {};
    for (final row in result) {
      final rawDate = row['date'] as String;
      final date = rawDate.split('_')[0]; // Strip suffix to match UI (YYYY-MM-DD)
      final status = row['status'] as String;
      if (!dateStatuses.containsKey(date)) {
        dateStatuses[date] = [];
      }
      dateStatuses[date]!.add(status);
    }
    return dateStatuses;
  }

  // ================================
  // GET ATTENDANCE FOR A DATE VIA SEED SLOTS (for calendar detail view)
  // Returns all subjects for the semester with their saved status for 'date'.
  // Uses day=0 seed timetable entries as the canonical attendance slot.
  // ================================
  // GET ATTENDANCE FOR A DATE — ONLY SUBJECTS WITH ACTUAL RECORDS
  // Returns subjects that have a real attendance entry (P or A) on 'date'.
  // Used by the calendar detail view to show "what was conducted on this day".
  // ================================
  Future<List<Map<String, dynamic>>> getAttendanceForDateBySeedSlot(
    String date,
    int semester,
  ) async {
    final db = await DBHelper.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        a.id        AS record_id,
        s.id        AS subject_id,
        s.name      AS subject_name,
        t.id        AS timetable_entry_id,
        a.status    AS status,
        a.date      AS record_date
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id AND t.day_of_week = 0
      INNER JOIN subjects s  ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date LIKE ?
      ORDER BY s.name ASC, a.date ASC
    ''',
      [semester, '$date%'],
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ================================
  // GET ALL SUBJECTS FOR MANUAL MARKING (LEFT JOIN — no records required)
  // Used as fallback when a selected date has no PDF records.
  // ================================
  Future<List<Map<String, dynamic>>> getAllSubjectsWithStatusForDate(
    String date,
    int semester,
  ) async {
    final db = await DBHelper.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        a.id        AS record_id,
        s.id        AS subject_id,
        s.name      AS subject_name,
        t.id        AS timetable_entry_id,
        a.status    AS status,
        a.date      AS record_date
      FROM subjects s
      LEFT JOIN timetable t
        ON t.subject_id = s.id AND t.day_of_week = 0
      LEFT JOIN attendance_records a
        ON a.timetable_entry_id = t.id AND a.date LIKE ?
      WHERE s.semester = ?
      ORDER BY s.name ASC, a.date ASC
    ''',
      ['$date%', semester],
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ================================
  // CALCULATE CURRENT STREAK
  // ================================
  Future<int> getCurrentStreak(int semester) async {
    final db = await DBHelper.instance.database;

    // Groups real-dated records by date, counting P and A per day.
    // Pseudo-dates (pad_P_, pad_A_) excluded via length(a.date)=10.
    final result = await db.rawQuery('''
      SELECT a.date,
             SUM(CASE WHEN a.status = 'A' THEN 1 ELSE 0 END) as absent_count,
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) as present_count
      FROM attendance_records a
      JOIN timetable t ON a.timetable_entry_id = t.id
      JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date NOT LIKE 'pad_%'
      GROUP BY substr(a.date, 1, 10)
      ORDER BY substr(a.date, 1, 10) DESC
    ''', [semester]);

    int streak = 0;
    for (final row in result) {
      int absentCount = row['absent_count'] as int;
      int presentCount = row['present_count'] as int;

      if (absentCount > 0) {
        break; // Streak is broken the moment we find an absent record!
      } else if (presentCount > 0) {
        streak++; // Perfect day!
      }
    }
    return streak;
  }
}
