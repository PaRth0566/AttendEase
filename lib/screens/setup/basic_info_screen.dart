import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/db_helper.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/local_pdf_parser.dart';
import '../../services/pdf_attendance_import_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/app_buttons.dart';

class BasicInfoScreen extends StatefulWidget {
  final bool isEditMode;
  final Map<String, dynamic>? prefilledData;

  const BasicInfoScreen({super.key, required this.isEditMode, this.prefilledData});

  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  final _nameController = TextEditingController();
  final _courseController = TextEditingController();
  final _yearController = TextEditingController();

  String _collegeType = 'degree';
  String _selectedTerm = 'FYJC';
  int _selectedSemester = 1;

  /// Whether the academic period (semester or term) came from the uploaded report.
  /// False when the report's header did not name one, which the field then says
  /// so the student can correct it before the import runs.
  bool _periodFromReport = false;

  DateTime? _startDate;
  DateTime? _endDate;

  /// True while [_saveAndNext] is writing prefs and importing the PDF. Drives
  /// the Next button's spinner and blocks a second submit — a fast double-tap
  /// previously fired the import twice and double-wrote rows.
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadSavedData();
    } else if (widget.prefilledData != null) {
      _loadPrefilledData();
    }
  }

  void _loadPrefilledData() {
    final data = widget.prefilledData!;
    _nameController.text = data['name']?.toString() ?? data['studentName']?.toString() ?? '';
    _courseController.text = data['course']?.toString() ?? '';
    _yearController.text = data['year']?.toString() ?? '';
    if (data['startDate'] != null && data['startDate'].toString().isNotEmpty) {
      _startDate = DateTime.tryParse(data['startDate']);
    }
    if (data['endDate'] != null && data['endDate'].toString().isNotEmpty) {
      _endDate = DateTime.tryParse(data['endDate']);
    }

    final rawCollege = data['collegeType']?.toString();
    final rawTerm = data['term']?.toString();
    final rawSem = data['semester']?.toString();

    // Determine if junior college: explicit collegeType or detected junior term markers
    final detectedJuniorTerm = (rawTerm == 'SYJC' || rawTerm == 'FYJC')
        ? rawTerm
        : (rawSem == 'SYJC' || rawSem == 'FYJC')
            ? rawSem
            : LocalPdfParser.extractJuniorCollegeTerm(rawTerm ?? '') ??
                LocalPdfParser.extractJuniorCollegeTerm(rawSem ?? '') ??
                LocalPdfParser.extractJuniorCollegeTerm(data['course']?.toString() ?? '');

    final isJunior = rawCollege == 'junior' || detectedJuniorTerm != null;

    if (isJunior) {
      _collegeType = 'junior';
      final term = detectedJuniorTerm ??
          (rawTerm != null && (rawTerm == 'SYJC' || rawTerm == 'FYJC') ? rawTerm : null);
      if (term != null) {
        _selectedTerm = term;
        _periodFromReport = true;
      } else {
        _selectedTerm = 'FYJC';
        _periodFromReport = false;
      }
      _selectedSemester = _selectedTerm == 'SYJC' ? 12 : 11;
    } else {
      _collegeType = 'degree';
      final parsedSem = data['semesterNumber'];
      final semNum = parsedSem is int
          ? parsedSem
          : LocalPdfParser.semesterNumberFrom(rawSem ?? '');

      _selectedSemester = (semNum ?? _selectedSemester).clamp(1, _maxSemester);
      _periodFromReport = semNum != null;
    }
  }

  /// Highest semester the dropdown offers.
  static const int _maxSemester = 8;

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('full_name') ?? '';
      _courseController.text = prefs.getString('course') ?? '';
      _yearController.text = prefs.getString('year') ?? '';
      _collegeType = prefs.getString('college_type') ?? 'degree';
      _selectedTerm = prefs.getString('term') ?? 'FYJC';
      _selectedSemester = prefs.getInt('semester') ?? 1;
    });
    await _loadDates();
  }

  Future<void> _loadDates() async {
    final prefs = await SharedPreferences.getInstance();
    String? start;
    String? end;
    if (_collegeType == 'junior') {
      start = prefs.getString('junior_term_start_$_selectedTerm');
      end = prefs.getString('junior_term_end_$_selectedTerm');
    } else {
      start = prefs.getString('semester_start_$_selectedSemester');
      end = prefs.getString('semester_end_$_selectedSemester');
    }
    if (start != null && end != null) {
      setState(() {
        _startDate = DateTime.parse(start!);
        _endDate = DateTime.parse(end!);
      });
    }
  }

  Future<void> _pickDate(bool isStartDate) async {
    DateTime minDate = isStartDate ? DateTime(2020) : (_startDate ?? DateTime(2020));
    DateTime maxDate = isStartDate ? (_endDate ?? DateTime(2030)) : DateTime(2030);

    DateTime initial = isStartDate
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());
    if (initial.isBefore(minDate)) initial = minDate;
    if (initial.isAfter(maxDate)) initial = maxDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: maxDate,
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _saveAndNext() async {
    // Block re-entry: the import below is the slow, side-effecting part and a
    // double-tap must not run it twice.
    if (_isSaving) return;

    if (_nameController.text.trim().isEmpty ||
        _courseController.text.trim().isEmpty ||
        _yearController.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields, including both dates'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _persistAndImport();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _persistAndImport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('full_name', _nameController.text.trim());
    await prefs.setString('course', _courseController.text.trim());
    await prefs.setString('year', _yearController.text.trim());
    await prefs.setString('college_type', _collegeType);

    final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);

    int effectiveSemester;
    if (_collegeType == 'junior') {
      await prefs.setString('term', _selectedTerm);
      await prefs.setString('junior_term_start_$_selectedTerm', startStr);
      await prefs.setString('junior_term_end_$_selectedTerm', endStr);
      // Use distinct term integers (11 for FYJC, 12 for SYJC) to completely
      // isolate Junior subjects, timetable, and attendance from Degree Semesters 1/2.
      effectiveSemester = _selectedTerm == 'SYJC' ? 12 : 11;
      await prefs.setInt('semester', effectiveSemester);
    } else {
      effectiveSemester = _selectedSemester;
      await prefs.setInt('semester', _selectedSemester);
      await prefs.setString('semester_start_$_selectedSemester', startStr);
      await prefs.setString('semester_end_$_selectedSemester', endStr);
    }

    if (widget.isEditMode) {
      final db = await DBHelper.instance.database;
      await db.rawDelete(
        '''DELETE FROM attendance_records WHERE id IN (
             SELECT a.id FROM attendance_records a
             INNER JOIN timetable t ON a.timetable_entry_id = t.id
             INNER JOIN subjects s ON t.subject_id = s.id
             WHERE s.semester = ? AND length(a.date) = 10
               AND (a.date < ? OR a.date > ?)
           )''',
        [effectiveSemester, startStr, endStr],
      );
    } else if (widget.prefilledData != null &&
        widget.prefilledData!['subjects'] != null) {
      final List<dynamic> subs = widget.prefilledData!['subjects'];
      if (subs.isNotEmpty) {
        await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
          data: widget.prefilledData!,
          semester: effectiveSemester,
          updateSemesterBounds: false,
        );
      }
    }

    if (!mounted) return;

    // Auto-sync after saving basic info
    CloudSyncService().backupDataToCloud();

    if (widget.isEditMode) {
      Navigator.pop(context);
    } else {
      context.go('/setup/basic/criteria');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                            widget.isEditMode
                                ? 'Edit your details'
                                : "Let's get to know you",
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),

                          const SizedBox(height: 32),

                          _inputField(_nameController, 'Full Name', theme),
                          _inputField(_courseController, 'Course', theme),
                          _inputField(_yearController, 'Year', theme),

                          const SizedBox(height: 16),

                          _buildCollegeSectionSelector(theme),

                          const SizedBox(height: 16),

                          if (_collegeType == 'junior')
                            DropdownButtonFormField<String>(
                              initialValue: _selectedTerm,
                              decoration: _inputDecoration('Term', theme).copyWith(
                                helperText: widget.prefilledData == null
                                    ? null
                                    : _periodFromReport
                                        ? 'Detected from your report'
                                        : "Couldn't read this from your report — "
                                            'please check it',
                                helperMaxLines: 2,
                                helperStyle: _periodFromReport
                                    ? null
                                    : TextStyle(color: theme.colorScheme.error),
                              ),
                              dropdownColor:
                                  theme.dialogTheme.backgroundColor ??
                                  theme.cardColor,
                              style: theme.textTheme.bodyLarge,
                              items: const [
                                DropdownMenuItem(
                                  value: 'FYJC',
                                  child: Text('FYJC'),
                                ),
                                DropdownMenuItem(
                                  value: 'SYJC',
                                  child: Text('SYJC'),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    _selectedTerm = value;
                                    _periodFromReport = true;
                                  });
                                  await _loadDates();
                                }
                              },
                            )
                          else
                            DropdownButtonFormField<int>(
                              initialValue: _selectedSemester,
                              decoration: _inputDecoration('Semester', theme)
                                  .copyWith(
                                helperText: widget.prefilledData == null
                                    ? null
                                    : _periodFromReport
                                        ? 'Detected from your report'
                                        : "Couldn't read this from your report — "
                                            'please check it',
                                helperMaxLines: 2,
                                helperStyle: _periodFromReport
                                    ? null
                                    : TextStyle(color: theme.colorScheme.error),
                              ),
                              dropdownColor:
                                  theme.dialogTheme.backgroundColor ??
                                  theme.cardColor,
                              // Derived from the theme, not constructed. A
                              // `DropdownButton` *replaces* its text style with
                              // whatever it is handed (dropdown.dart's
                              // `_textStyle => widget.style ?? titleMedium`), so a
                              // bare `TextStyle(color: ...)` left fontFamily null
                              // and the menu items rendered blank on web — CanvasKit
                              // fetches Roboto rather than shipping it. See
                              // 
                              style: theme.textTheme.bodyLarge,
                              items: List.generate(
                                _maxSemester,
                                (i) => DropdownMenuItem(
                                  value: i + 1,
                                  child: Text('Semester ${i + 1}'),
                                ),
                              ),
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    _selectedSemester = value;
                                    // Once the student picks, the field is settled
                                    // and the warning has served its purpose.
                                    _periodFromReport = true;
                                  });
                                  await _loadDates();
                                }
                              },
                            ),

                          const SizedBox(height: 16),
                          _dateTile(
                            label: _collegeType == 'junior'
                                ? 'Term Start Date *'
                                : 'Semester Start Date *',
                            date: _startDate,
                            onTap: () => _pickDate(true),
                            theme: theme,
                          ),
                          const SizedBox(height: 12),
                          _dateTile(
                            label: _collegeType == 'junior'
                                ? 'Term End Date *'
                                : 'Semester End Date *',
                            date: _endDate,
                            onTap: () => _pickDate(false),
                            theme: theme,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              border: Border.all(
                                color: Colors.amber.shade700.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Attendance history is STRICTLY bound by these dates. Classes occurring outside this timeframe are ignored! Ensure they match your report.",
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color:
                                          Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.amber.shade200
                                              : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),

                      SetupNavButtons(
                        onBack: () {
                          if (widget.isEditMode) {
                            Navigator.pop(context);
                          } else {
                            context.go('/setup');
                          }
                        },
                        onNext: _saveAndNext,
                        nextLabel: widget.isEditMode ? 'Save Changes' : 'Next',
                        nextLoading: _isSaving,
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

  Widget _buildCollegeSectionSelector(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'College Section',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.02),
          ),
          child: Row(
            children: [
              Expanded(
                child: _collegeSectionPill(
                  label: 'Degree College',
                  isSelected: _collegeType == 'degree',
                  onTap: () async {
                    if (_collegeType != 'degree') {
                      setState(() {
                        _collegeType = 'degree';
                        _periodFromReport = false;
                      });
                      await _loadDates();
                    }
                  },
                  theme: theme,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _collegeSectionPill(
                  label: 'Junior College',
                  isSelected: _collegeType == 'junior',
                  onTap: () async {
                    if (_collegeType != 'junior') {
                      setState(() {
                        _collegeType = 'junior';
                        _periodFromReport = false;
                      });
                      await _loadDates();
                    }
                  },
                  theme: theme,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _collegeSectionPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: isSelected
                ? (isDark
                    ? primary.withValues(alpha: 0.25)
                    : primary.withValues(alpha: 0.15))
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: isSelected
                    ? primary
                    : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : primary)
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        style: theme.textTheme.bodyLarge,
        decoration: _inputDecoration(label, theme),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? label : DateFormat('dd MMM yyyy').format(date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: date == null ? Colors.grey : theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.calendar_today, size: 18, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, ThemeData theme) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _courseController.dispose();
    _yearController.dispose();
    super.dispose();
  }
}
