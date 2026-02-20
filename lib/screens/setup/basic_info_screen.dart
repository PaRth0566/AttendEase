import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';

class BasicInfoScreen extends StatefulWidget {
  final bool isEditMode;

  const BasicInfoScreen({super.key, required this.isEditMode});

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
    }
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

  // ✅ DYNAMIC DATE RESTRICTION APPLIED HERE
  Future<void> _pickDate(bool isStartDate) async {
    // 1. Determine safe minimum and maximum dates
    DateTime minDate = isStartDate
        ? DateTime(2020)
        : (_startDate ?? DateTime(2020));
    DateTime maxDate = isStartDate
        ? (_endDate ?? DateTime(2030))
        : DateTime(2030);

    // 2. Ensure initialDate is safely within min/max bounds
    DateTime initial = isStartDate
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());
    if (initial.isBefore(minDate)) initial = minDate;
    if (initial.isAfter(maxDate)) initial = maxDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate, // ✅ Locks days before the Start Date
      lastDate: maxDate, // ✅ Locks days after the End Date
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
              ),
            ),
          ),
          child: child!,
        );
      },
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
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
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 32),

              _inputField(_nameController, 'Full Name'),
              _inputField(_courseController, 'Course'),
              _inputField(_yearController, 'Year'),
              _inputField(_divisionController, 'Division'),

              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedSemester,
                decoration: _inputDecoration('Semester'),
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
              ),
              const SizedBox(height: 12),
              _dateTile(
                label: 'Semester End Date *',
                date: _endDate,
                onTap: () => _pickDate(false),
              ),
              const SizedBox(height: 32),

              Row(
                children: [
                  if (widget.isEditMode) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveAndNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
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

  Widget _inputField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: _inputDecoration(label),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? label : DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(
                  color: date == null ? Colors.grey : Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
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
