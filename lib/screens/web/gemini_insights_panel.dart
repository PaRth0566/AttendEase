import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../models/subject.dart';
import 'ai_dashboard_screen.dart';

class GeminiInsightsPanel extends StatefulWidget {
  const GeminiInsightsPanel({super.key});

  @override
  State<GeminiInsightsPanel> createState() => _GeminiInsightsPanelState();
}

class _GeminiInsightsPanelState extends State<GeminiInsightsPanel>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
  String? _fileName;

  final TextEditingController _overallTargetCtrl =
      TextEditingController(text: '75');
  final TextEditingController _subjectTargetCtrl =
      TextEditingController(text: '70');

  List<Subject>? _parsedSubjects;
  Map<int, Map<String, int>>? _parsedStats;
  Map<String, String>? _reportMeta;

  late AnimationController _resultController;
  late Animation<double> _resultFade;

  @override
  void initState() {
    super.initState();
    _resultController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _resultFade =
        CurvedAnimation(parent: _resultController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _overallTargetCtrl.dispose();
    _subjectTargetCtrl.dispose();
    _resultController.dispose();
    super.dispose();
  }

  double get _overallTarget =>
      double.tryParse(_overallTargetCtrl.text) ?? 75.0;
  double get _subjectTarget =>
      double.tryParse(_subjectTargetCtrl.text) ?? 70.0;

  Future<void> _uploadAndAnalyze() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _parsedSubjects = null;
        _parsedStats = null;
        _reportMeta = null;
        _fileName = result.files.first.name;
      });

      final PlatformFile file = result.files.first;
      final List<int>? bytes = file.bytes;

      if (bytes == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load file bytes. Please try again.";
        });
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
            'https://attendease-backend-ndxs.onrender.com/api/analyze-attendance'),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'report',
          bytes,
          filename: file.name,
          contentType: MediaType('application', 'pdf'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          try {
            final String rawJsonInsights = data['insights'] as String;
            final String cleanedJson = rawJsonInsights
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();
            final Map<String, dynamic> parsedJson = jsonDecode(cleanedJson);

            // Extract metadata
            final Map<String, String> meta = {
              'studentName': (parsedJson['studentName'] ?? '').toString(),
              'semester': (parsedJson['semester'] ?? '').toString(),
              'program': (parsedJson['program'] ?? '').toString(),
              'academicYear': (parsedJson['academicYear'] ?? '').toString(),
              'reportStartDate':
                  (parsedJson['reportStartDate'] ?? '').toString(),
              'reportEndDate': (parsedJson['reportEndDate'] ?? '').toString(),
            };

            final List<Subject> extractedSubjects = [];
            final Map<int, Map<String, int>> extractedStats = {};

            int idCounter = 1;
            for (var item in parsedJson['subjects']) {
              extractedSubjects.add(Subject(
                id: idCounter,
                name: item['name'],
                requiredPercent: _subjectTarget,
                semester: 1,
              ));
              extractedStats[idCounter] = {
                'attended': int.parse(item['attended'].toString()),
                'total': int.parse(item['total'].toString()),
              };
              idCounter++;
            }

            setState(() {
              _parsedSubjects = extractedSubjects;
              _parsedStats = extractedStats;
              _reportMeta = meta;
              _isLoading = false;
            });
            _resultController.forward(from: 0);
          } catch (parseError) {
            setState(() {
              _errorMessage = 'Failed to parse AI output: $parseError';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage =
                data['error'] as String? ?? 'Unknown backend error.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'Server returned ${response.statusCode}: ${response.body}';
          _isLoading = false;
        });
      }
    } on http.ClientException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // Always return a plain Column — parent handles scrolling
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildUploadCard(theme, isDark),

        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(),
        ],

        if (_parsedSubjects != null && _parsedStats != null) ...[
          const SizedBox(height: 20),
          FadeTransition(
            opacity: _resultFade,
            child: AIDashboardScreen(
              subjects: _parsedSubjects!,
              attendanceStats: _parsedStats!,
              overallTarget: _overallTarget,
              subjectTarget: _subjectTarget,
              reportMeta: _reportMeta,
            ),
          ),
        ],

        if (_parsedSubjects == null && _errorMessage == null && !_isLoading) ...[
          const SizedBox(height: 20),
          SizedBox(
            height: 340,
            child: _buildIdleState(theme, isDark),
          ),
        ],
      ],
    );
  }

  Widget _buildUploadCard(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.07),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          // ── Top Row: Icon + Title + Upload Button ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Attendance Analyzer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _fileName != null
                          ? 'Selected: $_fileName'
                          : 'Upload your PDF for instant insights',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withOpacity(0.5)
                            : const Color(0xFF94A3B8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _isLoading
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF6366F1).withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _uploadAndAnalyze,
                        icon: const Icon(Icons.upload_file_rounded,
                            size: 16),
                        label: const Text('Upload PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Bottom Row: Two small target inputs ────────
          Row(
            children: [
              Expanded(
                child: _buildTargetInput(
                  controller: _overallTargetCtrl,
                  label: 'Overall Target %',
                  icon: Icons.pie_chart_outline_rounded,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTargetInput(
                  controller: _subjectTargetCtrl,
                  label: 'Per Subject Target %',
                  icon: Icons.menu_book_rounded,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isDark
                  ? const Color(0xFF818CF8)
                  : const Color(0xFF6366F1)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white.withOpacity(0.4)
                      : const Color(0xFF94A3B8),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Text(
            '%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withOpacity(0.35)
                  : const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: const Icon(Icons.close_rounded,
                color: Colors.redAccent, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleState(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ready to Analyze',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Upload your PDF attendance report above\nto generate instant AI-powered insights.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}