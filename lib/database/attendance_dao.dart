import 'package:sqflite/sqflite.dart';

import 'db_helper.dart';

class AttendanceDao {
  // ================================
  // DASHBOARD STATS (SUBJECT-WISE)
  // ================================
  Future<Map<int, Map<String, int>>> getAttendanceStats(int semester) async {
    final db = await DBHelper.instance.database;

    final result = await db.rawQuery(
      '''
      SELECT t.subject_id,
             SUM(CASE WHEN a.status = 'P' THEN 1 ELSE 0 END) AS attended,
             COUNT(a.id) AS total
      FROM attendance_records a
      JOIN timetable t ON a.timetable_entry_id = t.id
      JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ?
        AND a.date NOT LIKE 'pad_%'
        AND a.status IN ('P', 'A')
      GROUP BY t.subject_id
    ''',
      [semester],
    );

    final Map<int, Map<String, int>> stats = {};

    for (final row in result) {
      final subjectId = row['subject_id'] is num
          ? (row['subject_id'] as num).toInt()
          : row['subject_id'] as int;
      stats[subjectId] = {
        'attended': row['attended'] is num
            ? (row['attended'] as num).toInt()
            : 0,
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
    await upsertAttendanceWith(
      db,
      timetableId: timetableId,
      date: date,
      status: status,
      source: source,
      originalStatus: originalStatus,
    );
  }

  /// Transaction-aware variant of [upsertAttendance].
  ///
  /// Takes a [DatabaseExecutor] so a caller importing a whole report can run
  /// the upserts inside a single `db.transaction` rather than one implicit
  /// transaction per row — the per-row fsync is what made a several-hundred-row
  /// first upload feel hung. Pass `await DBHelper.instance.database` for the
  /// non-batched path.
  Future<void> upsertAttendanceWith(
    DatabaseExecutor executor, {
    required int timetableId,
    required String date,
    required String status,
    String source = 'pdf',
    String? originalStatus,
  }) async {
    String? baseline = originalStatus;
    if (baseline == null) {
      final existing = await executor.query(
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

    await executor.insert('attendance_records', {
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

  /// Deletes a single attendance record by its primary key.
  ///
  /// `(timetable_entry_id, date)` is UNIQUE, so [deleteAttendance] already
  /// removes exactly one row — but only as long as every caller passes the
  /// record's *full* date key, suffix included (`2026-08-11_2` is a subject's
  /// second lecture that day, and `2026-08-11` is a different record). Deleting
  /// by id takes that requirement off the caller, which is what lets the
  /// calendar's undo restore the one row the user tapped and no other.
  Future<void> deleteAttendanceById(int recordId) async {
    final db = await DBHelper.instance.database;

    await db.delete(
      'attendance_records',
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> replaceImportedReportDates(
    int semester,
    Iterable<String> dates,
  ) async {
    final db = await DBHelper.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'imported_report_dates',
        where: 'semester = ?',
        whereArgs: [semester],
      );
      for (final date in dates) {
        await txn.insert('imported_report_dates', {
          'semester': semester,
          'date': date,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> addImportedReportDates(
    int semester,
    Iterable<String> dates,
  ) async {
    final db = await DBHelper.instance.database;
    await db.transaction((txn) async {
      for (final date in dates) {
        await txn.insert('imported_report_dates', {
          'semester': semester,
          'date': date,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
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
        AND a.status IN ('P', 'A')
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
    // Schedule-sourced NC rows are included. They were filtered out here on the
    // grounds that a gap-fill is "not a real attendance event", but the subject
    // timeline is where a student looks to ask why a subject's total is lower
    // than the week suggests — and the answer, "that planned lecture was not
    // conducted", was the one row being withheld. The screen already renders
    // them (orange, "Planned lecture was not conducted"), and they carry no
    // weight in the percentage, which counts only P and A.
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

  /// Returns all real attendance records for a semester, including NU and NC.
  /// Callers use the records themselves to derive date-specific behaviour; the
  /// recurring timetable is not part of this read path.
  Future<Map<int, List<Map<String, dynamic>>>> getAttendanceHistoryForSemester(
    int semester,
  ) async {
    final db = await DBHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT t.subject_id, a.date, a.status
      FROM attendance_records a
      INNER JOIN timetable t ON a.timetable_entry_id = t.id
      INNER JOIN subjects s ON t.subject_id = s.id
      WHERE s.semester = ? AND a.date NOT LIKE 'pad_%'
      ORDER BY a.date ASC
      ''',
      [semester],
    );
    final history = <int, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final subjectId = (row['subject_id'] as num).toInt();
      (history[subjectId] ??= []).add(Map<String, dynamic>.from(row));
    }
    return history;
  }

  /// Materializes planned slots missing from an imported teaching day as NC.
  /// Actual imported/manual rows are never removed or remapped, and the weekly
  /// timetable remains a reusable plan for future weeks.
  Future<void> reconcileNotConductedLectures(int semester) async {
    final db = await DBHelper.instance.database;
    await db.transaction((txn) async {
      final teachingDates = await txn.rawQuery(
        '''
        SELECT DISTINCT substr(a.date, 1, 10) AS date
        FROM attendance_records a
        INNER JOIN timetable t ON a.timetable_entry_id = t.id
        INNER JOIN subjects s ON t.subject_id = s.id
        WHERE s.semester = ?
          AND a.source = 'pdf'
          AND a.status IN ('P', 'A', 'NU')
          AND a.date NOT LIKE 'pad_%'
        ''',
        [semester],
      );

      for (final dateRow in teachingDates) {
        final date = dateRow['date'] as String;
        final weekday = DateTime.parse(date).weekday;
        final planned = await txn.rawQuery(
          '''
          SELECT t.subject_id, COUNT(*) AS lecture_count
          FROM timetable t
          INNER JOIN subjects s ON t.subject_id = s.id
          WHERE s.semester = ? AND t.day_of_week = ?
          GROUP BY t.subject_id
          ''',
          [semester, weekday],
        );

        for (final slot in planned) {
          final subjectId = (slot['subject_id'] as num).toInt();
          final plannedCount = (slot['lecture_count'] as num).toInt();

          // No staleness test here, deliberately. The original guard skipped any
          // subject the report did not mention on this date — which is the
          // definition of a lecture that was not conducted, so it made NC
          // unreachable in the only case it exists for.
          //
          // Replacing it with "has this subject been seen on this weekday
          // elsewhere?" was no better: a subject that never appears in the
          // report at all (dropped, or cancelled every week) is exactly the one
          // whose planned lectures were not conducted, and that test skipped it.
          //
          // So the planned slot is trusted. This method only visits dates the
          // report actually covers, and only fills slots the report leaves
          // unaccounted for: if the timetable says the lecture was scheduled and
          // the report does not record it, it was not conducted. The cost is a
          // subject whose slot moved weekday mid-semester keeps producing NC on
          // the old day until the timetable is corrected — visible, but harmless,
          // since NC is excluded from every attendance calculation.

          final representedCountResult = await txn.rawQuery(
            '''
            SELECT COUNT(*) AS lecture_count
            FROM attendance_records a
            INNER JOIN timetable t ON a.timetable_entry_id = t.id
            WHERE t.subject_id = ?
              AND substr(a.date, 1, 10) = ?
            ''',
            [subjectId, date],
          );
          final representedCount =
              (representedCountResult.first['lecture_count'] as num).toInt();
          final missing = plannedCount - representedCount;
          if (missing <= 0) continue;

          final seedRows = await txn.query(
            'timetable',
            columns: ['id'],
            where: 'day_of_week = 0 AND subject_id = ?',
            whereArgs: [subjectId],
            limit: 1,
          );
          if (seedRows.isEmpty) continue;
          final seedId = seedRows.first['id'] as int;
          final existingRows = await txn.query(
            'attendance_records',
            columns: ['date'],
            where: 'timetable_entry_id = ? AND date LIKE ?',
            whereArgs: [seedId, '$date%'],
          );
          final used = existingRows.map((row) => row['date'] as String).toSet();
          var suffix = 1;
          for (var i = 0; i < missing; i++) {
            var key = suffix == 1 ? date : '${date}_$suffix';
            while (used.contains(key)) {
              suffix++;
              key = '${date}_$suffix';
            }
            used.add(key);
            suffix++;
            await txn.insert('attendance_records', {
              'timetable_entry_id': seedId,
              'date': key,
              'status': 'NC',
              'source': 'schedule',
              'original_status': 'NC',
            });
          }
        }
      }
    });
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
      WHERE s.semester = ?
        AND a.date NOT LIKE 'pad_%'
        AND substr(a.date, 1, 10) >= ?
        AND substr(a.date, 1, 10) <= ?
    ''',
      [semester, startDate, endDate],
    );

    final Map<String, List<String>> dateStatuses = {};
    for (final row in result) {
      final rawDate = row['date'] as String;
      final date = rawDate.split(
        '_',
      )[0]; // Strip suffix to match UI (YYYY-MM-DD)
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
  // Before a date is covered by an imported SAP report, scheduled lectures with
  // no record appear as virtual "Not Updated" rows. Once SAP coverage includes
  // the date, only report records are returned: missing scheduled rows were not
  // conducted, while unscheduled report rows are actual extra/swapped lectures.
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
    final importedDate = await db.query(
      'imported_report_dates',
      columns: ['id'],
      where: 'semester = ? AND date = ?',
      whereArgs: [semester, date],
      limit: 1,
    );
    final hasImportedReport = importedDate.isNotEmpty;

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

    // For imported dates, persisted records are authoritative. This includes
    // replacement subjects and reconciled NC rows; the recurring timetable is
    // only used to fill dates that have no imported coverage.
    final expectedCount = <int, int>{};
    final expectedName = <int, String>{};
    final orderedSubjects = <int>[];
    if (hasImportedReport) {
      for (final row in recordRows) {
        final sid = row['subject_id'] as int;
        if (!expectedCount.containsKey(sid)) {
          orderedSubjects.add(sid);
          expectedName[sid] = row['subject_name'] as String;
        }
        expectedCount[sid] = (expectedCount[sid] ?? 0) + 1;
      }
    } else {
      for (final row in timetableRows) {
        final sid = row['subject_id'] as int;
        if (!expectedCount.containsKey(sid)) {
          orderedSubjects.add(sid);
          expectedName[sid] = row['subject_name'] as String;
        }
        expectedCount[sid] = (expectedCount[sid] ?? 0) + 1;
      }
      // Extra manually-recorded lectures remain visible on uncovered dates.
      for (final sid in recordsBySubject.keys) {
        if (!expectedCount.containsKey(sid)) {
          orderedSubjects.add(sid);
          expectedName[sid] =
              recordsBySubject[sid]!.first['subject_name'] as String;
          expectedCount[sid] = 0;
        }
      }
    }

    String keyForIndex(int i) => i == 0 ? date : '${date}_${i + 1}';

    final result = <Map<String, dynamic>>[];
    for (final sid in orderedSubjects) {
      final records = recordsBySubject[sid] ?? const [];
      final expected = expectedCount[sid] ?? 0;
      final showCount = hasImportedReport
          ? records.length
          : (records.length > expected ? records.length : expected);

      // Track date keys already taken by real records to avoid collisions
      // when generating keys for virtual slots.
      final usedKeys = <String>{
        for (final r in records) r['record_date'] as String,
      };
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
        } else if (!hasImportedReport) {
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

}
