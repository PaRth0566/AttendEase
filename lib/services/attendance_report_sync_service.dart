import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';
import 'local_data_reset_service.dart';
import 'local_pdf_parser.dart';
import 'pdf_attendance_import_service.dart';
import 'report_owner_check.dart';

/// The stage a report sync has reached, so a caller can narrate it.
enum ReportSyncStage { reading, updating, saving }

/// Asks the user whether to throw away everything the app holds and rebuild it
/// from a report that does not belong to the same student or course.
///
/// Returning false — or simply not supplying one of these — cancels the import
/// outright. See [AttendanceReportSyncService.syncFromBytes].
typedef ReportReplaceConfirm =
    Future<bool> Function(ReportOwnerMismatch mismatch);

/// Outcome of a completed sync.
class AttendanceReportSyncResult {
  const AttendanceReportSyncResult({
    required this.semester,
    this.replacedPreviousData = false,
  });

  /// The semester the report was detected for — the one now active.
  final int semester;

  /// Whether this import began by erasing the data of a different course, so a
  /// caller can say "replaced" rather than "updated".
  final bool replacedPreviousData;
}

/// Picks an attendance PDF and folds it into the local database.
///
/// Extracted from `RefreshPdfScreen` so the dashboard's one-tap sync button and
/// the full sync screen run exactly the same import: they used to be one code
/// path only by accident of there being a single caller, and a second copy of
/// "parse, replace the semester, back up" is the kind of thing that silently
/// drifts apart.
class AttendanceReportSyncService {
  const AttendanceReportSyncService();

  /// Opens the file picker, imports the chosen report and backs the result up.
  ///
  /// Returns null when the user dismissed the picker without choosing a file, or
  /// declined the replacement [confirmReplace] offered — a cancel, not a failure,
  /// so callers should simply return to their resting state. Anything genuinely
  /// wrong throws; pass it to [friendlyError].
  ///
  /// [onStage] fires as each phase begins, for callers that show progress text.
  Future<AttendanceReportSyncResult?> pickAndSync({
    void Function(ReportSyncStage stage)? onStage,
    ReportReplaceConfirm? confirmReplace,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final fileBytes = result.files.first.bytes;
    if (fileBytes == null) {
      throw const FormatException('Could not read the selected PDF file.');
    }

    return syncFromBytes(
      fileBytes,
      onStage: onStage,
      confirmReplace: confirmReplace,
    );
  }

  /// Imports an already-read report and backs the result up.
  ///
  /// Split out of [pickAndSync] so a PDF that arrives from outside the app —
  /// opened from Android's "Open with" chooser, see `IncomingPdfService` — runs
  /// the *same* import rather than a second copy of "parse, replace the
  /// semester, back up". That duplication is precisely what this class was
  /// extracted to prevent.
  ///
  /// A normal sync folds the report into what is already there. When the report
  /// turns out to belong to a *different student or course* — see
  /// [ReportOwnerCheck] — folding the two together is wrong, so the import stops
  /// before writing anything and puts the choice to [confirmReplace]. Confirming
  /// erases every subject, timetable entry and record the app holds and rebuilds
  /// it from this report alone; declining imports nothing at all.
  ///
  /// Returns null when the replacement was declined. A caller that supplies no
  /// [confirmReplace] declines by default: merging two courses is the bug this
  /// check exists to prevent, so doing nothing is the safe way to be wrong.
  ///
  /// Throws on anything genuinely wrong; pass it to [friendlyError].
  Future<AttendanceReportSyncResult?> syncFromBytes(
    Uint8List bytes, {
    void Function(ReportSyncStage stage)? onStage,
    ReportReplaceConfirm? confirmReplace,
  }) async {
    onStage?.call(ReportSyncStage.reading);
    // Bounded so a PDF the parser cannot handle gives the user their screen
    // back instead of an open-ended spinner — same cap the setup upload screen
    // applies. `.timeout` abandons the future; the isolate is left to finish and
    // be collected.
    final Map<String, dynamic> data =
        await LocalPdfParser.extractAttendanceFromPdf(bytes)
            .timeout(parseTimeout);

    onStage?.call(ReportSyncStage.updating);
    final applied = await _applyData(data, confirmReplace);
    if (applied == null) return null;

    onStage?.call(ReportSyncStage.saving);
    await CloudSyncService().backupDataToCloud();

    return AttendanceReportSyncResult(
      semester: applied.semester,
      replacedPreviousData: applied.replaced,
    );
  }

  /// Cap on the local parse. A well-formed report parses in well under a second.
  static const Duration parseTimeout = Duration(seconds: 25);

  /// Writes the parsed report into the database, and returns the semester it
  /// landed in. The user is switched to that semester, since a report they just
  /// imported is the one they want to be looking at.
  ///
  /// Null when the report describes a different course and the replacement was
  /// declined — in which case nothing at all has been written.
  Future<({int semester, bool replaced})?> _applyData(
    Map<String, dynamic> data,
    ReportReplaceConfirm? confirmReplace,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final activeSemester = prefs.getInt('semester') ?? 1;

    // The parser resolves the number itself (see LocalPdfParser's semester
    // notes): it must be read before "Semester" appears, the way SAP lays the
    // cell out, and a trailing date fragment must not be mistaken for it.
    final parsed = data['semesterNumber'];
    final targetSemester = parsed is int && parsed >= 1
        ? parsed
        : activeSemester;

    // Before anything is written, and specifically before the profile fields
    // below: the check compares the *stored* name and course against the
    // report's, so refreshing the header first would erase the evidence it needs.
    // Resolving the semester first matters for the same reason — the reset drops
    // the `semester` pref this falls back to.
    final mismatch = await ReportOwnerCheck().detect(
      data: data,
      targetSemester: targetSemester,
    );
    var replaced = false;
    if (mismatch != null) {
      final confirmed = await confirmReplace?.call(mismatch) ?? false;
      if (!confirmed) return null;
      await const LocalDataResetService().clearAllAcademicData();
      replaced = true;
    }

    await prefs.setInt('semester', targetSemester);
    await applyProfileFields(data, prefs);

    await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
      data: data,
      semester: targetSemester,
    );
    return (semester: targetSemester, replaced: replaced);
  }

