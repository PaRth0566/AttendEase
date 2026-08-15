import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_refresh_bus.dart';
import '../../services/attendance_report_sync_service.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/pdf_source_widgets.dart';
import '../../widgets/report_replace_dialog.dart';

class RefreshPdfScreen extends StatefulWidget {
  const RefreshPdfScreen({super.key});

  @override
  State<RefreshPdfScreen> createState() => _RefreshPdfScreenState();
}

class _RefreshPdfScreenState extends State<RefreshPdfScreen> {
  bool _isUploading = false;
  String _statusMessage =
      'Select your latest attendance PDF to sync new records.';
  bool _isDone = false;

  /// Picks and imports a report through [AttendanceReportSyncService] — the same
  /// path the dashboard's circular sync button takes, so the two cannot drift.
  Future<void> _pickAndRefresh() async {
    try {
      final result = await const AttendanceReportSyncService().pickAndSync(
        onStage: (stage) {
          if (!mounted) return;
          setState(() {
            _isUploading = true;
            _isDone = false;
            _statusMessage = switch (stage) {
              ReportSyncStage.reading => 'Reading your attendance report...',
              ReportSyncStage.updating => 'Updating your records...',
              ReportSyncStage.saving => 'Saving to cloud...',
            };
          });
        },
        // A report for someone else's course cannot be folded into this one, so
        // the import stops here and asks before anything is written.
        confirmReplace: (mismatch) async {
          if (!mounted) return false;
          return confirmReportReplace(context, mismatch);
        },
      );
      if (!mounted) return;

      // A dismissed file picker, or a declined replacement: nothing imported,
      // nothing to report.
      if (result == null) {
        setState(() {
          _isUploading = false;
          _statusMessage =
              'Select your latest attendance PDF to sync new records.';
        });
        return;
      }

      // The tabs behind this screen are still mounted, so they are told to
      // re-read rather than left showing the previous report.
      AppRefreshBus.instance.refreshAll();

      setState(() {
        _isUploading = false;
        _isDone = true;
        _statusMessage = result.replacedPreviousData
            ? 'Done! Your data has been replaced with the new report.'
            : 'Done! Your attendance records have been updated.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage =
              'Select your latest attendance PDF to sync new records.';
        });
        // The snackbar surface follows the active theme; the danger colour
        // rides on the icon rather than flooding the bar.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: context.appColors.danger,
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(AttendanceReportSyncService.friendlyError(e)),
                ),
              ],
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _launchSAPPortal() async {
    final Uri url = Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        final c = context.appColors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
                const SizedBox(width: AppDimens.space12),
                const Expanded(child: Text('Could not launch SAP Portal.')),
              ],
            ),
          ),
        );
      }
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
                          color: theme.colorScheme.primary,
                        ),
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
                        label: const Text(
                          'Back to Dashboard',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusLg,
                            ),
                          ),
                        ),
                      ),
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
