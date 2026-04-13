import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';

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
  final _divisionController = TextEditingController();

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
    _nameController.text = data['studentName']?.toString() ?? '';
    _courseController.text = data['course']?.toString() ?? '';
    _yearController.text = data['year']?.toString() ?? '';
    
    final semStr = data['semester']?.toString().toLowerCase() ?? '1';
    int semNum = 1;
    if (semStr.contains('1') || semStr.contains('i') && !semStr.contains('ii') && !semStr.contains('iv') && !semStr.contains('vi')) semNum = 1;
    if (semStr.contains('2') || semStr.contains('ii') && !semStr.contains('iii') && !semStr.contains('vii')) semNum = 2;
    if (semStr.contains('3') || semStr.contains('iii') && !semStr.contains('viii')) semNum = 3;
    if (semStr.contains('4') || semStr.contains('iv')) semNum = 4;
    if (semStr.contains('5') || semStr.contains('v') && !semStr.contains('iv') && !semStr.contains('vi')) semNum = 5;
    if (semStr.contains('6') || semStr.contains('vi') && !semStr.contains('vii')) semNum = 6;
    if (semStr.contains('7') || semStr.contains('vii') && !semStr.contains('viii')) semNum = 7;
    if (semStr.contains('8') || semStr.contains('viii')) semNum = 8;
    
    setState(() {
      _selectedSemester = semNum;
    });
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('full_name') ?? '';
      _courseController.text = prefs.getString('course') ?? '';
      _yearController.text = prefs.getString('year') ?? '';
      _divisionController.text = prefs.getString('division') ?? '';
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

  // ✅ UPDATED: Removed the forced Light Mode wrapper!
  Future<void> _pickDate(bool isStartDate) async {
    DateTime minDate = isStartDate
        ? DateTime(2020)
        : (_startDate ?? DateTime(2020));
    DateTime maxDate = isStartDate
        ? (_endDate ?? DateTime(2030))
        : DateTime(2030);

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
        _divisionController.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all required fields, including both dates',
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('full_name', _nameController.text.trim());
    await prefs.setString('course', _courseController.text.trim());
    await prefs.setString('year', _yearController.text.trim());
    await prefs.setString('division', _divisionController.text.trim());
    await prefs.setInt('semester', _selectedSemester);

    final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);
    await prefs.setString('semester_start_$_selectedSemester', startStr);
    await prefs.setString('semester_end_$_selectedSemester', endStr);

    if (widget.isEditMode) {
      final db = await DBHelper.instance.database;
      await db.rawDelete(
        '''DELETE FROM attendance_records WHERE id IN (SELECT a.id FROM attendance_records a INNER JOIN timetable t ON a.timetable_entry_id = t.id INNER JOIN subjects s ON t.subject_id = s.id WHERE s.semester = ? AND (a.date < ? OR a.date > ?))''',
        [_selectedSemester, startStr, endStr],
      );
    } else if (widget.prefilledData != null && widget.prefilledData!['subjects'] != null) {
      final List<dynamic> subs = widget.prefilledData!['subjects'];
      if(subs.isNotEmpty) {
        final subjectDao = SubjectDao();
        // Only insert if no subjects exist for this semester (prevents duplicates if user hits back and next again)
        final existing = await subjectDao.getSubjectsBySemester(_selectedSemester);
        if (existing.isEmpty) {
          for (var sub in subs) {
             final subName = sub.toString().trim();
             if(subName.isNotEmpty) {
                await subjectDao.insertSubject(Subject(
                  name: subName,
                  requiredPercent: 75.0,
                  semester: _selectedSemester
                ));
             }
          }
        }
      }
    }

    if (!mounted) return;

    if (widget.isEditMode) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamed(context, '/attendance-criteria');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // ✅ Dynamic background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isEditMode
                    ? 'Edit your details'
                    : "Let's get to know you",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color:
                      theme.textTheme.bodyLarge?.color, // ✅ Dynamic Title Color
                ),
              ),
              const SizedBox(height: 32),

              _inputField(_nameController, 'Full Name', theme),
              _inputField(_courseController, 'Course', theme),
              _inputField(_yearController, 'Year', theme),
              _inputField(_divisionController, 'Division', theme),

              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedSemester,
                decoration: _inputDecoration('Semester', theme),
                dropdownColor:
                    theme.cardColor, // ✅ Fixes invisible dropdowns in dark mode
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
              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        if (widget.isEditMode) {
                          Navigator.pop(context);
                        } else {
                          await AuthService().signOut();

                          if (!mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.isEditMode ? 'Save Changes' : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
    );
  }

  Widget _inputField(
    TextEditingController controller,
    String label,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
        ), // ✅ Dynamic typing color
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
          border: Border.all(color: theme.dividerColor), // ✅ Dynamic border
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? label : DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(
                  color: date == null
                      ? Colors.grey
                      : theme.textTheme.bodyLarge?.color, // ✅ Dynamic Text
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today,
              size: 18,
              color: theme.iconTheme.color,
            ), // ✅ Dynamic Icon
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, ThemeData theme) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: theme.textTheme.bodyMedium?.color,
      ), // ✅ Dynamic label
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor), // ✅ Dynamic border
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
    _divisionController.dispose();
    super.dispose();
  }
}
