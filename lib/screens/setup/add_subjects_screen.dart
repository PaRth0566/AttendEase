import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_overlays.dart';

class AddSubjectsScreen extends StatefulWidget {
  final bool isEditMode;

  const AddSubjectsScreen({super.key, this.isEditMode = false});

  @override
  State<AddSubjectsScreen> createState() => _AddSubjectsScreenState();
}

class _AddSubjectsScreenState extends State<AddSubjectsScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final SubjectDao _subjectDao = SubjectDao();
  final TimetableDao _timetableDao = TimetableDao();

  List<Subject> _subjects = [];
  final List<int> _deletedSubjectIds = [];

  int _activeSemester = 1;
  double _defaultRequiredPercent = 75.0;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    _activeSemester = prefs.getInt('semester') ?? 1;
    _defaultRequiredPercent =
        prefs.getDouble('subject_required_attendance') ?? 75.0;

    final data = await _subjectDao.getSubjectsBySemester(_activeSemester);
    if (!mounted) return;

    setState(() {
      _subjects = data.toList();
      _deletedSubjectIds.clear();
    });
  }

  void _addSubject() {
    final name = _subjectController.text.trim();
    if (name.isEmpty) {
      _showError('Subject name cannot be empty');
      return;
    }

    setState(() {
      _subjects.add(
        Subject(
          name: name,
          requiredPercent: _defaultRequiredPercent,
          semester: _activeSemester,
        ),
      );
    });

    _subjectController.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _editSubject(int index) async {
    final subject = _subjects[index];
    final controller = TextEditingController(text: subject.name);

    await showAppDialog(
      context: context,
      builder: (_) => AlertDialog(
        // No style on either: dialogTheme.titleTextStyle already paints the
        // title in bodyLarge's colour at 18/bold, and the field's default is
        // bodyLarge. Both raw TextStyles only restated the colour, and a
        // hand-built TextStyle is what resets fontFamily to null. See
        // 
        title: const Text('Edit Subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Enter subject name',
            hintStyle: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              // labelLarge is 14/w600 — the same metrics textButtonTheme gives
              // this label — recoloured to read as neutral rather than as the
              // primary action. Derived from the theme so it keeps the bundled
              // font.
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              setState(() {
                _subjects[index] = Subject(
                  id: subject.id,
                  name: newName,
                  requiredPercent: subject.requiredPercent,
                  semester: subject.semester,
                );
              });

              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteSubject(int index) {
    setState(() {
      final removed = _subjects.removeAt(index);
      if (removed.id != null) {
        _deletedSubjectIds.add(removed.id!);
      }
    });
  }

  Future<void> _saveAndProceed() async {
    for (final id in _deletedSubjectIds) {
      await _subjectDao.deleteSubject(id);
    }

    for (final subject in _subjects) {
      if (subject.id == null) {
        await _subjectDao.insertSubject(subject);
      } else {
        await _subjectDao.updateSubject(subject);
      }
    }

    await _loadSubjects();

    // Ensure every subject has a seed slot (day=0) for calendar attendance
    final savedSubjects = await _subjectDao.getSubjectsBySemester(_activeSemester);
    for (final sub in savedSubjects) {
      await _timetableDao.ensureSeedEntry(sub.id!);
    }

    if (!mounted) return;

    // Auto-sync after saving subjects
    CloudSyncService().backupDataToCloud();

    if (widget.isEditMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subjects saved successfully')),
      );
      Navigator.pop(context);
    } else {
      context.go('/setup/basic/criteria/subjects/timetable');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final hasSubjects = _subjects.isNotEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // ✅ Dynamic Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppBreakpoints.isMobile(context) ? 24 : 40,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditMode
                  ? 'Edit Sem $_activeSemester Subjects'
                  : 'Add Your Subjects',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color, // ✅ Dynamic Title
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isEditMode
                  ? 'Tap a subject to edit its name'
                  : 'Add all subjects for this semester',
              style: TextStyle(
                fontSize: 16,
                color: theme.textTheme.bodyMedium?.color,
              ), // ✅ Dynamic Subtitle
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subjectController,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                    ), // ✅ Dynamic typing text
                    decoration: InputDecoration(
                      hintText: 'Enter subject name',
                      hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      filled: true,
                      fillColor: theme.cardColor, // ✅ Dynamic input background
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  icon: const Icon(Icons.add, size: 28),
                  onPressed: _addSubject,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(56, 56),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Expanded(
              child: ListView.builder(
                itemCount: _subjects.length,
                itemBuilder: (_, i) {
                  final subject = _subjects[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme
                          .cardColor, // ✅ Dynamic background for the list item
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor,
                      ), // ✅ Dynamic border
                    ),
                    child: ListTile(
                      title: Text(
                        subject.name,
                        // Two lines: this list is how you identify which
                        // subject you are editing, so the name has to be
                        // readable in full at any system font size.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: theme
                              .textTheme
                              .bodyLarge
                              ?.color, // ✅ Dynamic Text
                        ),
                      ),
                      onTap: () => _editSubject(i),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFEF4444),
                        ),
                        onPressed: () => _deleteSubject(i),
                      ),
                    ),
                  );
                },
              ),
            ),

            SetupNavButtons(
              onBack: () => Navigator.pop(context),
              onNext: hasSubjects ? _saveAndProceed : null,
              nextLabel: widget.isEditMode ? 'Save Changes' : 'Next',
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
