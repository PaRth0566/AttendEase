import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
      // Auto-sync after editing timetable
      CloudSyncService().backupDataToCloud();

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
    context.go('/app/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
              vertical: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEditMode
                      ? 'Edit Sem $_activeSemester Timetable'
                      : 'Set Your Weekly Timetable',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add lectures for each day to generate your schedule.',
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),

                // Days Selection
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _days.entries.map((e) {
                      final isSelected = _selectedDay == e.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: isSelected,
                            selectedColor: theme.colorScheme.primary,
                            backgroundColor: isDark
                                ? theme.cardColor
                                : theme.colorScheme.surfaceVariant.withOpacity(0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : theme.dividerColor.withOpacity(0.5),
                              ),
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : theme.textTheme.bodyLarge?.color,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 15,
                            ),
                            onSelected: (_) async {
                              await _saveDay();
                              setState(() => _selectedDay = e.key);
                              _loadDay();
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Subject Picker Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.cardColor
                        : theme.colorScheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? theme.dividerColor
                          : theme.colorScheme.primary.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Subject>(
                          value: _selectedSubject,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.w600,
                          ),
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.primary),
                          decoration: InputDecoration(
                            hintText: 'Select subject',
                            hintStyle: TextStyle(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                              fontWeight: FontWeight.normal,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? theme.scaffoldBackgroundColor
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: theme.colorScheme.primary.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                          ),
                          items: _allSubjects
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedSubject = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton.filled(
                          onPressed: () {
                            if (_selectedSubject != null) {
                              setState(() {
                                _daySubjects.add(_selectedSubject!);
                                _selectedSubject = null;
                              });
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(54, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Timetable List
                Expanded(
                  child: _daySubjects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.calendar_today_rounded,
                                  size: 48,
                                  color: theme.colorScheme.primary.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Free Day!',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No lectures added for this day yet.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _daySubjects.length,
                          itemBuilder: (_, i) {
                            final isLast = i == _daySubjects.length - 1;
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Timeline Line & Dot
                                  SizedBox(
                                    width: 40,
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: theme.colorScheme.primary.withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (!isLast)
                                          Expanded(
                                            child: Container(
                                              width: 2,
                                              color: theme.colorScheme.primary.withOpacity(0.2),
                                              margin: const EdgeInsets.symmetric(vertical: 4),
                                            ),
                                          )
                                        else
                                          const SizedBox(height: 16), // Padding for the last item
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Subject Card
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isDark ? theme.cardColor : Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: theme.dividerColor.withOpacity(0.5),
                                          ),
                                          boxShadow: isDark
                                              ? []
                                              : [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.03),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  )
                                                ],
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 8,
                                          ),
                                          title: Text(
                                            _daySubjects[i].name,
                                            style: TextStyle(
                                              color: theme.textTheme.bodyLarge?.color,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              height: 1.3,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: IconButton(
                                            icon: Icon(Icons.delete_outline_rounded,
                                                color: Colors.red.shade400, size: 24),
                                            onPressed: () =>
                                                setState(() => _daySubjects.removeAt(i)),
                                            tooltip: 'Remove Lecture',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),

                // Bottom Actions
                SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: theme.dividerColor,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                      ),
                      if (!widget.isEditMode) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            onPressed: _skipSetup,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                color: theme.colorScheme.secondary.withOpacity(0.5),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
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
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _finishSetup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 4,
                            shadowColor: theme.colorScheme.primary.withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            widget.isEditMode ? 'Save Timetable' : 'Finish Setup',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
