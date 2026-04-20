import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/local_pdf_parser.dart';
import 'basic_info_screen.dart';

class UploadPdfScreen extends StatefulWidget {
  const UploadPdfScreen({super.key});

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  bool _isUploading = false;

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
            const SnackBar(content: Text('Could not read the selected PDF file.')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final Map<String, dynamic> parsedData =
          await LocalPdfParser.extractAttendanceFromPdf(fileBytes);

      setState(() => _isUploading = false);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BasicInfoScreen(
              isEditMode: false,
              prefilledData: parsedData,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final displayErr = e.toString().replaceAll('FormatException: ', '').replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $displayErr'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Upload Report'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.textTheme.bodyLarge?.color,
      ),
      body: SafeArea(
        child: Center(
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
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : theme.colorScheme.primary.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                "Smart PDF Extraction",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Upload your attendance PDF to instantly extract your subjects and attendance records. Fully offline — no internet needed.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 48),

              if (_isUploading)
                Column(
                  children: [
                    CircularProgressIndicator(color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Analyzing PDF locally...',
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _pickAndUploadPdf,
                  icon: const Icon(Icons.upload_file),
                  label: const Text(
                    'Select PDF Report',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
                
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.indigo.withOpacity(0.15) : Colors.indigo.shade50.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.indigo.withOpacity(0.3) : Colors.indigo.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded, color: isDark ? Colors.indigo.shade300 : Colors.indigo.shade600, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            "This offline parser is exclusively configured for the detailed reports of Mithibai College students.",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              color: isDark ? Colors.indigo.shade100 : Colors.indigo.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.indigo.withOpacity(0.3) : Colors.indigo.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    Text(
                      "Students from other colleges, please use our Smart AI Web version for accurate insights.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final url = Uri.parse('https://attendease-backend-ndxs.onrender.com/');
                          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                            debugPrint('Could not launch web URL');
                          }
                        },
                        icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                        label: const Text('Open Web Version', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.indigo.shade300 : Colors.indigo.shade700,
                          side: BorderSide(color: isDark ? Colors.indigo.withOpacity(0.4) : Colors.indigo.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
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
