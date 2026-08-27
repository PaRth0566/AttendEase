import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/attendance_dao.dart';
import '../../database/subject_dao.dart';
import '../../models/subject.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/container_transform.dart';
import '../../widgets/app_overlays.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/pressable.dart';
import 'subject_detail_screen.dart';

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

  /// Calendar span actually covered by attendance records for
  /// [_selectedSemester] — the first date carrying any record (P / A / NU / NC)
  /// and the last one, future-dated records included. Custom-range picking is
  /// confined to this span: a range outside it can only ever produce an empty
  /// report. Null when the semester holds no records at all.
  DateTime? _recordFirstDate;
  DateTime? _recordLastDate;
  bool _boundsLoaded = false;

  bool _isGenerating = false;
  bool _reportGenerated = false;

  List<Subject> _subjects = [];
  Map<int, Map<String, int>> _stats = {};
  double _overallPercent = 0.0;
  int _totalLectures = 0;
  int _totalAttended = 0;

  /// The period the *displayed* report was generated over, captured at
  /// generation time.
  ///
  /// Read only when a breakdown card is opened, so the detail page is scoped to
  /// the report on screen rather than to whatever the pickers happen to hold
  /// now. Null range = Semester mode, which counts every record the semester
  /// holds — see [SubjectReportArgs].
  DateTimeRange? _generatedRange;
  String _generatedLabel = '';

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  Future<void> _initDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedSemester = prefs.getInt('semester') ?? 1;
    });
    await _loadRecordBounds();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Re-reads the record span for [_selectedSemester] and drops any already
  /// picked date that the new span no longer covers — switching semesters must
  /// not leave a range behind that its own picker would now refuse.
  Future<void> _loadRecordBounds() async {
    final bounds = await _attendanceDao.getAttendanceDateBoundsForSemester(
      _selectedSemester,
    );
    if (!mounted) return;

    final DateTime? first = bounds.firstDate == null
        ? null
        : _dateOnly(bounds.firstDate!);
    final DateTime? last = bounds.lastDate == null
        ? null
        : _dateOnly(bounds.lastDate!);

    bool outOfSpan(DateTime? d) {
      if (d == null) return false;
      if (first == null || last == null) return true;
      return d.isBefore(first) || d.isAfter(last);
    }

    setState(() {
      _recordFirstDate = first;
      _recordLastDate = last;
      _boundsLoaded = true;
      if (outOfSpan(_startDate)) {
        _startDate = null;
        _reportGenerated = false;
      }
      if (outOfSpan(_endDate)) {
        _endDate = null;
        _reportGenerated = false;
      }
    });
  }

  Future<void> _pickDate(bool isStart) async {
    if (!_boundsLoaded) await _loadRecordBounds();
    if (!mounted) return;

    final DateTime? first = _recordFirstDate;
    final DateTime? last = _recordLastDate;
    if (first == null || last == null) {
      _showMessage(
        'No attendance records for Semester $_selectedSemester yet — '
        'there is no date range to pick from.',
      );
      return;
    }

    // The picker asserts on an initialDate outside [firstDate, lastDate], and
    // "today" routinely falls outside a past semester's span.
    DateTime clamp(DateTime d) =>
        d.isBefore(first) ? first : (d.isAfter(last) ? last : d);

    final DateTime initial = clamp(
      _dateOnly(isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? last)),
    );

    // The full span stays selectable in both pickers, and an inverted range is
    // rejected on selection instead — so picking End first and then a later
    // Start reports the same error as the other order, rather than silently
    // greying the day out.
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;

    final DateTime value = _dateOnly(picked);

    if (isStart) {
      if (_endDate != null && value.isAfter(_endDate!)) {
        _showMessage('Start date cannot be after End date');
        return;
      }
      setState(() {
        _startDate = value;
        _reportGenerated = false;
      });
    } else {
      if (_startDate != null && value.isBefore(_startDate!)) {
        _showMessage('End date cannot be before Start date');
        return;
      }
      setState(() {
        _endDate = value;
        _reportGenerated = false;
      });
    }
  }

  Future<void> _generateReport({bool silent = false}) async {
    if (_reportType == 1) {
      if (_startDate == null || _endDate == null) {
        _showMessage('Please select both Start and End dates');
        return;
      }
      // Backstop for any range that turned invalid after it was picked (a
      // semester switch, a restored state). Generating on an inverted range
      // would quietly return an empty report instead of naming the problem.
      if (_endDate!.isBefore(_startDate!)) {
        _showMessage('End date cannot be before Start date');
        return;
      }
    }
    // `silent` is the re-read after returning from a breakdown card, where the
    // user may have edited a record. Flipping the button into its spinner for
    // that would read as a second, unasked-for generation.
    if (!silent) setState(() => _isGenerating = true);

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
    if (_reportType == 0) {
      // Semester mode counts every record for the semester — identical to the
      // Dashboard — so the two screens never disagree.
      _stats = await _attendanceDao.getAttendanceStats(_selectedSemester);
    } else {
      _stats = await _attendanceDao.getAttendanceStatsForDateRange(
        startQuery,
        endQuery,
        _selectedSemester,
      );
    }

    // Pinned to whichever branch above actually ran, so a breakdown card opens
    // on the same period its own numbers were counted over. Semester mode
    // deliberately carries no range: it counts the semester's whole record set,
    // not the profile's semester_start/end window.
    _generatedRange = _reportType == 0
        ? null
        : DateTimeRange(start: _startDate!, end: _endDate!);
    _generatedLabel = _reportType == 0
        ? 'Semester $_selectedSemester'
        : '${DateFormat('MMM d, yyyy').format(_startDate!)} – '
              '${DateFormat('MMM d, yyyy').format(_endDate!)}';

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

    if (!mounted) return;
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

  /// Opens the tapped subject's breakdown, scoped to the report on screen.
  ///
  /// Uses `push` rather than `go` for the return value: the history rows on that
  /// page are editable, so a record may have changed by the time it pops, and
  /// this report's own figures would otherwise sit stale behind it. The card is
  /// wrapped in a [ContainerTransformAnchor], so the page grows out of it and
  /// shrinks back into it exactly as on the Dashboard.
  Future<void> _openSubject(Subject subject) async {
    final SubjectReportArgs args = (
      subject: subject,
      range: _generatedRange,
      label: _generatedLabel,
    );
    await context.push('/app/profile/report/subject-detail', extra: args);
    // Only worth re-reading while results are actually on screen; a mode switch
    // while the page was open has already cleared them.
    if (!mounted || !_reportGenerated) return;
    await _generateReport(silent: true);
  }

  void _showExportOptions() {
    showAppModalSheet(
      context: context,
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
              leading: Icon(
                Icons.download_rounded,
                color: Theme.of(context).colorScheme.primary,
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
              leading: Icon(
                Icons.share_rounded,
                color: Theme.of(context).colorScheme.primary,
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

  Future<void> _showSemesterPicker() async {
    final theme = Theme.of(context);
    final int? picked = await showAppModalSheet<int>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Select Semester',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDimens.space12),
              ...List.generate(8, (i) {
                final int sem = i + 1;
                final bool isCurrent = sem == _selectedSemester;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.school_rounded,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.textTheme.bodyMedium?.color,
                  ),
                  title: Text(
                    'Semester $sem',
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? theme.colorScheme.primary : null,
                    ),
                  ),
                  trailing: isCurrent
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(ctx).pop(sem),
                );
              }),
            ],
          ),
        );
      },
    );

    if (picked != null && picked != _selectedSemester) {
      setState(() {
        _selectedSemester = picked;
        _reportGenerated = false;
      });
      // The selectable span belongs to the semester, so it has to follow the
      // switch — otherwise Custom Dates keeps offering the old semester's days.
      await _loadRecordBounds();
    }
  }

  Future<void> _processExport({required bool isShare}) async {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = pw.Document();

      // Premium Colors
      final primaryAppBlue = PdfColor.fromHex('#2563EB');
      final bgCard = PdfColor.fromHex('#F8FAFC');
      final textDark = PdfColor.fromHex('#1E293B');
      final textLight = PdfColor.fromHex('#64748B');
      final successColor = PdfColor.fromHex('#16A34A');
      final dangerColor = PdfColor.fromHex('#DC2626');

      String fileName = "";
      String reportSubtitle = "";
      if (_reportType == 0) {
        fileName = "Semester_${_selectedSemester}_Attendance_Report.pdf";
        reportSubtitle = "Semester $_selectedSemester Overview";
      } else {
        final start = DateFormat('dd MMM yyyy').format(_startDate!);
        final end = DateFormat('dd MMM yyyy').format(_endDate!);
        fileName =
            "Attendance_Report_${DateFormat('dd-MM-yyyy').format(_startDate!)}_to_${DateFormat('dd-MM-yyyy').format(_endDate!)}.pdf";
        reportSubtitle = "$start  to  $end";
      }

      int subjectsMeetingCriteria = 0;
      int subjectsNeedingAttention = 0;

      for (final sub in _subjects) {
        final stat = _stats[sub.id] ?? {'attended': 0, 'total': 0};
        final percent = stat['total'] == 0
            ? 0.0
            : (stat['attended']! / stat['total']!) * 100;
        if (percent >= sub.requiredPercent) {
          subjectsMeetingCriteria++;
        } else {
          subjectsNeedingAttention++;
        }
      }

      pw.Widget buildSummaryCard({
        required String title,
        required String value,
        required String subtitle,
        required PdfColor valueColor,
        required PdfColor bgColor,
        required PdfColor textColor,
        required PdfColor subTextColor,
      }) {
        return pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: bgColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: PdfColors.grey200, width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textColor,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                subtitle,
                style: pw.TextStyle(fontSize: 9, color: subTextColor),
              ),
            ],
          ),
        );
      }

      pw.Widget buildHeaderCell(String text) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }

      pw.Widget buildDataCell(
        String text, {
        PdfColor? color,
        bool isBold = false,
      }) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: color ?? PdfColors.grey800,
              fontSize: 10,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 24),
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: primaryAppBlue,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "AttendEase",
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Official Attendance Report",
                        style: pw.TextStyle(
                          color: PdfColors.blue100,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        reportSubtitle,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Generated: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}",
                        style: pw.TextStyle(
                          color: PdfColors.blue100,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          footer: (context) {
            return pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 16),
              child: pw.Text(
                "Generated securely by AttendEase App | Page ${context.pageNumber} of ${context.pagesCount}",
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey500,
                ),
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.Text(
                "Performance Summary",
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Row(
                children: [
                  pw.Expanded(
                    child: buildSummaryCard(
                      title: "Overall Attendance",
                      value: "${_overallPercent.toStringAsFixed(2)}%",
                      subtitle: "$_totalAttended / $_totalLectures Lectures",
                      valueColor: _overallPercent >= 75
                          ? successColor
                          : dangerColor,
                      bgColor: bgCard,
                      textColor: textDark,
                      subTextColor: textLight,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: buildSummaryCard(
                      title: "Meeting Criteria",
                      value: "$subjectsMeetingCriteria",
                      subtitle: "Out of ${_subjects.length} Subjects",
                      valueColor: successColor,
                      bgColor: bgCard,
                      textColor: textDark,
                      subTextColor: textLight,
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: buildSummaryCard(
                      title: "Needs Attention",
                      value: "$subjectsNeedingAttention",
                      subtitle: "Below Required %",
                      valueColor: subjectsNeedingAttention > 0
                          ? dangerColor
                          : successColor,
                      bgColor: bgCard,
                      textColor: textDark,
                      subTextColor: textLight,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 32),

              pw.Text(
                "Detailed Subject Breakdown",
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.5),
                },
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: primaryAppBlue),
                    children: [
                      buildHeaderCell("Subject Name"),
                      buildHeaderCell("Attended"),
                      buildHeaderCell("Total"),
                      buildHeaderCell("Percentage"),
                      buildHeaderCell("Status"),
                    ],
                  ),
                  ...List.generate(_subjects.length, (index) {
                    final sub = _subjects[index];
                    final stat = _stats[sub.id] ?? {'attended': 0, 'total': 0};
                    final attended = stat['attended']!;
                    final total = stat['total']!;
                    final percent = total == 0 ? 0.0 : (attended / total) * 100;
                    final isMeeting = percent >= sub.requiredPercent;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: index % 2 == 1
                            ? PdfColors.grey50
                            : PdfColors.white,
                      ),
                      children: [
                        buildDataCell(sub.name, isBold: true),
                        buildDataCell(attended.toString()),
                        buildDataCell(total.toString()),
                        buildDataCell(
                          '${percent.toStringAsFixed(2)}%',
                          color: isMeeting ? successColor : dangerColor,
                          isBold: true,
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            decoration: pw.BoxDecoration(
                              color: isMeeting
                                  ? PdfColor.fromHex('#DCFCE7')
                                  : PdfColor.fromHex('#FEE2E2'),
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(4),
                              ),
                            ),
                            child: pw.Text(
                              isMeeting ? 'On Track' : 'Warning',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: isMeeting ? successColor : dangerColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ];
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

        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: 'My Attendance Report'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not export the report. Please check storage permissions and try again.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;

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
              icon: Icon(
                Icons.file_download_outlined,
                color: theme.colorScheme.primary,
              ),
              onPressed: _showExportOptions,
            ),
        ],
      ),
      // Pushed screen: AppBar covers the status bar, but the scrolling body
      // still needs bottom inset protection on gesture-nav devices.
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimens.maxContentWide,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppBreakpoints.isMobile(context)
                    ? AppDimens.space16
                    : AppDimens.space32,
                AppDimens.space12,
                AppBreakpoints.isMobile(context)
                    ? AppDimens.space16
                    : AppDimens.space32,
                AppDimens.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Compact Header Hero Card
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                (theme.textTheme.bodyMedium?.color ??
                                        theme.colorScheme.onSurface)
                                    .withAlpha(18),
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Icon(
                            Icons.insights_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Attendance Report',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pick a range, generate your report, and export it as a polished PDF.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(AppDimens.space16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioGroup<int>(
                          groupValue: _reportType,
                          onChanged: (val) => setState(() {
                            if (val != null) {
                              _reportType = val;
                              _reportGenerated = false;
                            }
                          }),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _reportType = 0;
                                    _reportGenerated = false;
                                  }),
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusSm,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Radio<int>(
                                          value: 0,
                                          activeColor:
                                              theme.colorScheme.primary,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Semester',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: theme
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _reportType = 1;
                                    _reportGenerated = false;
                                  }),
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusSm,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Radio<int>(
                                          value: 1,
                                          activeColor:
                                              theme.colorScheme.primary,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Custom Dates',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: theme
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_reportType == 0)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Select Semester: ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: _showSemesterPicker,
                                borderRadius: BorderRadius.circular(
                                  AppDimens.radiusMd,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white.withAlpha(12)
                                        : Colors.black.withAlpha(8),
                                    borderRadius: BorderRadius.circular(
                                      AppDimens.radiusMd,
                                    ),
                                    border: Border.all(
                                      color: theme.dividerColor,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.school_outlined,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Semester $_selectedSemester',
                                        style: TextStyle(
                                          color:
                                              theme.textTheme.bodyLarge?.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color:
                                            theme.textTheme.bodyMedium?.color,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickDate(true),
                                  icon: const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 16,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.primary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    side: BorderSide(
                                      color: theme.colorScheme.primary
                                          .withAlpha(180),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppDimens.radiusMd,
                                      ),
                                    ),
                                  ),
                                  label: Text(
                                    _startDate == null
                                        ? 'Start Date'
                                        : DateFormat(
                                            'MMM dd, yyyy',
                                          ).format(_startDate!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickDate(false),
                                  icon: const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 16,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.primary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    side: BorderSide(
                                      color: theme.colorScheme.primary
                                          .withAlpha(180),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppDimens.radiusMd,
                                      ),
                                    ),
                                  ),
                                  label: Text(
                                    _endDate == null
                                        ? 'End Date'
                                        : DateFormat(
                                            'MMM dd, yyyy',
                                          ).format(_endDate!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        // The pickers already refuse everything outside the
                        // record span; saying what the span *is* saves the user
                        // discovering it by tapping greyed-out days.
                        if (_reportType == 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            _recordFirstDate == null || _recordLastDate == null
                                ? _boundsLoaded
                                      ? 'No attendance records for Semester '
                                            '$_selectedSemester yet.'
                                      : 'Loading available dates…'
                                : 'Records available '
                                      '${DateFormat('MMM dd, yyyy').format(_recordFirstDate!)}'
                                      ' – '
                                      '${DateFormat('MMM dd, yyyy').format(_recordLastDate!)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isGenerating ? null : _generateReport,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimens.radiusMd,
                                ),
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
                  const SizedBox(height: 12),
                  if (!_reportGenerated)
                    _emptyState(
                      theme: theme,
                      icon: Icons.assessment_outlined,
                      title: 'No report yet',
                      message:
                          'Choose a semester or date range above, then tap '
                          'Generate Report to see your breakdown.',
                    )
                  else if (_totalLectures == 0)
                    _emptyState(
                      theme: theme,
                      icon: Icons.event_busy_outlined,
                      title: 'No attendance data',
                      message:
                          'There are no records for this period. Try a '
                          'different range or mark some attendance first.',
                    )
                  else
                    ..._buildResults(theme, c),
                  const SizedBox(height: 12),
                  const CalloutBox(
                    kind: CalloutKind.info,
                    title: 'Note:',
                    message:
                        'Reports use the same records as your dashboard, so the '
                        'numbers always match.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Centered icon + title + message inside the shared card shell — replaces
  /// the old bare text floating in an empty pane.
  Widget _emptyState({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String message,
  }) {
    final Color secondary =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space20,
        vertical: AppDimens.space24,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: secondary.withAlpha(20),
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor),
            ),
            child: Icon(icon, size: 26, color: secondary),
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDimens.space6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// The generated-report body: overall summary card, export button, then the
  /// per-subject breakdown cards (dashboard color split).
  List<Widget> _buildResults(ThemeData theme, AppColors c) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Text(
              'Overall Attendance',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_overallPercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: _overallPercent >= 75 ? c.success : c.danger,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_totalAttended / $_totalLectures Lectures Attended',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _showExportOptions,
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Export & Share PDF'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              'Subject Breakdown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          // The chevron on each card is small; saying it outright is what makes
          // the rows discoverable as more than a table.
          Flexible(
            child: Text(
              'Tap a subject for details',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ..._subjects.map((sub) {
        final stat = _stats[sub.id] ?? {'attended': 0, 'total': 0};
        final attended = stat['attended']!;
        final total = stat['total']!;
        final percent = total == 0 ? 0.0 : (attended / total) * 100;
        final bool isSafe = percent >= sub.requiredPercent;
        final Color color = isSafe ? c.success : c.danger;
        final Color barColor = isSafe
            ? const Color(0xFF49AD4F)
            : const Color(0xFFF14134);

        return Padding(
          // The bottom gap was the Card's own `margin`, which put it inside the
          // anchor below — so the transform started from a box 8px taller than
          // the card. Moved out here, the recorded rect is the card exactly.
          padding: const EdgeInsets.only(bottom: 8),
          child: ContainerTransformAnchor(
            borderRadius: AppDimens.radiusMd,
            child: Pressable(
              borderRadius: AppDimens.brMd,
              onTap: () => _openSubject(sub),
              child: Card(
                margin: EdgeInsets.zero,
                color: theme.cardColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  side: BorderSide(color: theme.dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        // Top-aligned so the percentage tracks the name's first
                        // line now that a long name wraps.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            // Name + chevron, laid out as on the Dashboard card:
                            // Flexible (not Expanded) so a short name takes only
                            // its own width and the chevron follows it rather
                            // than parking against the percentage. The chevron is
                            // the only thing on the card saying it opens.
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    sub.name,
                                    // Two lines: a report row is unusable if you
                                    // cannot tell which subject it belongs to.
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      height: 1.25,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppDimens.space4),
                                // Nudged onto the first line's optical centre,
                                // since the row is top-aligned for wrapping.
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: theme.dividerColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Text(
                            '${percent.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: total == 0 ? 0 : percent / 100,
                        color: barColor,
                        backgroundColor: theme.dividerColor,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                      const SizedBox(height: 6),
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
              ),
            ),
          ),
        );
      }),
    ];
  }
}
