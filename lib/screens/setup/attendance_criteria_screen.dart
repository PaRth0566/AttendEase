import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_buttons.dart';

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
    // Pre-fill defaults first — the user can always edit them
    overallController.text = '75';
    subjectController.text = '70';

    // Override with previously saved values if available
    final prefs = await SharedPreferences.getInstance();
    final overall = prefs.getDouble('overall_required_attendance');
    final subject = prefs.getDouble('subject_required_attendance');

    if (mounted) {
      if (overall != null) overallController.text = overall.toStringAsFixed(overall.truncateToDouble() == overall ? 0 : 1);
      if (subject != null) subjectController.text = subject.toStringAsFixed(subject.truncateToDouble() == subject ? 0 : 1);
    }
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
      context.go('/setup/basic/criteria/subjects');
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
      // Two text fields with no scroll view could not survive the soft
      // keyboard. The LayoutBuilder keeps the nav buttons pinned to the bottom
      // on a tall screen (minHeight + spaceBetween) while letting the whole
      // column scroll once the keyboard shrinks the viewport — a Spacer cannot
      // do that job inside a scroll view.
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
                            'Attendance Requirements',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Default values are pre-filled — edit them to match your college requirements.',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.7),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            'Overall Attendance Required (%)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color,
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
                            ),
                            decoration: _inputStyle('e.g. 75 (default)', theme),
                          ),

                          const SizedBox(height: 24),

                          Text(
                            'Minimum Attendance Per Subject (%)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color,
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
                            ),
                            decoration: _inputStyle('e.g. 70 (default)', theme),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),

                      SetupNavButtons(
                        onBack: () => Navigator.pop(context),
                        onNext: _saveData,
                        nextLabel: widget.isEditMode ? 'Save Changes' : 'Next',
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
}
