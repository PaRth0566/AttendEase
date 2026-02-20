import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup_complete', true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable setup complete!')),
      );

      // This safely clears the setup stack and sends the user home!
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RootScreen()),
        (route) => false,
      );
    }
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditMode
                  ? 'Edit Sem $_activeSemester Timetable'
                  : 'Set Your Weekly Timetable',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
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
                      selectedColor: const Color(0xFF2563EB),
                      backgroundColor: const Color(0xFFF1F5F9),
                      labelStyle: TextStyle(
                        color: _selectedDay == e.key
                            ? Colors.white
                            : const Color(0xFF64748B),
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
                    decoration: InputDecoration(
                      hintText: 'Select subject',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      // ✅ BLUE FOCUSED BORDER FIX
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
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
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(56, 56),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Expanded(
              child: _daySubjects.isEmpty
                  ? const Center(
                      child: Text(
                        'No lectures added for this day',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _daySubjects.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(
                            0xFF2563EB,
                          ).withOpacity(0.15),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _daySubjects[i].name,
                          style: const TextStyle(
                            color: Colors.black,
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
                    onPressed: _finishSetup,
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
                      widget.isEditMode ? 'Save Changes' : 'Finish Setup',
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
