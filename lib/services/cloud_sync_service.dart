import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart'; // Ensure this path matches your project!
import '../utils/db_utils.dart';

/// Thrown inside the backup transaction to abort it when the cloud copy is
/// newer than the snapshot this device just took. A dedicated type keeps it
/// distinguishable from a genuine failure — the previous code threw a generic
/// `Exception('SKIP_BACKUP')` that the outer catch reported as an error.
class _SkipBackup implements Exception {
  const _SkipBackup();
}

class CloudSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSyncing = false;

  static const _prefsWhitelist = {
    'name',
    'full_name',
    'course',
    'semester',
    'semester_start_date',
    'semester_end_date',
    'last_sync_time',
    'manual_semester',
    'overall_required_attendance',
    'subject_required_attendance',
    'is_setup_complete',
  };

  // 1. BACKUP EVERYTHING (SQLite + SharedPreferences)
  Future<bool> backupDataToCloud() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      final user = _auth.currentUser;
      if (user == null || user.isAnonymous) {
        debugPrint('☁️ [Sync] Backup skipped: No user logged in or user is anonymous.');
        return false;
      }

      // Check network
      final List<ConnectivityResult> connectivityResult = await (Connectivity()
          .checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('☁️ [Sync] Backup skipped: No internet connection.');
        return false;
      }

      final db = await DBHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // Grab SQLite Data
      final subjects = await db.query('subjects');
      final timetable = await db.query('timetable');
      final attendanceRecords = await db.query('attendance_records');
      final importedReportDates = await db.query('imported_report_dates');

      debugPrint(
        '☁️ [Sync] Backing up: ${subjects.length} subjects, ${attendanceRecords.length} records.',
      );

      // Grab all SharedPreferences Data (Name, Course, Semester Dates, etc.)
      final Map<String, dynamic> userPrefs = {};
      for (String key in prefs.getKeys()) {
        if (_prefsWhitelist.contains(key) ||
            key.startsWith('semester_start_') ||
            key.startsWith('semester_end_')) {
          userPrefs[key] = prefs.get(key);
        }
      }

      final syncTime = DateTime.now().toUtc();
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      // Package it all together
      final backupData = {
        'preferences': userPrefs,
        'subjects': subjects,
        'timetable': timetable,
        'attendance_records': attendanceRecords,
        'imported_report_dates': importedReportDates,
        'last_backed_up': Timestamp.fromDate(syncTime),
        'app_version': appVersion, // Track version for migration safety
      };

      // Upload to Firestore with optimistic-locking transaction
      final userDoc = _firestore.collection('users').doc(user.uid);
      var skippedAsStale = false;
      try {
        await _firestore.runTransaction((txn) async {
          final snapshot = await txn.get(userDoc);
          if (snapshot.exists) {
            final existing = snapshot.data();
            if (existing != null && existing['last_backed_up'] is Timestamp) {
              final cloudTime = (existing['last_backed_up'] as Timestamp).toDate();
              if (cloudTime.isAfter(syncTime)) {
                debugPrint('☁️ [Sync] Cloud data is newer — skipping overwrite.');
                throw const _SkipBackup();
              }
            }
          }
          txn.set(userDoc, backupData);
        });
      } on _SkipBackup {
        // Not an error: another device wrote a newer backup while this one was
        // preparing. Declining to overwrite it is the correct outcome, but it
        // is also not a successful upload, so report false without logging a
        // failure the user would see as a broken sync.
        skippedAsStale = true;
      }
      if (skippedAsStale) return false;

      // Update local last sync time ONLY after successful upload
      final nowStr = syncTime.toIso8601String();
      await prefs.setString('last_sync_time', nowStr);

      debugPrint('☁️ [Sync] Backup Successful! Timestamp: $nowStr');
      return true;
    } catch (e) {
      debugPrint("☁️ [Sync] Backup Error: $e");
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  // 2. RESTORE EVERYTHING (Returns true if returning user, false if new user)
  Future<bool> restoreDataFromCloud() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      final user = _auth.currentUser;
      if (user == null || user.isAnonymous) {
        return false;
      }

      final docSnapshot = await _firestore.collection('users').doc(user.uid).get();

      // If no document exists, they are a brand new user
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        debugPrint('☁️ [Sync] Restore skipped: No cloud document found.');
        return false;
      }

      final data = docSnapshot.data()!;
      final db = await DBHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // Save the user's current local semester BEFORE restore so we can
      // protect it from being overwritten by an older cloud value.
      final int? localSemesterBeforeRestore = prefs.getInt('semester');
      debugPrint(
        '☁️ [Sync] Semester before restore: $localSemesterBeforeRestore (manual=${prefs.getBool('manual_semester') ?? false})',
      );

      debugPrint('☁️ [Sync] Starting Cloud Restoration...');

      // Keys that must always be stored as double (even when Firestore returns int)
      const doubleKeys = {'overall_required_attendance', 'subject_required_attendance'};

      // Keys that we intentionally skip during bulk restore and handle separately
      // 'semester' is protected so a stale cloud value doesn't overwrite the
      // locally-selected semester.
      const skipKeys = {'semester'};

      // 1. Restore SharedPreferences (Name, Course, Dates)
      final Map<String, dynamic> prefsData = data['preferences'] ?? {};
      if (prefsData.isNotEmpty) {
        for (var entry in prefsData.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value == null) continue;

          // Skip protected keys — handled separately below
          if (skipKeys.contains(key)) continue;

          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (doubleKeys.contains(key)) {
            // Always store known-double keys as double regardless of Firestore type
            await prefs.setDouble(key, (value as num).toDouble());
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is num) {
            if (value == value.toInt()) {
              await prefs.setInt(key, value.toInt());
            } else {
              await prefs.setDouble(key, value.toDouble());
            }
          }
        }
        debugPrint('☁️ [Sync] Restored ${prefsData.length} preferences.');
      }

      // 2 + 3. Wipe and restore SQLite data atomically.
      // The delete and re-inserts run in a single transaction so a failure
      // mid-restore rolls back completely, rather than leaving the user with
      // partially-restored or empty local data.
      final List<dynamic> subjects = data['subjects'] ?? [];
      final List<dynamic> timetable = data['timetable'] ?? [];
      final List<dynamic> attendanceRecords = data['attendance_records'] ?? [];
      final List<dynamic> importedReportDates = data['imported_report_dates'] ?? [];

      debugPrint(
        '☁️ [Sync] Restoring DB: ${subjects.length} subjects, ${attendanceRecords.length} records.',
      );

      await db.transaction((txn) async {
        await txn.delete('attendance_records');
        await txn.delete('timetable');
        await txn.delete('subjects');
        await txn.delete('imported_report_dates');

        for (var subject in subjects) {
          final sanitized = DbUtils.sanitizeRow(Map<String, dynamic>.from(subject));
          await txn.insert('subjects', sanitized, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (var session in timetable) {
          final sanitized = DbUtils.sanitizeRow(Map<String, dynamic>.from(session));
          await txn.insert('timetable', sanitized, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (var record in attendanceRecords) {
          final sanitized = DbUtils.sanitizeRow(Map<String, dynamic>.from(record));
          await txn.insert(
            'attendance_records',
            sanitized,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (var reportDate in importedReportDates) {
          final sanitized = DbUtils.sanitizeRow(Map<String, dynamic>.from(reportDate));
          await txn.insert(
            'imported_report_dates',
            sanitized,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (importedReportDates.isEmpty) {
          await txn.rawInsert('''
            INSERT OR IGNORE INTO imported_report_dates (semester, date)
            SELECT DISTINCT s.semester, substr(a.date, 1, 10)
            FROM attendance_records a
            INNER JOIN timetable t ON a.timetable_entry_id = t.id
            INNER JOIN subjects s ON t.subject_id = s.id
            WHERE a.source = 'pdf'
              AND a.date NOT LIKE 'pad_%'
              AND length(a.date) >= 10
          ''');
        }
      });

      // 4. Robust Semester Resolution
      // Priority order:
      //   1. Local semester the user had selected before restore (highest priority)
      //   2. Semester from the cloud backup (if local had none)
      //   3. Auto-detected from the highest semester in the restored subjects
      //   4. Default to 1 only if no subjects exist at all
      if (localSemesterBeforeRestore != null) {
        // User already had a semester selected locally — keep it.
        await prefs.setInt('semester', localSemesterBeforeRestore);
        debugPrint('☁️ [Sync] Kept local semester: $localSemesterBeforeRestore');
      } else {
        // No local semester — try to use cloud value first
        final cloudSem = prefsData['semester'];
        int? cloudSemInt;
        if (cloudSem is int) {
          cloudSemInt = cloudSem;
        } else if (cloudSem is num) {
          cloudSemInt = cloudSem.toInt();
        }

        if (cloudSemInt != null && cloudSemInt >= 1) {
          await prefs.setInt('semester', cloudSemInt);
          debugPrint('☁️ [Sync] Restored semester from cloud: $cloudSemInt');
        } else {
          // Fall back: detect from the highest semester present in subjects
          final semResult = await db.rawQuery(
            'SELECT DISTINCT semester FROM subjects ORDER BY semester DESC LIMIT 1',
          );
          if (semResult.isNotEmpty) {
            final detectedSem = semResult.first['semester'];
            int? target;
            if (detectedSem is int) {
              target = detectedSem;
            } else if (detectedSem is num) {
              target = detectedSem.toInt();
            }

            if (target != null) {
              await prefs.setInt('semester', target);
              debugPrint('☁️ [Sync] Auto-detected semester from subjects: $target');
            }
          } else {
            // Only default to 1 if we literally have NO subjects
            await prefs.setInt('semester', 1);
            debugPrint('☁️ [Sync] No subjects found, defaulting to Semester 1');
          }
        }
      }

      // Update local sync time after successful restore
      if (data.containsKey('last_backed_up') && data['last_backed_up'] is Timestamp) {
        final cloudTs = data['last_backed_up'] as Timestamp;
        await prefs.setString('last_sync_time', cloudTs.toDate().toIso8601String());
      } else {
        await prefs.setString('last_sync_time', DateTime.now().toUtc().toIso8601String());
      }
      debugPrint('☁️ [Sync] Restoration Complete!');

      return true;
    } catch (e) {
      debugPrint("☁️ [Sync] Restore Error: $e");
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  // 3. BIDIRECTIONAL SYNC
  Future<String> syncBidirectional() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no_user';
      // A guest has no cloud document by design. Reporting this as 'no_user'
      // told them to log in when they already were; 'guest' lets the UI
      // explain that cloud backup needs a real account.
      if (user.isAnonymous) return 'guest';

      if (_isSyncing) return 'syncing';

      final List<ConnectivityResult> connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) return 'no_network';

      final userDoc = _firestore.collection('users').doc(user.uid);
      final docSnapshot = await userDoc.get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        bool success = await backupDataToCloud();
        return success ? 'backed_up' : 'error';
      }

      final data = docSnapshot.data()!;
      final prefs = await SharedPreferences.getInstance();

      // Compare timestamps
      DateTime? cloudTime;
      final cloudTimestamp = data['last_backed_up'];
      if (cloudTimestamp is Timestamp) {
        cloudTime = cloudTimestamp.toDate();
      }

      DateTime? localTime;
      final localTimeStr = prefs.getString('last_sync_time');
      if (localTimeStr != null && localTimeStr != 'Never') {
        try {
          localTime = DateTime.parse(localTimeStr);
        } catch (_) {}
      }

      debugPrint('☁️ [Sync] Comparing: Cloud($cloudTime) vs Local($localTime)');

      // If cloud is newer than local (by at least 1 second to avoid clock jitter), restore
      if (cloudTime != null &&
          (localTime == null || cloudTime.difference(localTime).inSeconds > 1)) {
        debugPrint('☁️ [Sync] Cloud is newer. Restoring...');
        bool success = await restoreDataFromCloud();
        return success ? 'restored' : 'error';
      } else {
        debugPrint('☁️ [Sync] Local is newer or same. Backing up...');
        bool success = await backupDataToCloud();
        return success ? 'backed_up' : 'error';
      }
    } catch (e) {
      debugPrint("☁️ [Sync] Bidirectional Sync Error: $e");
      return 'error';
    }
  }
}
