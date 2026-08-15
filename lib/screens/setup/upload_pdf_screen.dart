import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/local_pdf_parser.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/pdf_source_widgets.dart';

class UploadPdfScreen extends StatefulWidget {
  const UploadPdfScreen({super.key});

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  bool _isUploading = false;

  /// Cap on the local parse. A well-formed report parses in well under a second;
  /// anything past this is a PDF the parser cannot handle, and an unbounded
  /// await there is what left the first-time upload spinning with no way out.
  static const Duration _parseTimeout = Duration(seconds: 25);

  Future<void> _pickAndUploadPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User canceled
      }

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read the selected PDF file.'),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() => _isUploading = true);

      // Bound the parse so the user always gets their screen back instead of an
      // infinite spinner (.timeout abandons the future; the short-lived isolate
      // is left to finish and be collected).
      final Map<String, dynamic> parsedData =
          await LocalPdfParser.extractAttendanceFromPdf(
            fileBytes,
          ).timeout(_parseTimeout);

      if (!mounted) return;
      context.go('/setup/basic', extra: parsedData);
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException
            ? "This PDF took too long to read. Make sure it's the attendance "
                  "report downloaded from SAP."
            : e is FormatException
            ? e.message
            : 'Something went wrong. Please try again with a valid attendance PDF.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      // The spinner must never outlive the operation, including on an early
      // return or an exception thrown after it was set.
      if (mounted && _isUploading) setState(() => _isUploading = false);
    }
  }

  Future<void> _launchSAPPortal() async {
    final Uri url = Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Could not launch SAP Portal.')),
        );
      }
    }
  }

  Future<void> _launchWebVersion() async {
    final url = Uri.parse('https://attendease-cbc6f.web.app/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch web URL');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = context.appColors.warning;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Upload Report'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.textTheme.bodyLarge?.color,
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
                  // Same layout as the Sync screen (shared widgets) with
                  // setup-appropriate copy and step labels (§8).
                  const PdfSourceHeroCard(
                    icon: Icons.upload_file_rounded,
                    title: 'Import Attendance',
                    subtitle:
                        'Upload your attendance PDF to extract your subjects '
                        'and records — fully offline.',
                    steps: [
                      PdfSourceStep('Select PDF'),
                      PdfSourceStep('Details'),
                      PdfSourceStep('Done'),
                    ],
                    currentStep: 1,
                  ),
                  const SizedBox(height: AppDimens.space16),

                  const CalloutBox(
                    kind: CalloutKind.info,
                    title: 'Note:',
                    message: 'Semester is auto-detected from your report.',
                  ),
                  const SizedBox(height: AppDimens.space24),

                  if (_isUploading)
                    Column(
                      children: [
                        CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Analyzing PDF locally...',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Text(
                      'Choose PDF Source',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select how you want to add your attendance report.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppDimens.space20),
                    PdfSourceCard(
                      icon: Icons.folder_open_rounded,
                      title: 'Select PDF Report',
                      subtitle:
                          'Browse and upload your attendance PDF from device.',
                      accent: theme.colorScheme.primary,
                      onTap: _pickAndUploadPdf,
                    ),
                    const SizedBox(height: AppDimens.space16),
                    PdfSourceCard(
                      icon: Icons.cloud_download_rounded,
                      title: 'Download PDF from SAP',
                      subtitle:
                          'Download your attendance report directly from the '
                          'SAP portal.',
                      accent: amber,
                      onTap: _launchSAPPortal,
                    ),
                    const SizedBox(height: AppDimens.space24),
                    const ReassuranceCard(
                      title: 'Fully offline extraction.',
                      subtitle:
                          'Your PDF is parsed on-device — nothing is uploaded.',
                    ),
                    const SizedBox(height: AppDimens.space16),
                    Center(
                      child: TextButton.icon(
                        onPressed: _launchWebVersion,
                        icon: const Icon(
                          Icons.open_in_browser_rounded,
                          size: 18,
                        ),
                        label: const Text('Not Mithibai? Open the Web Version'),
                      ),
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
