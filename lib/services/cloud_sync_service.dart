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
        if (entry.value is String)
          await prefs.setString(entry.key, entry.value);
        if (entry.value is int) await prefs.setInt(entry.key, entry.value);
        if (entry.value is double)
          await prefs.setDouble(entry.key, entry.value);
        if (entry.value is bool) await prefs.setBool(entry.key, entry.value);
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
        await db.insert(
          'subjects',
          Map<String, dynamic>.from(subject),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (var session in timetable) {
        await db.insert(
          'timetable',
          Map<String, dynamic>.from(session),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (var record in attendanceRecords) {
        await db.insert(
          'attendance_records',
          Map<String, dynamic>.from(record),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return true; // Successfully restored data for a returning user!
    } catch (e) {
      print("Restore Error: $e");
      return false;
    }
  }
}
