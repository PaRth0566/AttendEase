import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Make sure this path matches exactly where your DBHelper is located!
import '../../database/db_helper.dart';

class BackupSyncCard extends StatefulWidget {
  const BackupSyncCard({super.key});

  @override
  State<BackupSyncCard> createState() => _BackupSyncCardState();
}

class _BackupSyncCardState extends State<BackupSyncCard> {
  bool _isLoading = false;
  String _lastSyncTime = "Never";

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime(); // Load the saved time when the widget starts
  }

  // Fetch the saved time from local storage
  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastSyncTime = prefs.getString('last_sync_time') ?? "Never";
    });
  }

  Future<void> _handleManualBackup() async {
    // 1. Check internet before starting the loader
    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());

    // If offline, show error and STOP
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No internet connection. Connect to a network to backup.",
            ),
          ),
        );
      }
      return;
    }

    // 2. Internet is on, start loading animation
    setState(() => _isLoading = true);

    try {
      // 3. Get the currently logged-in user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("You must be logged in to backup data.");
      }

      // 4. Open the local SQLite database
      final db = await DBHelper.instance.database;

      // 5. Fetch all data from your local tables
      final subjects = await db.query('subjects');
      final timetable = await db.query('timetable');
      final attendanceRecords = await db.query('attendance_records');

      // 6. Package it all up into one Map
      final backupData = {
        'subjects': subjects,
        'timetable': timetable,
        'attendance_records': attendanceRecords,
        'last_backed_up':
            FieldValue.serverTimestamp(), // Saves the exact time on Firebase
      };

      // 7. Upload to Firestore under a 'users' collection -> their specific UID
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(backupData);

      // 8. Save the new time locally for the UI
      final currentTime = TimeOfDay.now().format(context);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync_time', currentTime);

      if (mounted) {
        setState(() {
          _lastSyncTime = currentTime;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Backup successful!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Backup failed: $e")));
      }
    } finally {
      // 9. Stop loader no matter what happens
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_sync_rounded, color: Color(0xFF2563EB)),
                    SizedBox(width: 12),
                    Text(
                      "Cloud Backup",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 36.0),
                  child: Text(
                    "Last sync: $_lastSyncTime",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _handleManualBackup,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                    ),
                    child: const Text("Sync Now"),
                  ),
          ],
        ),
      ),
    );
  }
}
