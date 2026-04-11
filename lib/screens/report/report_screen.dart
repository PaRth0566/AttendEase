import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
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
    );

    if (picked != null) {
      setState(() {
        if (isStart)
          _startDate = picked;
        else {
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

    _subjects.sort((a, b) {
      final statA = _stats[a.id] ?? {'attended': 0, 'total': 0};
      final statB = _stats[b.id] ?? {'attended': 0, 'total': 0};
      final double percentA = statA['total'] == 0
          ? 0.0
          : (statA['attended']! / statA['total']!) * 100;
      final double percentB = statB['total'] == 0
          ? 0.0
          : (statB['attended']! / statB['total']!) * 100;
      return percentA.compareTo(percentB);
    });

    setState(() {
      _isGenerating = false;
      _reportGenerated = true;
    });
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Export Report",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(
                Icons.download_rounded,
                color: Color(0xFF2563EB),
              ),
              title: Text(
                "Save to Downloads",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              subtitle: Text(
                "Save PDF directly to your device",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _processExport(isShare: false);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.share_rounded,
                color: Color(0xFF2563EB),
              ),
              title: Text(
                "Share PDF",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              subtitle: Text(
                "Send via WhatsApp, Email, etc.",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _processExport(isShare: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processExport({required bool isShare}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = pw.Document();

      // ✅ The exact blue used in your app
      final primaryAppBlue = PdfColor.fromHex('#2563EB');

      String fileName = "";
      String reportSubtitle = "";
      if (_reportType == 0) {
        fileName = "Semester_${_selectedSemester}_Attendance_Report.pdf";
        reportSubtitle = "Semester $_selectedSemester Overview";
      } else {
        final start = DateFormat('dd-MM-yyyy').format(_startDate!);
        final end = DateFormat('dd-MM-yyyy').format(_endDate!);
        fileName = "Attendance_Report_${start}_to_${end}.pdf";
        reportSubtitle = "$start to $end";
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // ✅ Title is now the Primary Blue
                        pw.Text(
                          "Attendance Report",
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryAppBlue,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          reportSubtitle,
                          style: const pw.TextStyle(
                            fontSize: 14,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Text(
                      "Generated on: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}",
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 24),

                pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Overall Attendance',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        '${_overallPercent.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                          color: _overallPercent >= 75
                              ? PdfColors.green800
                              : PdfColors.red800,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '$_totalAttended / $_totalLectures Lectures',
                        style: const pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 32),

                pw.Text(
                  "Subject Breakdown",
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.TableHelper.fromTextArray(
                  context: context,
                  // ✅ Table header background is now Primary Blue
                  headerDecoration: pw.BoxDecoration(color: primaryAppBlue),
                  // ✅ Table header text is now White for perfect contrast
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.white,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  rowDecoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                    ),
                  ),
                  headers: [
                    'Subject Name',
                    'Attended',
                    'Total',
                    'Percentage',
                    'Status',
                  ],
                  data: _subjects.map((sub) {
                    final stat = _stats[sub.id] ?? {'attended': 0, 'total': 0};
                    final attended = stat['attended']!;
                    final total = stat['total']!;
                    final percent = total == 0 ? 0.0 : (attended / total) * 100;
                    final status = percent >= sub.requiredPercent
                        ? 'Meeting Criteria'
                        : 'Below Criteria';

                    return [
                      sub.name,
                      attended.toString(),
                      total.toString(),
                      '${percent.toStringAsFixed(1)}%',
                      status,
                    ];
                  }).toList(),
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();

      if (!isShare) {
        Directory? directory;

        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory != null) {
          final file = File("${directory.path}/$fileName");
          await file.writeAsBytes(pdfBytes);

          if (!mounted) return;
          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to Downloads: $fileName'),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else {
          throw Exception("Could not find a directory to save the file.");
        }
      } else {
        final output = await getTemporaryDirectory();
        final file = File("${output.path}/$fileName");
        await file.writeAsBytes(pdfBytes);

        if (!mounted) return;
        Navigator.pop(context);

        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'My Attendance Report');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Analytics & Reports',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_reportGenerated && _totalLectures > 0)
            IconButton(
              icon: const Icon(
                Icons.file_download_outlined,
                color: Color(0xFF2563EB),
              ),
              onPressed: _showExportOptions,
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<int>(
                        title: Text(
                          'Semester',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        value: 0,
                        groupValue: _reportType,
                        contentPadding: EdgeInsets.zero,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (val) => setState(() {
                          _reportType = val!;
                          _reportGenerated = false;
                        }),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<int>(
                        title: Text(
                          'Custom Dates',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        value: 1,
                        groupValue: _reportType,
                        contentPadding: EdgeInsets.zero,
                        activeColor: theme.colorScheme.primary,
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
                      Text(
                        'Select Semester: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _selectedSemester,
                        dropdownColor: theme.cardColor,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.bold,
                        ),
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
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary),
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
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary),
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
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
          Expanded(
            child: !_reportGenerated
                ? Center(
                    child: Text(
                      'Adjust settings and click Generate',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  )
                : _totalLectures == 0
                ? Center(
                    child: Text(
                      'No attendance data found for this period.',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.primary.withAlpha(25)
                              : const Color(0xFFF2F4FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.primary.withAlpha(76),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Overall Attendance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _showExportOptions,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Export & Share PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(color: theme.colorScheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Subject Breakdown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                          color: theme.cardColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: theme.dividerColor),
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: theme.textTheme.bodyLarge?.color,
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
                                  backgroundColor: theme.dividerColor,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$attended / $total lectures',
                                  style: TextStyle(
                                    color: theme.textTheme.bodyMedium?.color,
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
