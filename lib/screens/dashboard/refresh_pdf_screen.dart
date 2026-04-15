import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        _statusMessage = 'Uploading to Gemini AI...';
      });

      final uri = Uri.parse('https://attendease-backend-ndxs.onrender.com/api/extract-setup-data');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'report',
          fileBytes,
          filename: result.files.first.name,
          contentType: MediaType('application', 'pdf'),
        ),
      );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        String serverMsg = 'Server error: ${response.statusCode}';
        try {
          final errJson = json.decode(responseData);
          if (errJson['error'] != null) serverMsg = errJson['error'];
        } catch (_) {}
        throw Exception(serverMsg);
      }

      final jsonResult = json.decode(responseData);
      if (jsonResult['success'] != true) {
        throw Exception(jsonResult['error'] ?? 'Unknown error occurred.');
      }

      final extractedStr = jsonResult['data'];
      if (extractedStr == null) throw Exception('No data returned from AI.');

      final cleanedStr = extractedStr
          .toString()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final Map<String, dynamic> data = json.decode(cleanedStr);

      setState(() => _statusMessage = 'Syncing records to database...');
      await _applyData(data);

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
        final displayErr = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $displayErr'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _applyData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final activeSemester = prefs.getInt('semester') ?? 1;

    final subjectDao = SubjectDao();
    final timetableDao = TimetableDao();
    final attendanceDao = AttendanceDao();

    // Step 1: Sync subjects — add new ones, never delete existing
    final List<dynamic> newSubjects = data['subjects'] ?? [];
    final existing = await subjectDao.getSubjectsBySemester(activeSemester);
    final existingNames = existing.map((s) => s.name).toSet();

    for (var sub in newSubjects) {
      final subName = sub.toString().trim();
      if (subName.isNotEmpty && !existingNames.contains(subName)) {
        await subjectDao.insertSubject(
          Subject(name: subName, requiredPercent: 75.0, semester: activeSemester),
        );
      }
    }

    // Build name → id map
    final allSubjects = await subjectDao.getSubjectsBySemester(activeSemester);
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

    final List<dynamic> records = data['attendanceRecords'] ?? [];
    for (final rec in records) {
      var dateStr = rec['date']?.toString().trim();
      final subName = rec['subject']?.toString().trim();
      final status = rec['status']?.toString().toUpperCase();

      if (dateStr == null || subName == null || status == null) continue;
      if (status != 'P' && status != 'A') continue;

      // Smart Date Parsing
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate == null) {
        debugPrint('Skipping invalid date format: "$dateStr"');
        continue;
      }
      
      // Enforce strict YYYY-MM-DD format for DB/Calendar compatibility
      dateStr = '${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';

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

    // Step 3B: Wipe old pseudo-dates before re-padding (avoid double-counting)
    final db = await DBHelper.instance.database;
    await db.rawDelete('''
      DELETE FROM attendance_records
      WHERE length(date) != 10
        AND timetable_entry_id IN (
          SELECT t.id FROM timetable t
          INNER JOIN subjects s ON t.subject_id = s.id
          WHERE s.semester = ?
        )
    ''', [activeSemester]);

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
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon with gradient glow
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isDone
                          ? [Colors.green.shade400, Colors.teal.shade400]
                          : [const Color(0xFF6366F1), const Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isDone ? Colors.green : const Color(0xFF6366F1))
                            .withOpacity(0.35),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isDone ? Icons.check_circle_rounded : Icons.cloud_sync_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              Text(
                _isDone ? 'Sync Complete! ✓' : 'Sync Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
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
                      color: Colors.amber.withOpacity(isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          'New records will be merged with existing data',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
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
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _pickAndRefresh,
                    icon: const Icon(Icons.upload_file_rounded, size: 20),
                    label: const Text('Select PDF Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
