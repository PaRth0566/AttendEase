import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../models/subject.dart';
import 'aura_ai_dashboard.dart';

// ── JS interop: reads globals set by index.html drop handler ────────────────
@JS('_flutterDropFileName')
external String? get _jsDropFileName;

@JS('_flutterDropFileBase64')
external String? get _jsDropFileBase64;

class AuraUploadConfig extends StatefulWidget {
  final Function(
    List<Subject> subjects,
    Map<int, Map<String, int>> stats,
    Map<String, String> meta,
    double overallTarget,
    double subjectTarget,
  )?
  onConfigured;

  const AuraUploadConfig({super.key, this.onConfigured});

  @override
  State<AuraUploadConfig> createState() => _AuraUploadConfigState();
}

class _AuraUploadConfigState extends State<AuraUploadConfig> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _fileName;
  bool _isDragging = false;
  bool _hasConsented = false;

  // ── Web drag-and-drop JS bridge listeners ─────────────────
  web.EventListener? _onFileDropped;
  web.EventListener? _onDragEnter;
  web.EventListener? _onDragLeave;

  // ── Progress animation state ──────────────────────────────

  int _progressStep = 0;
  double _progressValue = 0.0;
  bool _isHolding = false; // true when animation has caught up to API
  int _holdingHintIndex = 0; // cycles through holding hints
  Timer? _holdingHintTimer;
  bool _isStopped = false; // guard so delayed futures don't fire after done

  /// Steps: (icon, title, subtitle, dwell-ms before moving to next)
  static const _progressSteps = [
    // First step absorbs server cold-start (free-tier ~15 s)
    (
      Icons.cloud_upload_rounded,
      'Uploading PDF',
      'Securely transferring your report…',
      5000,
    ),
    (
      Icons.document_scanner_rounded,
      'Reading document',
      'Extracting text and structure…',
      8000,
    ),
    (
      Icons.calculate_rounded,
      'Calculating lectures',
      'Counting attended & total classes…',
      7000,
    ),
    (
      Icons.bar_chart_rounded,
      'Building subject stats',
      'Aggregating per-subject data…',
      7000,
    ),
    (
      Icons.auto_graph_rounded,
      'Running predictions',
      'Estimating future attendance needs…',
      7000,
    ),
    // ── Hold here until API responds ──────────────────────
    (
      Icons.psychology_rounded,
      'Analysing attendance',
      'AI is scanning every lecture row…',
      0,
    ),
    // Final step — triggered by _stopProgressAnimation()
    (
      Icons.fact_check_rounded,
      'Finalising report',
      'Packaging your personalised insights…',
      0,
    ),
  ];

  /// Hints cycled every 4 s while waiting for the API after animation catches up
  static const _holdingHints = [
    'Still processing — complex reports take time…',
    'AI is cross-referencing attendance records…',
    'Server is working hard, almost there…',
    'Hang tight! Generating your personalised insights…',
    'Large PDFs may take a minute — please don\'t close the tab…',
  ];

  /// Runs each step for its own dwell duration sequentially.
  Future<void> _startProgressAnimation() async {
    _progressStep = 0;
    _progressValue = 0.0;
    _isHolding = false;
    _holdingHintIndex = 0;
    _isStopped = false;
    if (mounted) setState(() {});

    // Advance through steps until the penultimate one (hold step)
    final holdAt = _progressSteps.length - 2;
    for (int i = 1; i <= holdAt; i++) {
      final dwell = _progressSteps[i - 1].$4;
      await Future.delayed(Duration(milliseconds: dwell));
      if (_isStopped || !mounted) return;
      setState(() {
        _progressStep = i;
        _progressValue = i / (_progressSteps.length - 1);
      });
    }

    // We've caught up — switch to holding/indeterminate state
    if (_isStopped || !mounted) return;
    setState(() => _isHolding = true);

    // Cycle hint text every 4 s while holding
    _holdingHintTimer = Timer.periodic(const Duration(milliseconds: 4000), (t) {
      if (!mounted || _isStopped) {
        t.cancel();
        return;
      }
      setState(() {
        _holdingHintIndex = (_holdingHintIndex + 1) % _holdingHints.length;
      });
    });
  }

  void _stopProgressAnimation() {
    _isStopped = true;
    _holdingHintTimer?.cancel();
    _holdingHintTimer = null;
    setState(() {
      _isHolding = false;
      _progressStep = _progressSteps.length - 1;
      _progressValue = 1.0;
    });
  }

  final TextEditingController _overallTargetCtrl = TextEditingController(
    text: '75',
  );
  final TextEditingController _subjectTargetCtrl = TextEditingController(
    text: '70',
  );

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _onFileDropped = ((web.Event _) => _handleWebDrop()).toJS;
      _onDragEnter = ((web.Event _) {
        if (mounted) setState(() => _isDragging = true);
      }).toJS;
      _onDragLeave = ((web.Event _) {
        if (mounted) setState(() => _isDragging = false);
      }).toJS;
      web.window.addEventListener('flutter_file_dropped', _onFileDropped!);
      web.window.addEventListener('flutter_drag_enter', _onDragEnter!);
      web.window.addEventListener('flutter_drag_leave', _onDragLeave!);
    }
  }

  void _handleWebDrop() {
    if (!_hasConsented) {
      setState(() {
        _isDragging = false;
        _errorMessage = 'Please check the AI Privacy Consent box before uploading.';
      });
      return;
    }
    final name = _jsDropFileName;
    final base64 = _jsDropFileBase64;
    if (name == null || base64 == null || base64.isEmpty) return;
    if (!name.toLowerCase().endsWith('.pdf')) {
      setState(() {
        _isDragging = false;
        _errorMessage = 'Please drop a valid .pdf file. Only PDF files are supported.';
      });
      return;
    }
    setState(() => _isDragging = false);
    try {
      final bytes = base64Decode(base64);
      _processFile(name, bytes);
    } catch (e) {
      setState(() => _errorMessage = 'Could not read the dropped file. Try the click to upload option instead.');
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      if (_onFileDropped != null) {
        web.window.removeEventListener('flutter_file_dropped', _onFileDropped!);
      }
      if (_onDragEnter != null) {
        web.window.removeEventListener('flutter_drag_enter', _onDragEnter!);
      }
      if (_onDragLeave != null) {
        web.window.removeEventListener('flutter_drag_leave', _onDragLeave!);
      }
    }
    _isStopped = true;
    _holdingHintTimer?.cancel();
    _overallTargetCtrl.dispose();
    _subjectTargetCtrl.dispose();
    super.dispose();
  }

  List<Subject>? _parsedSubjects;
  Map<int, Map<String, int>>? _parsedStats;
  Map<String, String>? _reportMeta;

  double get _overallTarget => double.tryParse(_overallTargetCtrl.text) ?? 75.0;
  double get _subjectTarget => double.tryParse(_subjectTargetCtrl.text) ?? 70.0;

  Future<void> _handleUpload() async {
    if (!_hasConsented) {
      setState(() {
        _errorMessage = 'Please check the AI Privacy Consent box before uploading.';
      });
      return;
    }
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _errorMessage = 'Could not read the selected file. Please try again.';
        });
        return;
      }
      await _processFile(file.name, bytes);
    } catch (e) {
      setState(
        () => _errorMessage =
            'Something went wrong while selecting the file. Please try again.',
      );
    }
  }

  Future<void> _processFile(String name, List<int> bytes) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _parsedSubjects = null;
        _parsedStats = null;
        _reportMeta = null;
        _fileName = name;
      });
      _startProgressAnimation();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://attendease-backend-ndxs.onrender.com/api/analyze-attendance',
        ),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'report',
          bytes,
          filename: name,
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

            final Map<String, String> meta = {
              'studentName': (parsedJson['studentName'] ?? '').toString(),
              'semester': (parsedJson['semester'] ?? '').toString(),
              'program': (parsedJson['program'] ?? '').toString(),
              'academicYear': (parsedJson['academicYear'] ?? '').toString(),
              'reportStartDate': (parsedJson['reportStartDate'] ?? '')
                  .toString(),
              'reportEndDate': (parsedJson['reportEndDate'] ?? '').toString(),
            };

            final List<Subject> extractedSubjects = [];
            final Map<int, Map<String, int>> extractedStats = {};

            int idCounter = 1;
            for (var item in parsedJson['subjects']) {
              extractedSubjects.add(
                Subject(
                  id: idCounter,
                  name: item['name'],
                  requiredPercent: _subjectTarget,
                  semester: 1,
                ),
              );
              extractedStats[idCounter] = {
                'attended': int.parse(item['attended'].toString()),
                'total': int.parse(item['total'].toString()),
              };
              idCounter++;
            }

            if (extractedSubjects.isEmpty ||
                meta['reportStartDate']!.isEmpty ||
                meta['reportEndDate']!.isEmpty) {
              throw Exception(
                'Invalid document type: upload valid attendance report.',
              );
            }

            setState(() {
              _parsedSubjects = extractedSubjects;
              _parsedStats = extractedStats;
              _reportMeta = meta;
              _isLoading = false;
            });
            _stopProgressAnimation();

            if (widget.onConfigured != null) {
              widget.onConfigured!(
                extractedSubjects,
                extractedStats,
                meta,
                _overallTarget,
                _subjectTarget,
              );
            }
          } catch (parseError) {
            _stopProgressAnimation();
            setState(() {
              _errorMessage =
                  'Unable to read your attendance report. Please ensure you uploaded the correct PDF file.';
              _isLoading = false;
            });
          }
        } else {
          _stopProgressAnimation();
          setState(() {
            _errorMessage =
                data['error'] as String? ??
                'Something went wrong while processing your report. Please try again.';
            _isLoading = false;
          });
        }
      } else {
        _stopProgressAnimation();
        setState(() {
          _errorMessage = response.statusCode >= 500
              ? 'The service is temporarily unavailable. Please try again in a few minutes.'
              : 'Could not process your report. Please try again.';
          _isLoading = false;
        });
      }
    } on http.ClientException {
      _stopProgressAnimation();
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Network error. Please check your internet connection and try again.';
      });
    } catch (e) {
      _stopProgressAnimation();
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_parsedSubjects != null &&
        _parsedStats != null &&
        widget.onConfigured == null) {
      return AuraAIDashboard(
        subjects: _parsedSubjects!,
        attendanceStats: _parsedStats!,
        overallTarget: _overallTarget,
        subjectTarget: _subjectTarget,
        reportMeta: _reportMeta,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;

    return Padding(
        padding: EdgeInsets.only(
          left: isMobile ? 16 : 24,
          right: isMobile ? 16 : 24,
          top: isMobile ? 24 : 24,
          bottom: isMobile ? 16 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1024),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Text
                Text(
                  'System Initialization',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isMobile ? 24 : (w < 768 ? 32 : 44),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        colors: isDark
                            ? [
                                const Color(0xFFA5B4FC),
                                const Color(0xFFC7D2FE),
                                const Color(0xFF818CF8),
                              ]
                            : [
                                const Color(0xFF4F46E5),
                                const Color(0xFF7C3AED),
                                const Color(0xFF4338CA),
                              ],
                      ).createShader(const Rect.fromLTWH(0, 0, 400, 80)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure your academic parameters and provide your official data source to begin predictive tracking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isMobile ? 13 : 16,
                    height: 1.5,
                    color: isDark
                        ? const Color(0xFFC7D2FE).withValues(alpha: 0.8)
                        : const Color(0xFF475569),
                  ),
                ),
                SizedBox(height: isMobile ? 16 : 24),

                // Main Content
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    final bannersWidget = LayoutBuilder(
                      builder: (context, innerConstraints) {
                        if (width < 768) {
                          return Column(
                            children: [
                              _buildBanner(
                                isDark,
                                Icons.warning_rounded,
                                'SVKM/Mithibai Students',
                                'Download your detailed attendance report directly from the SAP Portal before uploading.',
                                false,
                                isMobile,
                              ),
                              const SizedBox(height: 12),
                              _buildBanner(
                                isDark,
                                Icons.info_outline_rounded,
                                'Disclaimer',
                                'These insights are AI-generated. Always verify predictive models with official institutional records.',
                                true,
                                isMobile,
                              ),
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildBanner(
                                  isDark,
                                  Icons.warning_rounded,
                                  'SVKM/Mithibai Students',
                                  'Download your detailed attendance report directly from the SAP Portal before uploading.',
                                  false,
                                  isMobile,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: _buildBanner(
                                  isDark,
                                  Icons.info_outline_rounded,
                                  'Disclaimer',
                                  'These insights are AI-generated. Always verify predictive models with official institutional records.',
                                  true,
                                  isMobile,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );

                    final bentoWidget = LayoutBuilder(
                      builder: (context, innerConstraints) {
                        if (width < 900) {
                          return Column(
                            children: [
                              _buildSettingsCard(isDark, isMobile),
                              const SizedBox(height: 16),
                              _buildConsentCheckbox(isDark, isMobile),
                              const SizedBox(height: 16),
                              _buildUploadCard(isDark, isMobile),
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _buildSettingsCard(isDark, isMobile),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  children: [
                                    _buildConsentCheckbox(isDark, isMobile),
                                    const SizedBox(height: 16),
                                    Expanded(child: _buildUploadCard(isDark, isMobile)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );

                    if (isMobile) {
                      return Column(
                        children: [
                          bentoWidget,
                          const SizedBox(height: 24),
                          bannersWidget,
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          bannersWidget,
                          const SizedBox(height: 24),
                          bentoWidget,
                        ],
                      );
                    }
                  },
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF9F1239).withValues(alpha: 0.2)
                          : const Color(0xFFFFE4E6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFFBE123C).withValues(alpha: 0.4)
                            : const Color(0xFFFDA4AF),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFF43F5E),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFFDA4AF)
                                  : const Color(0xFF9F1239),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildBanner(
    bool isDark,
    IconData icon,
    String title,
    String desc,
    bool isInfo,
    bool isMobile,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1B4B).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: 1.5,
              color: isInfo
                  ? (isDark
                        ? const Color(0xFFF43F5E).withValues(alpha: 0.4)
                        : const Color(0xFFFDA4AF))
                  : (isDark
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                        : const Color(0xFFFDE68A)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 6 : 8),
                decoration: BoxDecoration(
                  color: isInfo
                      ? const Color(0xFFF43F5E).withValues(alpha: 0.1)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isInfo
                        ? const Color(0xFFF43F5E).withValues(alpha: 0.2)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  icon,
                  color: isInfo
                      ? const Color(0xFFFB7185)
                      : const Color(0xFFFBBF24),
                  size: isMobile ? 18 : 24,
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 14,
                        color: isDark
                            ? const Color(0xFFC7D2FE).withValues(alpha: 0.7)
                            : const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(bool isDark, bool isMobile) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1B4B).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF818CF8).withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set Targets',
                style: TextStyle(
                  fontSize: isMobile ? 18 : 28,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFF1E293B),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(height: 4),
                Text(
                  'Define thresholds for early warning alerts.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFFC7D2FE).withValues(alpha: 0.7)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
              SizedBox(height: isMobile ? 12 : 32),

              if (isMobile)
                Row(
                  children: [
                    Expanded(
                      child: _buildTargetField(
                        isDark,
                        'OVERALL (%)',
                        null,
                        _overallTargetCtrl,
                        isMobile,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTargetField(
                        isDark,
                        'SUBJECT (%)',
                        null,
                        _subjectTargetCtrl,
                        isMobile,
                      ),
                    ),
                  ],
                )
              else ...[
                _buildTargetField(
                  isDark,
                  'OVERALL TARGET (%)',
                  'Institutional minimum requirement.',
                  _overallTargetCtrl,
                  isMobile,
                ),
                const SizedBox(height: 24),
                _buildTargetField(
                  isDark,
                  'SUBJECT TARGET (%)',
                  'Minimum per-course threshold.',
                  _subjectTargetCtrl,
                  isMobile,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetField(
    bool isDark,
    String label,
    String? subtext,
    TextEditingController ctrl,
    bool isMobile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isDark
                ? const Color(0xFFA5B4FC).withValues(alpha: 0.8)
                : const Color(0xFF64748B),
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        Container(
          height: isMobile ? 40 : 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withValues(alpha: 0.8)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: isMobile ? 14 : 16,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (subtext != null) ...[
          const SizedBox(height: 4),
          Text(
            subtext,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? const Color(0xFFC7D2FE).withValues(alpha: 0.5)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConsentCheckbox(bool isDark, bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasConsented
              ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
              : (isDark ? const Color(0xFF818CF8).withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05)),
        ),
      ),
      child: CheckboxListTile(
        value: _hasConsented,
        onChanged: (val) {
          setState(() {
            _hasConsented = val ?? false;
            if (_hasConsented) _errorMessage = null;
          });
        },
        title: Text(
          'I consent to sending my PDF to Google Gemini AI for processing.',
          style: TextStyle(
            fontSize: isMobile ? 12 : 14,
            color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF1E293B),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Your PDF is sent for one-time analysis and is not stored on our servers.',
            style: TextStyle(
              fontSize: isMobile ? 10 : 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
      ),
    );
  }

  Widget _buildUploadCard(bool isDark, bool isMobile) {
    return GestureDetector(
      onTap: _handleUpload,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: isMobile ? 24 : 60,
              horizontal: isMobile ? 20 : 32,
            ),
            decoration: BoxDecoration(
              color: _isDragging
                  ? (isDark
                        ? const Color(0xFF312E81).withValues(alpha: 0.6)
                        : const Color(0xFFE0E7FF).withValues(alpha: 0.8))
                  : (isDark
                        ? const Color(0xFF1E1B4B).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isDragging
                    ? const Color(0xFF818CF8)
                    : (isDark
                          ? const Color(0xFF818CF8).withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.05)),
                width: _isDragging ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
                  blurRadius: _isDragging ? 80 : 50,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading) ...[
                  // ── Animated progress UI ──────────────────────────
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: _progressValue),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOut,
                    builder: (context, value, _) {
                      return Column(
                        children: [
                          // Step icon
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(scale: anim, child: child),
                            ),
                            child: Container(
                              key: ValueKey(_progressStep),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF312E81).withValues(alpha: 0.4)
                                    : const Color(0xFFEEF2FF),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF818CF8).withValues(alpha: 0.4)
                                      : const Color(0xFFC7D2FE),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF6366F1,
                                    ).withValues(alpha: isDark ? 0.3 : 0.15),
                                    blurRadius: 40,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _progressSteps[_progressStep].$1,
                                size: isMobile ? 40 : 56,
                                color: isDark
                                    ? const Color(0xFFA5B4FC)
                                    : const Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 20 : 28),

                          // Step title
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            child: Text(
                              _progressSteps[_progressStep].$2,
                              key: ValueKey('title_$_progressStep'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFFEEF2FF)
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Step subtitle — holding hint cycles; otherwise fixed
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              _isHolding
                                  ? _holdingHints[_holdingHintIndex]
                                  : _progressSteps[_progressStep].$3,
                              key: ValueKey(
                                _isHolding
                                    ? 'hint_$_holdingHintIndex'
                                    : 'sub_$_progressStep',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                color: isDark
                                    ? const Color(0xFFC7D2FE).withValues(alpha: 0.7)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),

                          SizedBox(height: isMobile ? 24 : 32),

                          // Progress bar — indeterminate while holding, determinate otherwise
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _isHolding
                                ? LinearProgressIndicator(
                                    minHeight: 6,
                                    backgroundColor: isDark
                                        ? const Color(
                                            0xFF312E81,
                                          ).withValues(alpha: 0.4)
                                        : const Color(0xFFE0E7FF),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark
                                          ? const Color(0xFF818CF8)
                                          : const Color(0xFF4F46E5),
                                    ),
                                  )
                                : LinearProgressIndicator(
                                    value: value,
                                    minHeight: 6,
                                    backgroundColor: isDark
                                        ? const Color(
                                            0xFF312E81,
                                          ).withValues(alpha: 0.4)
                                        : const Color(0xFFE0E7FF),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark
                                          ? const Color(0xFF818CF8)
                                          : const Color(0xFF4F46E5),
                                    ),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  // ── Idle upload UI ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF312E81).withValues(alpha: 0.3)
                          : const Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF818CF8).withValues(alpha: 0.3)
                            : const Color(0xFFC7D2FE),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                              : const Color(0xFF6366F1).withValues(alpha: 0.1),
                          blurRadius: 50,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.cloud_upload_rounded,
                      size: isMobile ? 48 : 72,
                      color: isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF6366F1),
                    ),
                  ),
                  SizedBox(height: isMobile ? 12 : 24),
                  Text(
                    _fileName ?? 'Drop your PDF report here',
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_fileName == null)
                    RichText(
                      text: TextSpan(
                        text: 'or ',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFC7D2FE).withValues(alpha: 0.8)
                              : const Color(0xFF64748B),
                          fontSize: 16,
                        ),
                        children: [
                          TextSpan(
                            text: 'click to browse',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF818CF8)
                                  : const Color(0xFF4F46E5),
                            ),
                          ),
                          const TextSpan(text: ' your device'),
                        ],
                      ),
                    )
                  else
                    const Text(
                      'Click to replace file',
                      style: TextStyle(color: Color(0xFFC7D2FE)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ), // closes ClipRRect
    ); // closes GestureDetector
  }
}
