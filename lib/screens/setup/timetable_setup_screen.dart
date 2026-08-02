import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/subject_dao.dart';
import '../../database/timetable_dao.dart';
import '../../models/subject.dart';
import '../../models/timetable_entry.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_buttons.dart';

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
    // Clean approach: delete all entries for this day+semester, then re-insert.
    // This eliminates subtle ordering bugs from the old index-based comparison.
    await _timetableDao.deleteEntriesForDay(_selectedDay, _activeSemester);

    for (int i = 0; i < _daySubjects.length; i++) {
      await _timetableDao.insertEntry(
        TimetableEntry(
          dayOfWeek: _selectedDay,
          subjectId: _daySubjects[i].id!,
          lectureOrder: i + 1,
        ),
      );
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
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
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
                  'Add lectures for each day to generate your schedule.\nNote: Each lecture is assumed to be 1 hour long.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.7,
                    ),
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
                                : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : theme.dividerColor.withValues(alpha: 0.5),
                              ),
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : theme.textTheme.bodyLarge?.color,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
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
                        : theme.colorScheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? theme.dividerColor
                          : theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Subject>(
                          initialValue: _selectedSubject,
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.w600,
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Select subject',
                            hintStyle: TextStyle(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.6),
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
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                          items: _allSubjects
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedSubject = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
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
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.calendar_today_rounded,
                                  size: 48,
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Free Day? 🏖️',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'We couldn\'t find any consistent classes for this day in your PDF report (or you just don\'t have any!).\n\nIf you do have classes today, please add them manually above.',
                                textAlign: TextAlign.center,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _daySubjects.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            return Container(
                              decoration: BoxDecoration(
                                color: isDark ? theme.cardColor : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                boxShadow: isDark
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${i + 1}',
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
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
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade400,
                                    size: 24,
                                  ),
                                  onPressed: () =>
                                      setState(() => _daySubjects.removeAt(i)),
                                  tooltip: 'Remove Lecture',
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),

                // Bottom Actions
                SetupNavButtons(
                  onBack: () => Navigator.pop(context),
                  onNext: _finishSetup,
                  nextLabel: widget.isEditMode
                      ? 'Save Timetable'
                      : 'Finish Setup',
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