  /// Refreshes the student's name, programme and academic year from the report.
  ///
  /// The semester and the semester's start/end dates already followed the PDF —
  /// the number here, the bounds in `PdfAttendanceImportService` — but these
  /// three did not, so a student moving to a new year kept last year's header on
  /// the profile while everything below it had moved on. They come off the same
  /// header as the dates, so a report that is authoritative for one is
  /// authoritative for all of them.
  ///
  /// Each field is written only when the parser actually found it: the header
  /// regexes fall back to an empty string when a report is laid out unusually,
  /// and blanking a name the user typed during setup is far worse than leaving
  /// it a semester out of date.
  @visibleForTesting
  static Future<void> applyProfileFields(
    Map<String, dynamic> data,
    SharedPreferences prefs,
  ) async {
    const fields = <String, String>{
      'name': 'full_name',
      'course': 'course',
      'year': 'year',
    };
    for (final entry in fields.entries) {
      final value = data[entry.key]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      await prefs.setString(entry.value, value);
    }
  }

  /// Reads a semester out of a header string that spells it as a digit or a
  /// Roman numeral, falling back to [fallback] when it says nothing usable.
  ///
  /// Delegates to [LocalPdfParser.semesterNumberFrom] — the three copies of this
  /// ladder that used to exist disagreed about zero-padded values.
  static int parseSemesterNumber(String s, int fallback) =>
      LocalPdfParser.semesterNumberFrom(s) ?? fallback;

  /// A message worth showing a student, for an error thrown by [pickAndSync].
  static String friendlyError(Object error) {
    final raw = error.toString();
    if (error is FormatException) {
      // The parser throws already-user-facing text — use it as-is.
      return error.message;
    }
    if (error is TimeoutException) {
      return "This PDF took too long to read. Make sure it's the attendance "
          'report downloaded from SAP.';
    }
    if (raw.contains('No such file') || raw.contains('FileSystemException')) {
      return 'The selected file could not be accessed. '
          'Please try selecting it again.';
    }
    return 'Something went wrong. Please try again with a valid attendance PDF.';
  }
}
