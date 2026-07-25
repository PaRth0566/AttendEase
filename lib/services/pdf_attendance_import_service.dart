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
  })  : _subjectDao = subjectDao ?? SubjectDao(),
        _timetableDao = timetableDao ?? TimetableDao(),
        _attendanceDao = attendanceDao ?? AttendanceDao();

  Future<PdfAttendanceImportResult> replaceSemesterFromParsedPdf({
    required Map<String, dynamic> data,
    required int semester,
    bool updateSemesterBounds = true,
  }) async {
    final db = await DBHelper.instance.database;
    await db.delete('subjects', where: 'semester = ?', whereArgs: [semester]);

    final subjects = data['subjects'] is List ? data['subjects'] as List : const [];
    for (final rawSubject in subjects) {
      final subjectName = rawSubject.toString().trim();
      if (subjectName.isEmpty) continue;
      await _subjectDao.insertSubject(
        Subject(name: subjectName, requiredPercent: 75.0, semester: semester),
      );
    }

    final insertedSubjects = await _subjectDao.getSubjectsBySemester(semester);
    final subjectNameToId = {
      for (final subject in insertedSubjects) subject.name.trim(): subject.id!,
    };

    final subjectIdToSeedEntryId = <int, int>{};
    for (final subjectId in subjectNameToId.values) {
      subjectIdToSeedEntryId[subjectId] = await _timetableDao.ensureSeedEntry(subjectId);
    }

    if (updateSemesterBounds) {
      await _updateSemesterBounds(data, semester);
    }

    var recordsImported = 0;
    final insertedP = <String, int>{};
    final insertedA = <String, int>{};
    final records = data['attendanceRecords'] is List
        ? data['attendanceRecords'] as List
        : const [];

    for (final rawRecord in records) {
      if (rawRecord is! Map) continue;
      final normalized = _normalizeRecord(Map<String, dynamic>.from(rawRecord));
      if (normalized == null) continue;

      final subId = subjectNameToId[normalized.subjectName];
      if (subId == null) continue;
      final seedEntryId = subjectIdToSeedEntryId[subId];
      if (seedEntryId == null) continue;

      // The PDF value is authoritative: it sets both the current status and the
      // baseline (original_status). If the user had manually edited this record
      // to something else, re-importing the PDF resets it to the PDF value and
      // clears any "Manual" tag (Manual is derived as status != original_status).
      await _attendanceDao.upsertAttendance(
        timetableId: seedEntryId,
        date: normalized.date,
        status: normalized.status,
        source: 'pdf',
        originalStatus: normalized.status,
      );
      recordsImported++;

      if (normalized.status == 'P') {
        insertedP[normalized.subjectName] = (insertedP[normalized.subjectName] ?? 0) + 1;
      } else if (normalized.status == 'A') {
        insertedA[normalized.subjectName] = (insertedA[normalized.subjectName] ?? 0) + 1;
      }
    }

    await _insertStatPadding(
      data: data,
      subjectNameToId: subjectNameToId,
      subjectIdToSeedEntryId: subjectIdToSeedEntryId,
      insertedP: insertedP,
      insertedA: insertedA,
    );

    final timetableEntriesImported = await _insertInferredTimetable(
      data: data,
      subjectNameToId: subjectNameToId,
    );

    return PdfAttendanceImportResult(
      semester: semester,
      subjectsImported: insertedSubjects.length,
      recordsImported: recordsImported,
      timetableEntriesImported: timetableEntriesImported,
    );
  }

  Future<void> _updateSemesterBounds(Map<String, dynamic> data, int semester) async {
    final startStr = data['startDate']?.toString() ?? '';
    final endStr = data['endDate']?.toString() ?? '';
    if (DateTime.tryParse(startStr) == null || DateTime.tryParse(endStr) == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('semester_start_$semester', startStr);
    await prefs.setString('semester_end_$semester', endStr);
    debugPrint('Updated semester bounds from PDF: $startStr to $endStr');
  }

  Future<void> _insertStatPadding({
    required Map<String, dynamic> data,
    required Map<String, int> subjectNameToId,
    required Map<int, int> subjectIdToSeedEntryId,
    required Map<String, int> insertedP,
    required Map<String, int> insertedA,
  }) async {
    final rawStats = data['subjectStats'];
    if (rawStats is! Map) return;

    for (final entry in rawStats.entries) {
      final subjectName = entry.key.toString().trim();
      final stats = entry.value;
      if (stats is! Map) continue;

      final targetP = (stats['attended'] as num?)?.toInt() ?? 0;
      final targetTotal = (stats['total'] as num?)?.toInt() ?? 0;
      final targetA = targetTotal - targetP;

      final subId = subjectNameToId[subjectName];
      if (subId == null) continue;
      final seedEntryId = subjectIdToSeedEntryId[subId];
      if (seedEntryId == null) continue;

      final needP = (targetP - (insertedP[subjectName] ?? 0)).clamp(0, 99999);
      final needA = (targetA - (insertedA[subjectName] ?? 0)).clamp(0, 99999);

      for (var i = 0; i < needP; i++) {
        await _attendanceDao.upsertAttendance(
          timetableId: seedEntryId,
          date: 'pad_P_${subId}_$i',
          status: 'P',
        );
      }
      for (var i = 0; i < needA; i++) {
        await _attendanceDao.upsertAttendance(
          timetableId: seedEntryId,
          date: 'pad_A_${subId}_$i',
          status: 'A',
        );
      }
    }
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

  _NormalizedPdfRecord? _normalizeRecord(Map<String, dynamic> record) {
    final rawDate = record['date']?.toString().trim();
    final subjectName = record['subject']?.toString().trim();
    final status = record['status']?.toString().trim().toUpperCase();
    if (rawDate == null || subjectName == null || status == null) return null;
    if (subjectName.isEmpty || !const {'P', 'A', 'NU'}.contains(status)) return null;

    final parts = rawDate.split('_');
    final parsedDate = DateTime.tryParse(parts[0]);
    if (parsedDate == null) {
      debugPrint('Skipping invalid date format: "$rawDate"');
      return null;
    }

    final prefix = '${parsedDate.year.toString().padLeft(4, '0')}-'
        '${parsedDate.month.toString().padLeft(2, '0')}-'
        '${parsedDate.day.toString().padLeft(2, '0')}';
    final date = parts.length > 1 ? '${prefix}_${parts[1]}' : prefix;
    return _NormalizedPdfRecord(date: date, subjectName: subjectName, status: status);
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
