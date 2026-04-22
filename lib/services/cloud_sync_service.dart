import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart'; // Ensure this path matches your project!

class CloudSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. BACKUP EVERYTHING (SQLite + SharedPreferences)
  Future<bool> backupDataToCloud() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Check network
      final List<ConnectivityResult> connectivityResult = await (Connectivity()
          .checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) return false;

      final db = await DBHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // Grab SQLite Data
      final subjects = await db.query('subjects');
      final timetable = await db.query('timetable');
      final attendanceRecords = await db.query('attendance_records');

      // Grab all SharedPreferences Data (Name, Course, Semester Dates, etc.)
      final Map<String, dynamic> userPrefs = {};
      for (String key in prefs.getKeys()) {
        userPrefs[key] = prefs.get(key);
      }

      // Package it all together
      final backupData = {
        'preferences': userPrefs,
        'subjects': subjects,
        'timetable': timetable,
        'attendance_records': attendanceRecords,
        'last_backed_up': FieldValue.serverTimestamp(),
      };

      // Upload to Firestore
      await _firestore.collection('users').doc(user.uid).set(backupData);

      // Update local last sync time
      await prefs.setString('last_sync_time', DateTime.now().toString());
      return true;
    } catch (e) {
      print("Backup Error: $e");
      return false;
    }
  }

  // 2. RESTORE EVERYTHING (Returns true if returning user, false if new user)
  Future<bool> restoreDataFromCloud() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final docSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      // If no document exists, they are a brand new user
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return false;
      }

      final data = docSnapshot.data()!;
      final db = await DBHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore SharedPreferences (Name, Course, Dates)
      final Map<String, dynamic> prefsData = data['preferences'] ?? {};
      for (var entry in prefsData.entries) {
        final value = entry.value;
        if (value is String) {
          await prefs.setString(entry.key, value);
        } else if (value is bool) {
          // Check bool BEFORE int/num since Dart's bool is not a num
          await prefs.setBool(entry.key, value);
        } else if (value is int) {
          await prefs.setInt(entry.key, value);
        } else if (value is double) {
          await prefs.setDouble(entry.key, value);
        } else if (value is num) {
          // Firestore can return numbers as 'num' in nested maps.
          // Decide if it's an int or double based on its actual value.
          if (value == value.toInt()) {
            await prefs.setInt(entry.key, value.toInt());
          } else {
            await prefs.setDouble(entry.key, value.toDouble());
          }
        }
      }

      // 2. Wipe current local SQLite data to avoid duplicates
      await db.delete('subjects');
      await db.delete('timetable');
      await db.delete('attendance_records');

      // 3. Restore SQLite Data
      final List<dynamic> subjects = data['subjects'] ?? [];
      final List<dynamic> timetable = data['timetable'] ?? [];
      final List<dynamic> attendanceRecords = data['attendance_records'] ?? [];

      for (var subject in subjects) {
        final sanitized = _sanitizeRow(Map<String, dynamic>.from(subject));
        await db.insert(
          'subjects',
          sanitized,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (var session in timetable) {
        final sanitized = _sanitizeRow(Map<String, dynamic>.from(session));
        await db.insert(
          'timetable',
          sanitized,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (var record in attendanceRecords) {
        final sanitized = _sanitizeRow(Map<String, dynamic>.from(record));
        await db.insert(
          'attendance_records',
          sanitized,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 4. Auto-detect semester if preferences didn't include it
      //    (handles old backups that didn't save preferences)
      if (!prefsData.containsKey('semester') || prefs.getInt('semester') == null) {
        final semResult = await db.rawQuery(
          'SELECT DISTINCT semester FROM subjects ORDER BY semester DESC LIMIT 1',
        );
        if (semResult.isNotEmpty) {
          final detectedSem = semResult.first['semester'];
          if (detectedSem is int) {
            await prefs.setInt('semester', detectedSem);
          } else if (detectedSem is num) {
            await prefs.setInt('semester', detectedSem.toInt());
          }
        }
      }

      // Update local sync time after successful restore
      await prefs.setString('last_sync_time', DateTime.now().toString());

      return true; // Successfully restored data for a returning user!
    } catch (e) {
      print("Restore Error: $e");
      return false;
    }
  }

  // 3. BIDIRECTIONAL SYNC — Pull from cloud first, then push local changes
  // Used by the "Sync Now" button to ensure both platforms stay in sync.
  // Returns 'restored' if cloud was newer (data pulled), 'backed_up' if
  // local was pushed, or 'error' / 'no_user' on failure.
  Future<String> syncBidirectional() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no_user';

      // Check network
      final List<ConnectivityResult> connectivityResult =
          await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return 'no_network';
      }

      final docSnapshot =
          await _firestore.collection('users').doc(user.uid).get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        // No cloud data — just backup local
        await backupDataToCloud();
        return 'backed_up';
      }

      final data = docSnapshot.data()!;
      final prefs = await SharedPreferences.getInstance();

      // Compare timestamps to decide direction
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

      // If cloud is newer than local, restore from cloud first
      if (cloudTime != null &&
          (localTime == null || cloudTime.isAfter(localTime))) {
        await restoreDataFromCloud();
        return 'restored';
      } else {
        // Local is newer or same — push to cloud
        await backupDataToCloud();
        return 'backed_up';
      }
    } catch (e) {
      print("Bidirectional Sync Error: $e");
      return 'error';
    }
  }

  /// Sanitizes a row from Firestore for safe SQLite insertion.
  /// Firestore stores all numbers as `num` (or sometimes `int` where `double`
  /// is expected). SQLite's sqflite driver is strict about types. This method
  /// ensures integer columns stay int and real columns stay double.
  Map<String, dynamic> _sanitizeRow(Map<String, dynamic> row) {
    final sanitized = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key;
      var value = entry.value;

      if (value is num) {
        // These columns are REAL in SQLite
        if (key == 'required_percent') {
          value = value.toDouble();
        } else {
          // All other numeric columns are INTEGER
          value = value.toInt();
        }
      }

      sanitized[key] = value;
    }
    return sanitized;
  }
}
