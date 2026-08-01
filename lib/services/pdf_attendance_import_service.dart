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

  Future<PdfAttendanceImportResult> replaceSemesterFromParsedPdf({
    required Map<String, dynamic> data,
    required int semester,
    bool updateSemesterBounds = true,
  }) async {
    final db = await DBHelper.instance.database;
    final subjects = data['subjects'] is List
        ? data['subjects'] as List
        : const [];
    final existingSubjects = await _subjectDao.getSubjectsBySemester(semester);
    final existingNames = {
      for (final subject in existingSubjects) subject.name.trim(),
    };
    for (final rawSubject in subjects) {
      final subjectName = rawSubject.toString().trim();
      if (subjectName.isEmpty || existingNames.contains(subjectName)) continue;
      await _subjectDao.insertSubject(
        Subject(name: subjectName, requiredPercent: 75.0, semester: semester),
      );
      existingNames.add(subjectName);
    }

    final insertedSubjects = await _subjectDao.getSubjectsBySemester(semester);
    final subjectNameToId = {
      for (final subject in insertedSubjects) subject.name.trim(): subject.id!,
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
    final coverageDates = _reportCoverageDates(data);
    if (coverageDates.isNotEmpty) {
      final sorted = coverageDates.toList()..sort();
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
        [semester, sorted.first, sorted.last],
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

        final subId = subjectNameToId[normalized.subjectName];
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
    if (hadPlannedTimetable) {
      await _attendanceDao.reconcileNotConductedLectures(semester);
    }

    return PdfAttendanceImportResult(
      semester: semester,
      subjectsImported: insertedSubjects.length,
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
        DateTime.tryParse(endStr) == null)
      return;

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
        final subjectId = subjectNameToId[subjectName];
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

  Set<String> _reportCoverageDates(Map<String, dynamic> data) {
    final start = DateTime.tryParse(data['startDate']?.toString() ?? '');
    final end = DateTime.tryParse(data['endDate']?.toString() ?? '');
    if (start == null || end == null || end.isBefore(start)) return const {};

    final dates = <String>{};
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
      );
    }
    return dates;
  }

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
    if (subjectName.isEmpty || !const {'P', 'A', 'NU', 'NC'}.contains(status))
      return null;

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
