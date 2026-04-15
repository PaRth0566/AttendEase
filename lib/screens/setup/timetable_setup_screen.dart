import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';
import '../../services/cloud_sync_service.dart';
import '../root/root_screen.dart';

class TimetableSetupScreen extends StatefulWidget {
  final bool isEditMode;

  const TimetableSetupScreen({super.key, this.isEditMode = false});

  @override
  State<TimetableSetupScreen> createState() => _TimetableSetupScreenState();
}

class _TimetableSetupScreenState extends State<TimetableSetupScreen> {
  final SubjectDao _subjectDao = SubjectDao();
  final TimetableDao _timetableDao = TimetableDao();

  final Map<int, String> _days = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
  };

  int _selectedDay = 1;
  int _activeSemester = 1;
  List<Subject> _allSubjects = [];
  List<Subject> _daySubjects = [];
  Subject? _selectedSubject;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _activeSemester = prefs.getInt('semester') ?? 1;

    final data = await _subjectDao.getSubjectsBySemester(_activeSemester);
    if (!mounted) return;
    setState(() => _allSubjects = data);
    await _loadDay();
  }

  Future<void> _loadDay() async {
    final entries = await _timetableDao.getEntriesForDay(
      _selectedDay,
      _activeSemester,
    );
    if (!mounted) return;

    setState(() {
      _daySubjects = entries
          .map(
            (e) => _allSubjects.firstWhere(
              (s) => s.id == e.subjectId,
              orElse: () => Subject(
                name: 'Unknown',
                requiredPercent: 0,
                semester: _activeSemester,
              ),
            ),
          )
          .where((s) => s.name != 'Unknown')
          .toList();
    });
  }

  Future<void> _saveDay() async {
    final existingEntries = await _timetableDao.getEntriesForDay(
      _selectedDay,
      _activeSemester,
    );

    bool isChanged = false;
    if (existingEntries.length != _daySubjects.length) {
      isChanged = true;
    } else {
      for (int i = 0; i < existingEntries.length; i++) {
        if (existingEntries[i].subjectId != _daySubjects[i].id) {
          isChanged = true;
          break;
        }
      }
    }

    if (!isChanged) return;

    final db = await DBHelper.instance.database;

    for (int i = 0; i < _daySubjects.length; i++) {
      final subjectId = _daySubjects[i].id!;
      final order = i + 1;

      if (i < existingEntries.length) {
        final existing = existingEntries[i];
        if (existing.subjectId != subjectId) {
          await db.delete(
            'timetable',
            where: 'id = ?',
            whereArgs: [existing.id],
          );
          await _timetableDao.insertEntry(
            TimetableEntry(
              dayOfWeek: _selectedDay,
              subjectId: subjectId,
              lectureOrder: order,
            ),
          );
        }
      } else {
        await _timetableDao.insertEntry(
          TimetableEntry(
            dayOfWeek: _selectedDay,
            subjectId: subjectId,
            lectureOrder: order,
          ),
        );
      }
    }

    if (existingEntries.length > _daySubjects.length) {
      for (int i = _daySubjects.length; i < existingEntries.length; i++) {
        await db.delete(
          'timetable',
          where: 'id = ?',
          whereArgs: [existingEntries[i].id],
        );
      }
    }
  }

  Future<void> _finishSetup() async {
    await _saveDay();
    if (!mounted) return;

    if (widget.isEditMode) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Timetable updated!')));
      Navigator.pop(context);
    } else {
      await _completeSetupAndNavigate();
    }
  }

  Future<void> _skipSetup() async {
    if (widget.isEditMode) {
      Navigator.pop(context);
      return;
    }
    await _completeSetupAndNavigate();
  }

  Future<void> _completeSetupAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_setup_complete', true);

    await CloudSyncService().backupDataToCloud();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RootScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Extract Theme
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // ✅ Dynamic background
      appBar: AppBar(
        backgroundColor: Colors.transparent, // ✅ Adheres to theme naturally
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditMode
                  ? 'Edit Sem $_activeSemester Timetable'
                  : 'Set Your Weekly Timetable',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color, // ✅ Dynamic text
              ),
            ),
            const SizedBox(height: 24),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _days.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _selectedDay == e.key,
                      selectedColor:
                          theme.colorScheme.primary, // ✅ Dynamic primary
                      backgroundColor:
                          theme.cardColor, // ✅ Dynamic unselected bg
                      labelStyle: TextStyle(
                        color: _selectedDay == e.key
                            ? Colors.white
                            : theme
                                  .textTheme
                                  .bodyLarge
                                  ?.color, // ✅ Dynamic unselected text
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) async {
                        await _saveDay();
                        setState(() => _selectedDay = e.key);
                        _loadDay();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Subject>(
                    value: _selectedSubject,
                    dropdownColor: theme
                        .cardColor, // ✅ Crucial: prevents white dropdown in dark mode
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                    ), // ✅ Dropdown text color
                    decoration: InputDecoration(
                      hintText: 'Select subject',
                      hintStyle: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor,
                        ), // ✅ Dynamic border
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    items: _allSubjects
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSubject = v),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: () {
                    if (_selectedSubject != null) {
                      setState(() {
                        _daySubjects.add(_selectedSubject!);
                        _selectedSubject = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.add),
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
              child: _daySubjects.isEmpty
                  ? Center(
                      child: Text(
                        'No lectures added for this day',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _daySubjects.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: theme.colorScheme.primary.withAlpha(
                            38,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _daySubjects[i].name,
                          style: TextStyle(
                            color: theme
                                .textTheme
                                .bodyLarge
                                ?.color, // ✅ Dynamic text
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () =>
                              setState(() => _daySubjects.removeAt(i)),
                        ),
                      ),
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
                if (!widget.isEditMode) ...
                [
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _skipSetup,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                          color: theme.colorScheme.secondary,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _finishSetup,
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
                      widget.isEditMode ? 'Save Changes' : 'Finish',
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
