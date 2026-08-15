import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';

/// Erases the academic data one report's worth of setup left behind, so a report
/// from a different course can be imported into a clean app.
///
/// Separate from the wipe in `AuthService.signOut`, which also clears *every*
/// preference because the next user may be a different account entirely. This one
/// keeps the things that are the device's rather than the report's — the theme,
/// the attendance thresholds the student chose, the fact that setup has been
/// completed — because the user is not signing out, they are swapping which
/// report the app is built from.
class LocalDataResetService {
  const LocalDataResetService();

  /// Preferences that describe the student and the term a report established.
  /// Everything here is re-derived from the incoming report by
  /// `AttendanceReportSyncService`, so leaving any of them would mix the old
  /// course's header into the new course's data.
  static const _reportDerivedKeys = <String>{
    'full_name',
    'name',
    'course',
    'year',
    'division',
    'semester',
    'manual_semester',
  };

  /// Whether [key] is a per-semester date bound. Both the current
  /// `semester_start_3` form and the legacy unsuffixed `semester_start` are
  /// matched: an old install can still hold the bare keys, and a stale bound
  /// silently shrinks the calendar's idea of the term.
  static bool _isSemesterBound(String key) =>
      key.startsWith('semester_start') || key.startsWith('semester_end');

  /// Drops every subject, timetable entry, attendance record and imported-date
  /// marker, for every semester, plus the report-derived preferences above.
  ///
  /// Every semester, not just the one being replaced: the old data belongs to a
  /// course the student is not on, and leaving semesters 1–4 of one programme
  /// under semester 5 of another is the same overlap in slower motion.
  ///
  /// Destructive and not undoable — the caller must have the user's explicit
  /// confirmation, and the cloud copy is overwritten by the backup that follows
  /// the import.
  Future<void> clearAllAcademicData() async {
    final db = await DBHelper.instance.database;
    // One transaction so a failure part-way leaves the old data intact rather
    // than half a course. Order respects the foreign keys even though they
    // cascade, so the intent reads plainly.
    await db.transaction((txn) async {
      await txn.delete('attendance_records');
      await txn.delete('timetable');
      await txn.delete('subjects');
      await txn.delete('imported_report_dates');
    });

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (_reportDerivedKeys.contains(key) || _isSemesterBound(key)) {
        await prefs.remove(key);
      }
    }
    debugPrint('[Reset] Cleared local academic data for a new course');
  }
}
