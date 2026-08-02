import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/pdf_attendance_import_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_buttons.dart';

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

  /// True while [_saveAndNext] is writing prefs and importing the PDF. Drives
  /// the Next button's spinner and blocks a second submit — a fast double-tap
  /// previously fired the import twice and double-wrote rows.
  bool _isSaving = false;

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
    // Block re-entry: the import below is the slow, side-effecting part and a
    // double-tap must not run it twice.
    if (_isSaving) return;

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

    setState(() => _isSaving = true);
    try {
      await _persistAndImport();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _persistAndImport() async {
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
        await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
          data: widget.prefilledData!,
          semester: _selectedSemester,
          updateSemesterBounds: false,
        );
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
            constraints: const BoxConstraints(maxWidth: 600),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppBreakpoints.isMobile(context) ? 24 : 40,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isEditMode
                                ? 'Edit your details'
                                : "Let's get to know you",
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
                            initialValue: _selectedSemester,
                            decoration: _inputDecoration('Semester', theme),
                            dropdownColor: theme.cardColor,
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                            ),
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
                              color: Colors.amber.withValues(alpha: 0.15),
                              border: Border.all(
                                color: Colors.amber.shade700.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Attendance history is STRICTLY bound by these dates. Classes occurring outside this timeframe are ignored! Ensure they match your report.",
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color:
                                          Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.amber.shade200
                                              : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),

                      SetupNavButtons(
                        onBack: () {
                          if (widget.isEditMode) {
                            Navigator.pop(context);
                          } else {
                            context.go('/setup');
                          }
                        },
                        onNext: _saveAndNext,
                        nextLabel: widget.isEditMode ? 'Save Changes' : 'Next',
                        nextLoading: _isSaving,
                      ),
                    ],
                  ),
                ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
