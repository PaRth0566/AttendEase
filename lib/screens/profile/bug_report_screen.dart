import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../theme/app_breakpoints.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/callout_box.dart';
import '../../widgets/pdf_source_widgets.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitBugReport() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out both the title and description.')),
      );
      return;
    }

    if (title.length > 200 || desc.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title or description is too long.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'unknown_uid';
      await FirebaseFirestore.instance.collection('bug_reports').add({
        'title': title,
        'description': desc,
        'uid': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bug report submitted successfully! Thank you.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit bug report. Please check your connection and try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Report a Bug'),
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
                  // Sibling of the Sync / Upload screens (§11): same hero card,
                  // no step indicator — this is a one-step form.
                  const PdfSourceHeroCard(
                    icon: Icons.bug_report_rounded,
                    title: 'Found a problem?',
                    subtitle:
                        "Tell us what went wrong and we'll look into it.",
                  ),
                  const SizedBox(height: AppDimens.space16),

                  // Only the account id is attached (see _submitBugReport) — do
                  // not claim device/version details that are not sent.
                  const CalloutBox(
                    kind: CalloutKind.info,
                    title: 'Note:',
                    message:
                        'Your account is attached so we can follow up on your '
                        'report.',
                  ),
                  const SizedBox(height: AppDimens.space24),

                  Text(
                    'Describe the issue',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppDimens.space16),

                  Container(
                    padding: const EdgeInsets.all(AppDimens.space16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Brief Title', theme),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _titleController,
                          maxLength: 200,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            theme,
                            hint: 'E.g. App crashes on login',
                          ),
                        ),
                        const SizedBox(height: AppDimens.space12),
                        _fieldLabel('Detailed Description', theme),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _descController,
                          minLines: 4,
                          maxLines: 6,
                          maxLength: 5000,
                          textInputAction: TextInputAction.newline,
                          decoration: _fieldDecoration(
                            theme,
                            hint:
                                'Please describe the bug and how to reproduce '
                                'it...',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.space24),

                  PrimaryButton(
                    label: 'Submit Bug Report',
                    icon: Icons.send_rounded,
                    loading: _isSubmitting,
                    onPressed: _submitBugReport,
                  ),
                  const SizedBox(height: AppDimens.space24),

                  const ReassuranceCard(
                    title: 'We only receive what you type here.',
                    subtitle: 'No screenshots or files are sent automatically.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, ThemeData theme) {
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.textTheme.bodyMedium?.color,
      ),
    );
  }

  InputDecoration _fieldDecoration(ThemeData theme, {required String hint}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: theme.scaffoldBackgroundColor,
      border: border(theme.dividerColor),
      enabledBorder: border(theme.dividerColor),
      focusedBorder: border(theme.colorScheme.primary, 1.5),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
