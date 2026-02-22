import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
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
        title: const Text('Edit Subject'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter subject name',
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
    // 1. Process all queued deletions
    for (final id in _deletedSubjectIds) {
      await _subjectDao.deleteSubject(id);
    }

    // 2. Process all additions and updates
    for (final subject in _subjects) {
      if (subject.id == null) {
        await _subjectDao.insertSubject(subject);
      } else {
        await _subjectDao.updateSubject(subject);
      }
    }

    // ✅ THE FIX: Reload subjects from the database to update their IDs in memory!
    // This stops them from duplicating if the user hits Back and Next again.
    await _loadSubjects();

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
            Text(
              widget.isEditMode
                  ? 'Edit Sem $_activeSemester Subjects'
                  : 'Add Your Subjects',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isEditMode
                  ? 'Tap a subject to edit its name'
                  : 'Add all subjects for this semester',
              style: const TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      hintText: 'Enter subject name',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
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
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
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
                    backgroundColor: const Color(0xFF2563EB),
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
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      title: Text(
                        subject.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                    onPressed: hasSubjects ? _saveAndProceed : null,
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
          ],
        ),
      ),
    );
  }
}
