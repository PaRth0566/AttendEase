import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import 'add_subjects_screen.dart';

class AttendanceCriteriaScreen extends StatefulWidget {
  final bool isEditMode;

  const AttendanceCriteriaScreen({super.key, this.isEditMode = false});

  @override
  State<AttendanceCriteriaScreen> createState() =>
      _AttendanceCriteriaScreenState();
}

class _AttendanceCriteriaScreenState extends State<AttendanceCriteriaScreen> {
  final TextEditingController overallController = TextEditingController();
  final TextEditingController subjectController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final overall = prefs.getDouble('overall_required_attendance');
    final subject = prefs.getDouble('subject_required_attendance');

    if (overall != null) overallController.text = overall.toString();
    if (subject != null) subjectController.text = subject.toString();
  }

  Future<void> _saveData() async {
    final overall = double.tryParse(overallController.text.trim());
    final subject = double.tryParse(subjectController.text.trim());

    if (overall == null || subject == null) {
      _showError('Please enter valid percentages');
      return;
    }

    if (overall <= 0 || overall > 100 || subject <= 0 || subject > 100) {
      _showError('Percentage must be between 1 and 100');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('overall_required_attendance', overall);
    await prefs.setDouble('subject_required_attendance', subject);

    final subjectDao = SubjectDao();
    final existingSubjects = await subjectDao.getAllSubjects();

    for (final s in existingSubjects) {
      await subjectDao.updateSubject(
        Subject(
          id: s.id,
          name: s.name,
          requiredPercent: subject,
          semester: s.semester,
        ),
      );
    }

    if (!mounted) return;

    if (widget.isEditMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance criteria saved')),
      );
      Navigator.pop(context);
    } else {
      // ✅ NAVIGATION FIX: Uses push so back button works!
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddSubjectsScreen()),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Colors.grey,
        fontWeight: FontWeight.normal,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance Requirements',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              'Overall Attendance Required (%)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: overallController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputStyle('e.g. 75'),
            ),

            const SizedBox(height: 24),

            const Text(
              'Minimum Attendance Per Subject (%)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: subjectController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputStyle('e.g. 70'),
            ),

            const Spacer(),

            // ✅ UNIFIED BUTTON ROW
            Row(
              children: [
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
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveData,
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
