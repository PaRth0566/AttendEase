import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import 'add_subjects_screen.dart';
import '../../database/db_helper.dart';
import '../../services/cloud_sync_service.dart';

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
      // Auto-sync after editing criteria
      CloudSyncService().backupDataToCloud();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance criteria saved')),
      );
      Navigator.pop(context);
    } else {
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

  InputDecoration _inputStyle(String hint, ThemeData theme) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: theme.textTheme.bodyMedium?.color,
        fontWeight: FontWeight.normal,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // ✅ Dynamic Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Requirements',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color, // ✅ Dynamic Title
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Overall Attendance Required (%)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color, // ✅ Dynamic subtitle
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: overallController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
              ), // ✅ Typing color
              decoration: _inputStyle('e.g. 75', theme),
            ),

            const SizedBox(height: 24),

            Text(
              'Minimum Attendance Per Subject (%)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color, // ✅ Dynamic subtitle
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: subjectController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
              ), // ✅ Typing color
              decoration: _inputStyle('e.g. 70', theme),
            ),

            const Spacer(),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
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
                    onPressed: _saveData,
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
            const SizedBox(height: 16),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
