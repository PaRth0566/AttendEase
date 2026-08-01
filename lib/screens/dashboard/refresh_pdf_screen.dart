import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/local_pdf_parser.dart';
import '../../services/cloud_sync_service.dart';

import '../../services/pdf_attendance_import_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/pdf_source_widgets.dart';

class RefreshPdfScreen extends StatefulWidget {
  const RefreshPdfScreen({super.key});

  @override
  State<RefreshPdfScreen> createState() => _RefreshPdfScreenState();
}

class _RefreshPdfScreenState extends State<RefreshPdfScreen> {
  bool _isUploading = false;
  String _statusMessage = 'Select your latest attendance PDF to sync new records.';
  bool _isDone = false;

  Future<void> _pickAndRefresh() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        _showError('Could not read the selected PDF file.');
        return;
      }

      setState(() {
        _isUploading = true;
        _isDone = false;
        _statusMessage = 'Reading your attendance report...';
      });

      final Map<String, dynamic> data =
          await LocalPdfParser.extractAttendanceFromPdf(fileBytes);

      setState(() => _statusMessage = 'Updating your records...');
      await _applyData(data);

      setState(() => _statusMessage = 'Saving to cloud...');
      await CloudSyncService().backupDataToCloud();

      setState(() {
        _isUploading = false;
        _isDone = true;
        _statusMessage = 'Done! Your attendance records have been updated.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'Select your latest attendance PDF to sync new records.';
        });
        // Determine a user-friendly message based on the error type
        String friendlyMsg;
        final raw = e.toString();
        if (e is FormatException) {
          // The parser now throws a user-friendly message — use it directly
          friendlyMsg = e.message;
        } else if (raw.contains('No such file') || raw.contains('FileSystemException')) {
          friendlyMsg = 'The selected file could not be accessed. Please try selecting it again.';
        } else {
          friendlyMsg = 'Something went wrong. Please try again with a valid attendance PDF.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMsg),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  int _parseSemesterNumber(String s, int fallback) {
    final digitMatch = RegExp(r'\b([1-8])\b').firstMatch(s);
    if (digitMatch != null) return int.parse(digitMatch.group(1)!);
    if (RegExp(r'\bviii\b').hasMatch(s)) return 8;
    if (RegExp(r'\bvii\b').hasMatch(s))  return 7;
    if (RegExp(r'\bvi\b').hasMatch(s))   return 6;
    if (RegExp(r'\biv\b').hasMatch(s))   return 4;
    if (RegExp(r'\bv\b').hasMatch(s))    return 5;
    if (RegExp(r'\biii\b').hasMatch(s))  return 3;
    if (RegExp(r'\bii\b').hasMatch(s))   return 2;
    if (RegExp(r'\bi\b').hasMatch(s))    return 1;
    return fallback;
  }

  Future<void> _launchSAPPortal() async {
    final Uri url = Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not launch SAP Portal.'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _applyData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final activeSemester = prefs.getInt('semester') ?? 1;
    
    final semStr = data['semester']?.toString().toLowerCase().trim() ?? '';
    int targetSemester = activeSemester;
    if (semStr.isNotEmpty) {
       targetSemester = _parseSemesterNumber(semStr, activeSemester);
    }

    // Automatically switch the user to the newly uploaded semester
    await prefs.setInt('semester', targetSemester);

    await PdfAttendanceImportService().replaceSemesterFromParsedPdf(
      data: data,
      semester: targetSemester,
    );
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = context.appColors.warning;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sync New Report'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.textTheme.bodyLarge?.color,
        leading: BackButton(onPressed: () => Navigator.pop(context, _isDone)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: AppBreakpoints.isMobile(context) ? 24 : 40,
                vertical: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PdfSourceHeroCard(
                    icon: _isDone
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    title: _isDone ? 'Sync Complete' : 'Sync Attendance',
                    subtitle: _isDone
                        ? 'Your attendance records have been updated.'
                        : 'Import your latest attendance PDF and keep your '
                            'records up to date.',
                    steps: const [
                      PdfSourceStep('Select PDF'),
                      PdfSourceStep('Review'),
                      PdfSourceStep('Sync'),
                    ],
                    currentStep: _isDone ? 3 : 1,
                  ),
                  const SizedBox(height: AppDimens.space16),

                  const CalloutBox(
                    kind: CalloutKind.info,
                    title: 'Note:',
                    message:
                        'Semester is auto-detected. Only that specific semester '
                        'will be updated, leaving others untouched.',
                  ),
                  const SizedBox(height: AppDimens.space24),

                  if (_isUploading)
                    Column(
                      children: [
                        CircularProgressIndicator(
                            color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else if (_isDone)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('Back to Dashboard',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppDimens.radiusLg)),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Choose PDF Source',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select how you want to add your latest attendance report.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppDimens.space20),
                    PdfSourceCard(
                      icon: Icons.folder_open_rounded,
                      title: 'Select PDF Report',
                      subtitle:
                          'Browse and upload your latest attendance PDF from '
                          'device.',
                      accent: theme.colorScheme.primary,
                      onTap: _pickAndRefresh,
                    ),
                    const SizedBox(height: AppDimens.space16),
                    PdfSourceCard(
                      icon: Icons.cloud_download_rounded,
                      title: 'Download PDF from SAP',
                      subtitle:
                          'Download your latest attendance report directly from '
                          'SAP portal.',
                      accent: amber,
                      onTap: _launchSAPPortal,
                    ),
                    const SizedBox(height: AppDimens.space24),
                    const ReassuranceCard(
                      title: 'Your data is safe and secure.',
                      subtitle: 'We only update the selected semester records.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
