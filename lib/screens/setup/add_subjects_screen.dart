import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../setup/timetable_setup_screen.dart';

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
  List<int> _deletedSubjectIds = [];

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

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor, // ✅ Dynamic popup color
        title: Text(
          'Edit Subject',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
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
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
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

    if (widget.isEditMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subjects saved successfully')),
      );
      Navigator.pop(context);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TimetableSetupScreen()),
      );
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
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
                    onPressed: hasSubjects ? _saveAndProceed : null,
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
          ],
        ),
      ),
        ),
      ),
    );
  }
}
