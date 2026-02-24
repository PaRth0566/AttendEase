import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final AttendanceDao _attendanceDao = AttendanceDao();
  final SubjectDao _subjectDao = SubjectDao();

  int _reportType = 0; // 0 = Semester, 1 = Custom Date Range
  int _selectedSemester = 1;

  DateTime? _startDate;
  DateTime? _endDate;

  bool _isGenerating = false;
  bool _reportGenerated = false;

  List<Subject> _subjects = [];
  Map<int, Map<String, int>> _stats = {};
  double _overallPercent = 0.0;
  int _totalLectures = 0;
  int _totalAttended = 0;

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  Future<void> _initDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSemester = prefs.getInt('semester') ?? 1;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          if (_startDate != null && picked.isBefore(_startDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('End date cannot be before Start date'),
              ),
            );
          } else {
            _endDate = picked;
          }
        }
        _reportGenerated = false;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_reportType == 1 && (_startDate == null || _endDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both Start and End dates')),
      );
      return;
    }

    if (_reportType == 1 && _endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before Start date')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    String startQuery = '';
    String endQuery = '';

    if (_reportType == 0) {
      final prefs = await SharedPreferences.getInstance();
      startQuery =
          prefs.getString('semester_start_$_selectedSemester') ?? '1970-01-01';
      endQuery =
          prefs.getString('semester_end_$_selectedSemester') ?? '2099-12-31';
    } else {
      startQuery = DateFormat('yyyy-MM-dd').format(_startDate!);
      endQuery = DateFormat('yyyy-MM-dd').format(_endDate!);
    }

    _subjects = await _subjectDao.getSubjectsBySemester(_selectedSemester);
    _stats = await _attendanceDao.getAttendanceStatsForDateRange(
      startQuery,
      endQuery,
      _selectedSemester,
    );

    _totalAttended = 0;
    _totalLectures = 0;

    for (final sub in _subjects) {
      final s = _stats[sub.id] ?? {'attended': 0, 'total': 0};
      _totalAttended += s['attended']!;
      _totalLectures += s['total']!;
    }

    _overallPercent = _totalLectures == 0
        ? 0.0
        : (_totalAttended / _totalLectures) * 100;

    // ✅ NEW LOGIC: Sort subjects by attendance percentage for reports
    _subjects.sort((a, b) {
      final statA = _stats[a.id] ?? {'attended': 0, 'total': 0};
      final statB = _stats[b.id] ?? {'attended': 0, 'total': 0};

      final double percentA = statA['total'] == 0
          ? 0.0
          : (statA['attended']! / statA['total']!) * 100;
      final double percentB = statB['total'] == 0
          ? 0.0
          : (statB['attended']! / statB['total']!) * 100;

      int comparison = percentA.compareTo(percentB);
      if (comparison == 0) {
        return a.name.compareTo(b.name);
      }
      return comparison;
    });

    setState(() {
      _isGenerating = false;
      _reportGenerated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Analytics & Reports',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // REPORT CONTROLS (TOP)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<int>(
                        title: const Text(
                          'Semester',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: 0,
                        groupValue: _reportType,
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF2563EB),
                        onChanged: (val) => setState(() {
                          _reportType = val!;
                          _reportGenerated = false;
                        }),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<int>(
                        title: const Text(
                          'Custom Dates',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: 1,
                        groupValue: _reportType,
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF2563EB),
                        onChanged: (val) => setState(() {
                          _reportType = val!;
                          _reportGenerated = false;
                        }),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                if (_reportType == 0)
                  Row(
                    children: [
                      const Text(
                        'Select Semester: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _selectedSemester,
                        items: List.generate(
                          8,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('Semester ${i + 1}'),
                          ),
                        ),
                        onChanged: (val) => setState(() {
                          _selectedSemester = val!;
                          _reportGenerated = false;
                        }),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(true),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(color: Color(0xFF2563EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          label: Text(
                            _startDate == null
                                ? 'Start Date'
                                : DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(_startDate!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(false),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(color: Color(0xFF2563EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          label: Text(
                            _endDate == null
                                ? 'End Date'
                                : DateFormat('MMM dd, yyyy').format(_endDate!),
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isGenerating ? null : _generateReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isGenerating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Generate Report',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // REPORT RESULTS (BOTTOM)
          Expanded(
            child: !_reportGenerated
                ? const Center(
                    child: Text(
                      'Adjust settings and click Generate',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : _totalLectures == 0
                ? const Center(
                    child: Text(
                      'No attendance data found for this period.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // OVERALL CARD
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F4FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF2563EB).withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Overall Attendance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_overallPercent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: _overallPercent >= 75
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_totalAttended / $_totalLectures Lectures Attended',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Text(
                        'Subject Breakdown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // SUBJECTS LIST
                      ..._subjects.map((sub) {
                        final stat =
                            _stats[sub.id] ?? {'attended': 0, 'total': 0};
                        final attended = stat['attended']!;
                        final total = stat['total']!;
                        final percent = total == 0
                            ? 0.0
                            : (attended / total) * 100;
                        final color = percent >= sub.requiredPercent
                            ? Colors.green
                            : Colors.red;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      sub.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '${percent.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: total == 0 ? 0 : percent / 100,
                                  color: color,
                                  backgroundColor: Colors.grey.shade200,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$attended / $total lectures',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
