import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/attendance_dao.dart';
import '../database/db_helper.dart';
import '../database/subject_dao.dart';
import '../database/timetable_dao.dart';
import '../models/subject.dart';
import '../models/timetable_entry.dart';

class PdfAttendanceImportResult {
  final int semester;
  final int subjectsImported;
  final int recordsImported;
  final int timetableEntriesImported;

  const PdfAttendanceImportResult({
    required this.semester,
    required this.subjectsImported,
    required this.recordsImported,
    required this.timetableEntriesImported,
  });
}

class PdfAttendanceImportService {
  final SubjectDao _subjectDao;
  final TimetableDao _timetableDao;
  final AttendanceDao _attendanceDao;

  PdfAttendanceImportService({
    SubjectDao? subjectDao,
    TimetableDao? timetableDao,
    AttendanceDao? attendanceDao,
  }) : _subjectDao = subjectDao ?? SubjectDao(),
       _timetableDao = timetableDao ?? TimetableDao(),
       _attendanceDao = attendanceDao ?? AttendanceDao();

  /// Identity key for a subject name: case-folded with inner whitespace
  /// collapsed.
  ///
  /// Used for matching only — the original spelling is what gets stored and
  /// displayed. Two rows of the same course that differ by a doubled space or
  /// letter case are the same subject, and treating them as two would split one
  /// course's attendance across two dashboard rows.
  ///
  /// Public because `ReportOwnerCheck` compares a report's subject list against
  /// the stored one to decide whether they are the same curriculum, and it has to
  /// draw that line in exactly the same place this import does.
  static String nameKey(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<PdfAttendanceImportResult> replaceSemesterFromParsedPdf({
    required Map<String, dynamic> data,
    required int semester,
    bool updateSemesterBounds = true,
  }) async {
    final db = await DBHelper.instance.database;
    final subjects = data['subjects'] is List
        ? data['subjects'] as List
        : const [];
    // Subjects are matched on a normalised key — case-folded, inner whitespace
    // collapsed. An exact-string match meant "Data  Structures" (a doubled space
    // from a column split) or a re-cased "DBMS" registered as a new subject
    // alongside the original, splitting one course's attendance across two rows
    // on the dashboard. The first spelling seen keeps its display name.
    final existingSubjects = await _subjectDao.getSubjectsBySemester(semester);
    final existingNames = {
      for (final subject in existingSubjects) nameKey(subject.name),
    };
    var subjectsCreated = 0;
    for (final rawSubject in subjects) {
      final subjectName = rawSubject.toString().trim();
      final key = nameKey(subjectName);
      if (key.isEmpty || existingNames.contains(key)) continue;
      await _subjectDao.insertSubject(
        Subject(name: subjectName, requiredPercent: 75.0, semester: semester),
      );
      existingNames.add(key);
      subjectsCreated++;
    }

    final insertedSubjects = await _subjectDao.getSubjectsBySemester(semester);
    final subjectNameToId = {
      for (final subject in insertedSubjects) nameKey(subject.name): subject.id!,
    };

    final subjectIdToSeedEntryId = <int, int>{};
    for (final subjectId in subjectNameToId.values) {
      subjectIdToSeedEntryId[subjectId] = await _timetableDao.ensureSeedEntry(
        subjectId,
      );
    }

    if (updateSemesterBounds) {
      await _updateSemesterBounds(data, semester);
    }

    var recordsImported = 0;
    final records = data['attendanceRecords'] is List
        ? data['attendanceRecords'] as List
        : const [];
    final importedDates = <String>{};

    // Replace only report-derived rows in this report's date range. Subject IDs,
    // the planned timetable, manual extras and records outside the report stay
    // intact. This also removes NC rows previously derived from an older import.
    //
    // The delete sweeps the header's full span while coverage stops at the last
    // recorded date. Narrowing the delete to match coverage would strand rows an
    // earlier, longer report had written past this one's final record — they
    // would survive as phantom lectures no later import could reach.
    final coverageDates = _reportCoverageDates(data);
    final deleteRange = _reportDeleteRange(data);
    if (deleteRange != null) {
      await db.rawDelete(
        '''
        DELETE FROM attendance_records
        WHERE id IN (
          SELECT a.id
          FROM attendance_records a
          INNER JOIN timetable t ON a.timetable_entry_id = t.id
          INNER JOIN subjects s ON t.subject_id = s.id
          WHERE s.semester = ?
            AND substr(a.date, 1, 10) BETWEEN ? AND ?
            AND (a.source = 'pdf' OR a.status = 'NC')
        )
        ''',
        [semester, deleteRange.$1, deleteRange.$2],
      );
    }

    // One transaction for the whole report instead of one per record. A
    // semester's report is several hundred rows; at one implicit transaction
    // each this was seconds of fsync on a mid-range phone — the wait that made
    // the first upload feel hung.
    await db.transaction((txn) async {
      for (final rawRecord in records) {
        if (rawRecord is! Map) continue;
        final normalized =
            _normalizeRecord(Map<String, dynamic>.from(rawRecord));
        if (normalized == null) continue;
        importedDates.add(normalized.date.split('_').first);

        final subId = subjectNameToId[nameKey(normalized.subjectName)];
        if (subId == null) continue;
        final seedEntryId = subjectIdToSeedEntryId[subId];
        if (seedEntryId == null) continue;

        // The PDF value is authoritative: it sets both the current status and
        // the baseline (original_status). If the user had manually edited this
        // record to something else, re-importing the PDF resets it to the PDF
        // value and clears any "Manual" tag (Manual is derived as
        // status != original_status).
        await _attendanceDao.upsertAttendanceWith(
          txn,
          timetableId: seedEntryId,
          date: normalized.date,
          status: normalized.status,
          source: 'pdf',
          originalStatus: normalized.status,
        );
        recordsImported++;
      }
    });

    importedDates.addAll(coverageDates);
    await _attendanceDao.addImportedReportDates(semester, importedDates);

    // Clean up manual records the report contradicts.
    //
    // Every key the PDF mentions was just upserted with source='pdf', so any row
    // still marked 'manual' inside the covered range is one the report does not
    // have — either the subject was not conducted that day at all, or the day
    // held fewer lectures than the local copy believed. Both are stale, and both
    // inflate the subject's total if left in place.
    //
    // Matching on the exact date key rather than the base date is what catches
    // the second case: a "2025-11-05_2" row left over from an earlier report
    // that listed two lectures survives on a date the subject still appears on,
    // and silently adds a lecture the student never had.
    //
    // Only dates inside the coverage set are touched; manual records outside the
    // report (future dates, days it never spoke for) are the user's own and are
    // left alone.
    if (importedDates.isNotEmpty) {
      final sortedDates = importedDates.toList()..sort();
      final manualRows = await db.rawQuery(
        '''
        SELECT a.id, substr(a.date, 1, 10) AS base_date
        FROM attendance_records a
        INNER JOIN timetable t ON a.timetable_entry_id = t.id AND t.day_of_week = 0
        INNER JOIN subjects s ON t.subject_id = s.id
        WHERE s.semester = ?
          AND substr(a.date, 1, 10) BETWEEN ? AND ?
          AND a.source = 'manual'
        ''',
        [semester, sortedDates.first, sortedDates.last],
      );

      // BETWEEN spans a contiguous range, but the covered set need not be —
      // a record dated before the header's start widens the range past what the
      // report actually speaks for. Re-check membership so those days survive.
      final orphanIds = [
        for (final row in manualRows)
          if (importedDates.contains(row['base_date'] as String))
            (row['id'] as num).toInt(),
      ];

      if (orphanIds.isNotEmpty) {
        // Delete in batches to avoid SQLite variable limit.
        for (var i = 0; i < orphanIds.length; i += 500) {
          final batch = orphanIds.sublist(
            i,
            i + 500 > orphanIds.length ? orphanIds.length : i + 500,
          );
          final placeholders = List.filled(batch.length, '?').join(',');
          await db.rawDelete(
            'DELETE FROM attendance_records WHERE id IN ($placeholders)',
            batch,
          );
        }
        debugPrint(
          '[Import] Removed ${orphanIds.length} stale manual record(s)',
        );
      }
    }

    // Inference is setup assistance only. A later report must never rewrite the
    // user's planned weekly timetable based on temporary real-world changes.
    final recurring = await _timetableDao.getWeeklyTimetable(semester);
    final hadPlannedTimetable = recurring.isNotEmpty;
    final timetableEntriesImported = !hadPlannedTimetable
        ? await _insertInferredTimetable(
            data: data,
            subjectNameToId: subjectNameToId,
          )
        : 0;
    // Reconcile in both cases. This used to run only when a planned timetable
    // already existed, which meant a *first* upload produced no NC rows at all:
    // the timetable it needs to compare against is the one inferred immediately
    // above, so there was nothing to reconcile before that line and nobody
    // reconciled after it. A day where the report shows fewer lectures than the
    // week's inferred shape therefore showed a short day rather than the
    // "Not Conducted" slots that make the gap legible.
    await _attendanceDao.reconcileNotConductedLectures(semester);

    return PdfAttendanceImportResult(
      semester: semester,
      // Subjects newly created by *this* import, not every subject the semester
      // now holds — a re-import of the same report creates none, and reporting
      // the full count made it read as if it had re-added them all.
      subjectsImported: subjectsCreated,
      recordsImported: recordsImported,
      timetableEntriesImported: timetableEntriesImported,
    );
  }

  Future<void> _updateSemesterBounds(
    Map<String, dynamic> data,
    int semester,
  ) async {
    final startStr = data['startDate']?.toString() ?? '';
    final endStr = data['endDate']?.toString() ?? '';
    if (DateTime.tryParse(startStr) == null ||
        DateTime.tryParse(endStr) == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('semester_start_$semester', startStr);
    await prefs.setString('semester_end_$semester', endStr);
    debugPrint('Updated semester bounds from PDF: $startStr to $endStr');
  }

  Future<int> _insertInferredTimetable({
    required Map<String, dynamic> data,
    required Map<String, int> subjectNameToId,
  }) async {
    final inferredTimetable = data['inferredTimetable'];
    if (inferredTimetable is! Map) return 0;

    var inserted = 0;
    for (final dayEntry in inferredTimetable.entries) {
      final dayOfWeek = int.tryParse(dayEntry.key.toString());
      if (dayOfWeek == null || dayOfWeek < 1 || dayOfWeek > 7) continue;
      final subjectsForDay = dayEntry.value;
      if (subjectsForDay is! List) continue;

      for (var i = 0; i < subjectsForDay.length; i++) {
        final subjectName = subjectsForDay[i].toString().trim();
        final subjectId = subjectNameToId[nameKey(subjectName)];
        if (subjectId == null) continue;
        await _timetableDao.insertEntry(
          TimetableEntry(
            dayOfWeek: dayOfWeek,
            subjectId: subjectId,
            lectureOrder: i + 1,
          ),
        );
        inserted++;
      }
    }
    return inserted;
  }

  /// Inclusive `(start, end)` bounds for clearing previously report-derived
  /// rows, as `yyyy-MM-dd`.
  ///
  /// Widened to cover the header span *and* every date this report carries a
  /// record for, so a re-import cleans up after an earlier report even when the
  /// two disagree about the term's extent. Null when neither is knowable, in
  /// which case nothing is deleted and the upserts below merely overwrite
  /// matching keys.
  (String, String)? _reportDeleteRange(Map<String, dynamic> data) {
    final bounds = <String>[];
    final start = DateTime.tryParse(data['startDate']?.toString() ?? '');
    final end = DateTime.tryParse(data['endDate']?.toString() ?? '');
    if (start != null) bounds.add(_dateKey(start));
    if (end != null) bounds.add(_dateKey(end));

    final records = data['attendanceRecords'] is List
        ? data['attendanceRecords'] as List
        : const [];
    for (final rawRecord in records) {
      if (rawRecord is! Map) continue;
      final normalized = _normalizeRecord(Map<String, dynamic>.from(rawRecord));
      if (normalized == null) continue;
      bounds.add(normalized.date.split('_').first);
    }

    if (bounds.isEmpty) return null;
    bounds.sort();
    return (bounds.first, bounds.last);
  }

  /// The dates this report actually speaks for.
  ///
  /// Every date in the range is included, not just those carrying a record: a
  /// gap *inside* the covered span is the report positively asserting "no class
  /// that day", which the calendar must honour instead of projecting the
  /// weekly timetable onto it.
  ///
  /// The span is the header's start date through the **last date the report has
  /// a record for** — not the header's end date. A SAP header spans the whole
  /// semester ("From 01.11.2025 to 25.02.2026"), so trusting its end marked
  /// every remaining date of the term as covered. `getDaySchedule` then treated
  /// tomorrow as an imported day with zero records and returned nothing, so the
  /// calendar showed "No records for this date" for every future day and the
  /// timetable projection never ran. A report cannot assert anything about days
  /// that had not happened when it was generated.
  ///
  /// A trailing run of genuinely class-free days (an exam gap at the end of the
  /// report) falls outside the span and will project timetable rows instead of
  /// nothing. That is the conservative direction to be wrong in, and matches
  /// how a one-off future holiday already behaves.
  Set<String> _reportCoverageDates(Map<String, dynamic> data) {
    final start = DateTime.tryParse(data['startDate']?.toString() ?? '');
    if (start == null) return const {};

    final headerEnd = DateTime.tryParse(data['endDate']?.toString() ?? '');
    final lastRecorded = _lastRecordedDate(data);
    if (lastRecorded == null) return const {};

    var end = lastRecorded;
    if (headerEnd != null && headerEnd.isBefore(end)) end = headerEnd;
    if (end.isBefore(start)) return const {};

    final dates = <String>{};
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(_dateKey(date));
    }
    return dates;
  }

  /// The latest date carrying a usable record, which stands in for "when this
  /// report was generated".
  DateTime? _lastRecordedDate(Map<String, dynamic> data) {
    final records = data['attendanceRecords'] is List
        ? data['attendanceRecords'] as List
        : const [];
    DateTime? latest;
    for (final rawRecord in records) {
      if (rawRecord is! Map) continue;
      final normalized = _normalizeRecord(Map<String, dynamic>.from(rawRecord));
      if (normalized == null) continue;
      final date = DateTime.tryParse(normalized.date.split('_').first);
      if (date == null) continue;
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  _NormalizedPdfRecord? _normalizeRecord(Map<String, dynamic> record) {
    final rawDate = record['date']?.toString().trim();
    final subjectName = record['subject']?.toString().trim();
    final rawStatus = record['status']?.toString().trim().toUpperCase();
    final status = rawStatus == 'AG' || rawStatus == 'ATTENDANCE GRANTED'
        ? 'P'
        : rawStatus == 'CANCELLED' || rawStatus == 'NOT CONDUCTED'
        ? 'NC'
        : rawStatus;
    if (rawDate == null || subjectName == null || status == null) return null;
    if (subjectName.isEmpty ||
        !const {'P', 'A', 'NU', 'NC'}.contains(status)) {
      return null;
    }

    final parts = rawDate.split('_');
    final parsedDate = DateTime.tryParse(parts[0]);
    if (parsedDate == null) {
      debugPrint('Skipping invalid date format: "$rawDate"');
      return null;
    }

    final prefix =
        '${parsedDate.year.toString().padLeft(4, '0')}-'
        '${parsedDate.month.toString().padLeft(2, '0')}-'
        '${parsedDate.day.toString().padLeft(2, '0')}';
    final date = parts.length > 1 ? '${prefix}_${parts[1]}' : prefix;
    return _NormalizedPdfRecord(
      date: date,
      subjectName: subjectName,
      status: status,
    );
  }
}

class _NormalizedPdfRecord {
  final String date;
  final String subjectName;
  final String status;

  const _NormalizedPdfRecord({
    required this.date,
    required this.subjectName,
    required this.status,
  });
}
