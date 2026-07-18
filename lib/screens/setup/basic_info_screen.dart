import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../database/attendance_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';
import '../setup/attendance_criteria_screen.dart';
import '../../services/cloud_sync_service.dart';

class BasicInfoScreen extends StatefulWidget {
  final bool isEditMode;
  final Map<String, dynamic>? prefilledData;

  const BasicInfoScreen({super.key, required this.isEditMode, this.prefilledData});

  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  final _nameController = TextEditingController();
  final _courseController = TextEditingController();
  final _yearController = TextEditingController();

  int _selectedSemester = 1;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadSavedData();
    } else if (widget.prefilledData != null) {
      _loadPrefilledData();
    }
  }

  void _loadPrefilledData() {
    final data = widget.prefilledData!;
    _nameController.text = data['name']?.toString() ?? data['studentName']?.toString() ?? '';
    _courseController.text = data['course']?.toString() ?? '';
    _yearController.text = data['year']?.toString() ?? '';
    if (data['startDate'] != null && data['startDate'].toString().isNotEmpty) {
      _startDate = DateTime.tryParse(data['startDate']);
    }
    if (data['endDate'] != null && data['endDate'].toString().isNotEmpty) {
      _endDate = DateTime.tryParse(data['endDate']);
    }

    final semStr = data['semester']?.toString().toLowerCase().trim() ?? '';
    int semNum = _parseSemesterNumber(semStr);

    setState(() {
      _selectedSemester = semNum;
    });
  }

  /// Parses a semester string like "Semester III", "sem 3", "3", "iii" etc.
  int _parseSemesterNumber(String s) {
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
    return 1;
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('full_name') ?? '';
      _courseController.text = prefs.getString('course') ?? '';
      _yearController.text = prefs.getString('year') ?? '';
      _selectedSemester = prefs.getInt('semester') ?? 1;
    });
    await _loadDatesForSemester(_selectedSemester);
  }

  Future<void> _loadDatesForSemester(int sem) async {
    final prefs = await SharedPreferences.getInstance();
    final start = prefs.getString('semester_start_$sem');
    final end = prefs.getString('semester_end_$sem');
    setState(() {
      _startDate = start != null ? DateTime.parse(start) : null;
      _endDate = end != null ? DateTime.parse(end) : null;
    });
  }

  Future<void> _pickDate(bool isStartDate) async {
    DateTime minDate = isStartDate ? DateTime(2020) : (_startDate ?? DateTime(2020));
    DateTime maxDate = isStartDate ? (_endDate ?? DateTime(2030)) : DateTime(2030);

    DateTime initial = isStartDate
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());
    if (initial.isBefore(minDate)) initial = minDate;
    if (initial.isAfter(maxDate)) initial = maxDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: maxDate,
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _saveAndNext() async {
    if (_nameController.text.trim().isEmpty ||
        _courseController.text.trim().isEmpty ||
        _yearController.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields, including both dates'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('full_name', _nameController.text.trim());
    await prefs.setString('course', _courseController.text.trim());
    await prefs.setString('year', _yearController.text.trim());
    await prefs.setInt('semester', _selectedSemester);

    final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);
    await prefs.setString('semester_start_$_selectedSemester', startStr);
    await prefs.setString('semester_end_$_selectedSemester', endStr);

    if (widget.isEditMode) {
      final db = await DBHelper.instance.database;
      await db.rawDelete(
        '''DELETE FROM attendance_records WHERE id IN (
             SELECT a.id FROM attendance_records a
             INNER JOIN timetable t ON a.timetable_entry_id = t.id
             INNER JOIN subjects s ON t.subject_id = s.id
             WHERE s.semester = ? AND length(a.date) = 10
               AND (a.date < ? OR a.date > ?)
           )''',
        [_selectedSemester, startStr, endStr],
      );
    } else if (widget.prefilledData != null &&
        widget.prefilledData!['subjects'] != null) {
      final List<dynamic> subs = widget.prefilledData!['subjects'];
      if (subs.isNotEmpty) {
        final db = await DBHelper.instance.database;
        final subjectDao = SubjectDao();
        final timetableDao = TimetableDao();
        final attendanceDao = AttendanceDao();

        // Step 1: Wipe all old data for this semester (clean re-import)
        await db.rawDelete('''
          DELETE FROM attendance_records WHERE timetable_entry_id IN (
            SELECT t.id FROM timetable t
            INNER JOIN subjects s ON t.subject_id = s.id
            WHERE s.semester = ?
          )
        ''', [_selectedSemester]);

        for (int day = 0; day <= 7; day++) {
          await timetableDao.deleteEntriesForDay(day, _selectedSemester);
        }

        final oldSubjects = await subjectDao.getSubjectsBySemester(_selectedSemester);
        for (final sub in oldSubjects) {
          await subjectDao.deleteSubject(sub.id!);
        }

        // Step 2: Insert subjects
        for (var sub in subs) {
          final subName = sub.toString().trim();
          if (subName.isNotEmpty) {
            await subjectDao.insertSubject(Subject(
              name: subName,
              requiredPercent: 75.0,
              semester: _selectedSemester,
            ));
          }
        }

        // Build name -> id map
        final Map<String, int> subjectNameToId = {};
        final insertedSubjects = await subjectDao.getSubjectsBySemester(_selectedSemester);
        for (var sub in insertedSubjects) {
          subjectNameToId[sub.name] = sub.id!;
        }

        // Step 3A: Create seed timetable slots (day=0) for every subject
        final Map<int, int> subjectIdToSeedEntryId = {};
        for (final subId in subjectNameToId.values) {
          final seedId = await timetableDao.ensureSeedEntry(subId);
          subjectIdToSeedEntryId[subId] = seedId;
        }

        // Step 3B: Insert real-dated records from AI (populates the calendar)
        final Map<String, int> insertedP = {};
        final Map<String, int> insertedA = {};

        final rawRecords = widget.prefilledData!['attendanceRecords'];
        if (rawRecords != null && rawRecords is List) {
          for (final rec in rawRecords) {
            var dateStr = rec['date']?.toString().trim();
            final subName = rec['subject']?.toString().trim();
            final status = rec['status']?.toString().toUpperCase();

            if (dateStr == null || subName == null || status == null) continue;
            if (status != 'P' && status != 'A' && status != 'NU') continue;
            // The local parser appends '_N' for same-day lectures to prevent DB overwrite
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
        }

        // Step 3C: Pad with pseudo-dates to match authoritative subjectStats counts
        // Guarantees accurate stats even if AI underextracted records in Step 3B.
        final subjectStats = widget.prefilledData!['subjectStats'];
        if (subjectStats != null && subjectStats is Map) {
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
        // Step 3D: Insert inferred timetable entries
        final inferredTimetable = widget.prefilledData!['inferredTimetable'] as Map<String, dynamic>?;
        if (inferredTimetable != null) {
          for (final dayEntry in inferredTimetable.entries) {
            final dayOfWeek = int.tryParse(dayEntry.key);
            if (dayOfWeek == null) continue;
            final subjectsForDay = dayEntry.value as List<dynamic>;
            for (int i = 0; i < subjectsForDay.length; i++) {
              final subName = subjectsForDay[i].toString();
              final subId = subjectNameToId[subName];
              if (subId != null) {
                await timetableDao.insertEntry(
                  TimetableEntry(
                    dayOfWeek: dayOfWeek,
                    subjectId: subId,
                    lectureOrder: i,
                  ),
                );
              }
            }
          }
        }
      }
    }

    if (!mounted) return;

    // Auto-sync after saving basic info
    CloudSyncService().backupDataToCloud();

    if (widget.isEditMode) {
      Navigator.pop(context);
    } else {
      context.go('/setup/basic/criteria');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isEditMode ? 'Edit your details' : "Let's get to know you",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 32),

              _inputField(_nameController, 'Full Name', theme),
              _inputField(_courseController, 'Course', theme),
              _inputField(_yearController, 'Year', theme),

              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedSemester,
                decoration: _inputDecoration('Semester', theme),
                dropdownColor: theme.cardColor,
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                items: List.generate(
                  8,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Semester ${i + 1}'),
                  ),
                ),
                onChanged: (value) async {
                  if (value != null) {
                    setState(() => _selectedSemester = value);
                    await _loadDatesForSemester(value);
                  }
                },
              ),

              const SizedBox(height: 16),
              _dateTile(
                label: 'Semester Start Date *',
                date: _startDate,
                onTap: () => _pickDate(true),
                theme: theme,
              ),
              const SizedBox(height: 12),
              _dateTile(
                label: 'Semester End Date *',
                date: _endDate,
                onTap: () => _pickDate(false),
                theme: theme,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  border: Border.all(color: Colors.amber.shade700.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Attendance history is STRICTLY bound by these dates. Classes occurring outside this timeframe are ignored! Ensure they match your report.",
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (widget.isEditMode) {
                          Navigator.pop(context);
                        } else {
                          context.go('/setup');
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveAndNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        widget.isEditMode ? 'Save Changes' : 'Next',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        decoration: _inputDecoration(label, theme),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? label : DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(
                  color: date == null ? Colors.grey : theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.calendar_today, size: 18, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, ThemeData theme) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _courseController.dispose();
    _yearController.dispose();
    super.dispose();
  }
}
