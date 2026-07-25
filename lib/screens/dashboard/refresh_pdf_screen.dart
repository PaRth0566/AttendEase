import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/local_pdf_parser.dart';
import '../../services/cloud_sync_service.dart';

import '../../services/pdf_attendance_import_service.dart';

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
    final isDark = theme.brightness == Brightness.dark;

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
            child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 24,
            vertical: 24,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon with gradient glow
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isDone
                          ? [Colors.green.shade500, Colors.teal.shade500]
                          : [const Color(0xFF6366F1), const Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isDone ? Colors.green.shade500 : const Color(0xFF6366F1)).withValues(alpha: 0.35),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isDone ? Icons.check_circle_rounded : Icons.cloud_sync_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              Text(
                _isDone ? 'Sync Complete' : 'Sync Attendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _statusMessage,
                  key: ValueKey(_statusMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.6, color: theme.textTheme.bodyMedium?.color),
                ),
              ),
              const SizedBox(height: 16),

              if (!_isDone && !_isUploading)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: Colors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Note: Semester is auto-detected. Only that specific semester will be updated, leaving others untouched.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 48),

              if (_isUploading)
                Column(
                  children: [
                    CircularProgressIndicator(color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else if (_isDone)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Back to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Primary CTA — Select PDF
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _pickAndRefresh,
                        icon: const Icon(Icons.upload_file_rounded, size: 20),
                        label: const Text(
                          'Select PDF Report',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Secondary CTA — SAP Portal (outlined amber style)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDark
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.08)
                            : const Color(0xFFFFF7ED),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFFFBBF24).withValues(alpha: 0.35)
                              : const Color(0xFFD97706).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _launchSAPPortal,
                        icon: Icon(
                          Icons.open_in_browser_rounded,
                          size: 20,
                          color: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFD97706),
                        ),
                        label: Text(
                          'Download PDF from SAP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFD97706),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFD97706),
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
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
