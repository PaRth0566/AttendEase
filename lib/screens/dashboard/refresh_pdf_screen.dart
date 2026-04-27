import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/local_pdf_parser.dart';
import '../../services/cloud_sync_service.dart';

import '../../database/attendance_dao.dart';
import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';

class RefreshPdfScreen extends StatefulWidget {
  const RefreshPdfScreen({super.key});

  @override
  State<RefreshPdfScreen> createState() => _RefreshPdfScreenState();
}

class _RefreshPdfScreenState extends State<RefreshPdfScreen> {
  bool _isUploading = false;
  String _statusMessage = 'Select your latest attendance PDF to sync new records.';
  bool _isDone = false;

  Future<void> _pickAndRefresh() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        _showError('Could not read the selected PDF file.');
        return;
      }

      setState(() {
        _isUploading = true;
        _isDone = false;
        _statusMessage = 'Reading your attendance report...';
      });

      final Map<String, dynamic> data =
          await LocalPdfParser.extractAttendanceFromPdf(fileBytes);

      setState(() => _statusMessage = 'Updating your records...');
      await _applyData(data);

      setState(() => _statusMessage = 'Saving to cloud...');
      await CloudSyncService().backupDataToCloud();

      setState(() {
        _isUploading = false;
        _isDone = true;
        _statusMessage = 'Done! Your attendance records have been updated.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'Select your latest attendance PDF to sync new records.';
        });
        // Determine a user-friendly message based on the error type
        String friendlyMsg;
        final raw = e.toString();
        if (e is FormatException) {
          // The parser now throws a user-friendly message — use it directly
          friendlyMsg = e.message;
        } else if (raw.contains('No such file') || raw.contains('FileSystemException')) {
          friendlyMsg = 'The selected file could not be accessed. Please try selecting it again.';
        } else {
          friendlyMsg = 'Something went wrong. Please try again with a valid attendance PDF.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMsg),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  int _parseSemesterNumber(String s, int fallback) {
    final digitMatch = RegExp(r'\b([1-8])\b').firstMatch(s);
    if (digitMatch != null) return int.parse(digitMatch.group(1)!);
    if (RegExp(r'\bviii\b').hasMatch(s)) return 8;
    if (RegExp(r'\bvii\b').hasMatch(s))  return 7;
    if (RegExp(r'\bvi\b').hasMatch(s))   return 6;
    if (RegExp(r'\biv\b').hasMatch(s))   return 4;
    if (RegExp(r'\bv\b').hasMatch(s))    return 5;
    if (RegExp(r'\biii\b').hasMatch(s))  return 3;
    if (RegExp(r'\bii\b').hasMatch(s))   return 2;
    if (RegExp(r'\bi\b').hasMatch(s))    return 1;
    return fallback;
  }

  Future<void> _applyData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final activeSemester = prefs.getInt('semester') ?? 1;
    
    final semStr = data['semester']?.toString().toLowerCase().trim() ?? '';
    int targetSemester = activeSemester;
    if (semStr.isNotEmpty) {
       targetSemester = _parseSemesterNumber(semStr, activeSemester);
    }

    // Automatically switch the user to the newly uploaded semester
    await prefs.setInt('semester', targetSemester);

    final subjectDao = SubjectDao();
    final timetableDao = TimetableDao();
    final attendanceDao = AttendanceDao();

    // Step 0: Aggressive Wipe of Existing Semester Data
    // We actively delete the subjects for the TARGET semester. 
    // Thanks to ON DELETE CASCADE set up in db_helper.dart, this automatically 
    // annihilates all orphaned timetable and attendance_record rows instantly.
    final db = await DBHelper.instance.database;
    await db.delete(
      'subjects',
      where: 'semester = ?',
      whereArgs: [targetSemester],
    );

    // Step 1: Insert new subjects from PDF
    final List<dynamic> newSubjects = data['subjects'] ?? [];
    for (var sub in newSubjects) {
      final subName = sub.toString().trim();
      if (subName.isNotEmpty) {
        await subjectDao.insertSubject(
          Subject(name: subName, requiredPercent: 75.0, semester: targetSemester),
        );
      }
    }

    // Build name → id map
    final allSubjects = await subjectDao.getSubjectsBySemester(targetSemester);
    final Map<String, int> subjectNameToId = {
      for (var s in allSubjects) s.name: s.id!
    };

    // Step 2: Ensure seed slots (day=0) exist for all subjects
    final Map<int, int> subjectIdToSeedEntryId = {};
    for (final subId in subjectNameToId.values) {
      final seedId = await timetableDao.ensureSeedEntry(subId);
      subjectIdToSeedEntryId[subId] = seedId;
    }

    // Step 3A: Insert real-dated records from AI (populates calendar heatmap)
    final Map<String, int> insertedP = {};
    final Map<String, int> insertedA = {};

    // Update bounds based on the new PDF if it included them
    if (data['startDate'] != null && data['startDate'].toString().isNotEmpty &&
        data['endDate'] != null && data['endDate'].toString().isNotEmpty) {
      final startStr = data['startDate'].toString();
      final endStr = data['endDate'].toString();
      // Only update if they parse successfully
      if (DateTime.tryParse(startStr) != null && DateTime.tryParse(endStr) != null) {
        await prefs.setString('semester_start_$targetSemester', startStr);
        await prefs.setString('semester_end_$targetSemester', endStr);
        debugPrint('Updated semester bounds from new PDF: $startStr to $endStr');
      }
    }

    final List<dynamic> records = data['attendanceRecords'] ?? [];
    for (final rec in records) {
      var dateStr = rec['date']?.toString().trim();
      final subName = rec['subject']?.toString().trim();
      final status = rec['status']?.toString().toUpperCase();

      if (dateStr == null || subName == null || status == null) continue;
      if (status != 'P' && status != 'A') continue;

      // Smart Date Parsing, preserving index suffix if any
      final parts = dateStr.split('_');
      final parsedDate = DateTime.tryParse(parts[0]);
      if (parsedDate == null) {
        debugPrint('Skipping invalid date format: "$dateStr"');
        continue;
      }
      
      // Enforce strict YYYY-MM-DD format for DB/Calendar compatibility
      final prefix = '${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';
      dateStr = parts.length > 1 ? '${prefix}_${parts[1]}' : prefix;

      final subId = subjectNameToId[subName];
      if (subId == null) continue;
      final seedEntryId = subjectIdToSeedEntryId[subId];
      if (seedEntryId == null) continue;

      await attendanceDao.upsertAttendance(
        timetableId: seedEntryId,
        date: dateStr,
        status: status,
      );

      if (status == 'P') {
        insertedP[subName] = (insertedP[subName] ?? 0) + 1;
      } else {
        insertedA[subName] = (insertedA[subName] ?? 0) + 1;
      }
    }

    // Step 3B: (Wiping old pseudo-dates is no longer necessary as Step 0 cleared all records)

    // Step 3C: Pad pseudo-dates to match authoritative subjectStats counts
    final subjectStats = data['subjectStats'] as Map<String, dynamic>? ?? {};
    for (final entry in subjectStats.entries) {
      final subjectName = entry.key.toString().trim();
      final stats = entry.value;
      if (stats == null) continue;

      final int targetP = (stats['attended'] as num?)?.toInt() ?? 0;
      final int targetTotal = (stats['total'] as num?)?.toInt() ?? 0;
      final int targetA = targetTotal - targetP;

      final subId = subjectNameToId[subjectName];
      if (subId == null) continue;
      final seedEntryId = subjectIdToSeedEntryId[subId];
      if (seedEntryId == null) continue;

      final int gotP = insertedP[subjectName] ?? 0;
      final int gotA = insertedA[subjectName] ?? 0;
      final int needP = (targetP - gotP).clamp(0, 99999);
      final int needA = (targetA - gotA).clamp(0, 99999);

      for (int i = 0; i < needP; i++) {
        await attendanceDao.upsertAttendance(
          timetableId: seedEntryId,
          date: 'pad_P_${subId}_$i',
          status: 'P',
        );
      }
      for (int i = 0; i < needA; i++) {
        await attendanceDao.upsertAttendance(
          timetableId: seedEntryId,
          date: 'pad_A_${subId}_$i',
          status: 'A',
        );
      }
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sync New Report'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.textTheme.bodyLarge?.color,
        leading: BackButton(onPressed: () => Navigator.pop(context, _isDone)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
            vertical: 24,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isDone 
                        ? Colors.green.withOpacity(isDark ? 0.15 : 0.1)
                        : theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.1),
                    border: Border.all(
                      color: _isDone 
                          ? Colors.green.withOpacity(0.5)
                          : theme.colorScheme.primary.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isDone ? Icons.check_rounded : Icons.cloud_sync_rounded,
                    size: 48,
                    color: _isDone ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              Text(
                _isDone ? 'Sync Complete' : 'Sync Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.6, color: theme.textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 16),

              if (!_isDone && !_isUploading)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Note: Semester is auto-detected. Only that specific semester will be updated, leaving others untouched.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? theme.colorScheme.primary.withAlpha(200) : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 48),

              if (_isUploading)
                Column(
                  children: [
                    CircularProgressIndicator(color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else if (_isDone)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _pickAndRefresh,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Select PDF Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}
