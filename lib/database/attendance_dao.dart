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
        AND a.date NOT LIKE 'pad_%'
        AND a.status != 'NU'
      GROUP BY t.subject_id
    ''', [semester]);

    final Map<int, Map<String, int>> stats = {};

    for (final row in result) {
      final subjectId = row['subject_id'] is num
          ? (row['subject_id'] as num).toInt()
          : row['subject_id'] as int;
      stats[subjectId] = {
        'attended': row['attended'] is num ? (row['attended'] as num).toInt() : 0,
        'total': row['total'] is num ? (row['total'] as num).toInt() : 0,
      };
    }

    return stats;
  }

  // ================================
  // INSERT / UPDATE ATTENDANCE (PER LECTURE)
  // ================================
  // [originalStatus] records the PDF-reported baseline. When null, the baseline
  // is preserved from any existing row (a manual edit), or falls back to the
  // new [status] for a brand-new manual record. "Manual" is later derived as
  // (status != original_status), so reverting a value back to the PDF baseline
  // clears the tag automatically.
  Future<void> upsertAttendance({
    required int timetableId,
    required String date,
    required String status,
    String source = 'pdf',
    String? originalStatus,
  }) async {
    final db = await DBHelper.instance.database;

    String? baseline = originalStatus;
    if (baseline == null) {
      final existing = await db.query(
        'attendance_records',
        columns: ['original_status'],
        where: 'timetable_entry_id = ? AND date = ?',
        whereArgs: [timetableId, date],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.first['original_status'] != null) {
        baseline = existing.first['original_status'] as String;
      } else {
        // Brand-new record with no PDF baseline: treat the chosen status as the
        // baseline so a purely manual entry is not flagged "Manual".
        baseline = status;
      }
    }

    await db.insert('attendance_records', {
      'timetable_entry_id': timetableId,
      'date': date,
      'status': status,
      'source': source,
      'original_status': baseline,
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

    // Compare on the stripped 10-char date (substr) so multi-lecture records
    // carrying a "_2"/"_3" suffix (e.g. 2026-07-20_2) are matched on their real
    // date instead of sorting lexicographically past the end boundary. Padding
    // rows (pad_%) are shorter/prefixed and excluded explicitly.
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT t.subject_id,
             COUNT(a.id) as total,
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) as attended
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id
      INNER JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ?
        AND a.date NOT LIKE 'pad_%'
        AND substr(a.date, 1, 10) >= ? AND substr(a.date, 1, 10) <= ?
        AND a.status != 'NU'
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
      SELECT a.timetable_entry_id, a.date, a.status, a.source, a.original_status
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
        a.date      AS record_date,
        a.source    AS source,
        a.original_status AS original_status
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
  // GET FULL DAY SCHEDULE (TIMETABLE-FILLED)
  // ================================
  // Merges the weekly timetable's expected lectures for [date]'s weekday with
  // the actually-stored records, so every scheduled lecture appears — even ones
  // with no record yet (rendered as virtual "Not Updated" rows the user can set).
  // This makes each weekday show a consistent lecture count (fixes the 4/5/6
  // Monday inconsistency). Rows are returned in timetable order, with any extra
  // recorded lectures (beyond the timetable) appended.
  //
  // Each row: record_id (null when virtual), subject_id, subject_name,
  // timetable_entry_id (the day=0 seed id), status, record_date (unique key),
  // source, original_status, is_virtual (1/0).
  Future<List<Map<String, dynamic>>> getDaySchedule(
    String date,
    int semester,
  ) async {
    final db = await DBHelper.instance.database;
    final weekday = DateTime.parse(date).weekday; // 1 = Mon … 7 = Sun

    // 1. Expected lectures for this weekday, in slot order.
    final timetableRows = await db.rawQuery(
      '''
      SELECT t.subject_id AS subject_id, s.name AS subject_name
      FROM timetable t
      INNER JOIN subjects s ON t.subject_id = s.id
      WHERE t.day_of_week = ? AND s.semester = ?
      ORDER BY t.lecture_order ASC, s.name ASC
    ''',
      [weekday, semester],
    );

    // 2. Seed (day=0) timetable entry id per subject — attendance lives here.
    final seedRows = await db.rawQuery(
      'SELECT subject_id, id FROM timetable WHERE day_of_week = 0',
    );
    final seedBySubject = <int, int>{
      for (final r in seedRows) r['subject_id'] as int: r['id'] as int,
    };

    // 3. Stored records for this date, grouped by subject (in date order).
    final recordRows = await db.rawQuery(
      '''
      SELECT
        a.id        AS record_id,
        s.id        AS subject_id,
        s.name      AS subject_name,
        t.id        AS timetable_entry_id,
        a.status    AS status,
        a.date      AS record_date,
        a.source    AS source,
        a.original_status AS original_status
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id AND t.day_of_week = 0
      INNER JOIN subjects s  ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date LIKE ?
      ORDER BY a.date ASC
    ''',
      [semester, '$date%'],
    );

    final recordsBySubject = <int, List<Map<String, dynamic>>>{};
    for (final r in recordRows) {
      (recordsBySubject[r['subject_id'] as int] ??= []).add(
        Map<String, dynamic>.from(r),
      );
    }

    // Expected lecture count per subject (from the timetable), preserving the
    // first-seen order of subjects across the day.
    final expectedCount = <int, int>{};
    final expectedName = <int, String>{};
    final orderedSubjects = <int>[];
    for (final row in timetableRows) {
      final sid = row['subject_id'] as int;
      if (!expectedCount.containsKey(sid)) {
        orderedSubjects.add(sid);
        expectedName[sid] = row['subject_name'] as String;
      }
      expectedCount[sid] = (expectedCount[sid] ?? 0) + 1;
    }
    // Include any subjects that have records but aren't in the timetable
    // (e.g. manually-added extra lectures) so nothing is ever hidden.
    for (final sid in recordsBySubject.keys) {
      if (!expectedCount.containsKey(sid)) {
        orderedSubjects.add(sid);
        expectedName[sid] = recordsBySubject[sid]!.first['subject_name'] as String;
        expectedCount[sid] = 0;
      }
    }

    String keyForIndex(int i) => i == 0 ? date : '${date}_${i + 1}';

    final result = <Map<String, dynamic>>[];
    for (final sid in orderedSubjects) {
      final records = recordsBySubject[sid] ?? const [];
      final expected = expectedCount[sid] ?? 0;
      final showCount = records.length > expected ? records.length : expected;

      // Track date keys already taken by real records to avoid collisions
      // when generating keys for virtual slots.
      final usedKeys = <String>{for (final r in records) r['record_date'] as String};
      var nextKeyIndex = 0;
      String nextFreeKey() {
        var k = keyForIndex(nextKeyIndex);
        while (usedKeys.contains(k)) {
          nextKeyIndex++;
          k = keyForIndex(nextKeyIndex);
        }
        usedKeys.add(k);
        nextKeyIndex++;
        return k;
      }

      for (var i = 0; i < showCount; i++) {
        if (i < records.length) {
          result.add(records[i]);
        } else {
          // Virtual "Not Updated" slot filled from the timetable.
          final seedId = seedBySubject[sid];
          if (seedId == null) continue; // no seed slot -> cannot store; skip
          result.add({
            'record_id': null,
            'subject_id': sid,
            'subject_name': expectedName[sid],
            'timetable_entry_id': seedId,
            'status': 'NU',
            'record_date': nextFreeKey(),
            'source': 'timetable',
            'original_status': 'NU',
            'is_virtual': 1,
          });
        }
      }
    }
    return result;
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
        a.date      AS record_date,
        a.source    AS source
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
        AND a.status != 'NU'
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
