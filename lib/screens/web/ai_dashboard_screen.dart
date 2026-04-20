import 'package:flutter/material.dart';
import '../../models/subject.dart';

class AIDashboardScreen extends StatelessWidget {
  final List<Subject> subjects;
  final Map<int, Map<String, int>> attendanceStats;
  final double overallTarget;
  final double subjectTarget;
  final Map<String, String>? reportMeta;

  const AIDashboardScreen({
    super.key,
    required this.subjects,
    required this.attendanceStats,
    this.overallTarget = 75.0,
    this.subjectTarget = 70.0,
    this.reportMeta,
  });

  Map<String, dynamic> _getPredictiveInsight(
      int attended, int total, double requiredPercent) {
    if (total == 0) {
      return {'text': 'No classes recorded yet.', 'isSafe': true};
    }
    double reqFrac = requiredPercent / 100;
    double currentPercent = (attended / total) * 100;
    if (currentPercent >= requiredPercent) {
      int skips = ((attended / reqFrac) - total).floor();
      if (skips <= 0) {
        return {
          'text': 'On track — cannot skip next lecture.',
          'isSafe': true
        };
      }
      return {
        'text':
            'Can safely skip $skips more lecture${skips > 1 ? 's' : ''}.',
        'isSafe': true
      };
    } else {
      int attends =
          (((reqFrac * total) - attended) / (1 - reqFrac)).ceil();
      return {
        'text':
            'Attend $attends more lecture${attends > 1 ? 's' : ''} to reach ${requiredPercent.toStringAsFixed(0)}%.',
        'isSafe': false
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int totalAttended = 0;
    int totalLectures = 0;

    for (final subject in subjects) {
      final stat = attendanceStats[subject.id] ?? {'attended': 0, 'total': 0};
      totalAttended += stat['attended']!;
      totalLectures += stat['total']!;
    }

    double overallPercent =
        totalLectures == 0 ? 0 : (totalAttended / totalLectures) * 100;

    final sortedSubjects = List<Subject>.from(subjects);
    sortedSubjects.sort((a, b) {
      final statA = attendanceStats[a.id] ?? {'attended': 0, 'total': 0};
      final statB = attendanceStats[b.id] ?? {'attended': 0, 'total': 0};
      final pA = statA['total'] == 0
          ? 0.0
          : statA['attended']! / statA['total']! * 100;
      final pB = statB['total'] == 0
          ? 0.0
          : statB['attended']! / statB['total']! * 100;
      return pA.compareTo(pB);
    });

    bool isSafe = overallPercent >= overallTarget;
    final overallInsight =
        _getPredictiveInsight(totalAttended, totalLectures, overallTarget);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Report Metadata Card ─────────────────────────────
        if (reportMeta != null && _hasAnyMeta()) ...[
            _buildMetaCard(isDark),
            const SizedBox(height: 16),
          ],

          // ── Overall Summary Hero ─────────────────────────────
          _buildOverallCard(overallPercent, totalAttended, totalLectures,
              isSafe, overallInsight, isDark),
          const SizedBox(height: 24),

          // ── Subject Grid Header ──────────────────────────────
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Subject Breakdown  •  ${sortedSubjects.length} subjects',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Subject Cards ────────────────────────────────────
          if (sortedSubjects.isEmpty)
            _buildEmptySubjects(isDark)
          else
            ...sortedSubjects.map((subject) {
              final stat = attendanceStats[subject.id] ??
                  {'attended': 0, 'total': 0};
              final double percent = stat['total'] == 0
                  ? 0.0
                  : (stat['attended']! / stat['total']!) * 100;
              return _buildSubjectCard(subject, percent, stat['attended']!,
                  stat['total']!, isDark);
            }),
            
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.red.withOpacity(0.1) : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.red.withOpacity(0.3) : Colors.red.shade200,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 22,
                  color: isDark ? Colors.red.shade400 : Colors.red.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Disclaimer: AttendEase is an automated tool. We are not liable for any calculation inaccuracies or resulting consequences. Please verify your attendance with official college records.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  bool _hasAnyMeta() {
    if (reportMeta == null) return false;
    return reportMeta!.values.any((v) => v.isNotEmpty);
  }

  Widget _buildMetaCard(bool isDark) {
    final meta = reportMeta!;
    final name = meta['studentName'] ?? '';
    final semester = meta['semester'] ?? '';
    final program = meta['program'] ?? '';
    final academicYear = meta['academicYear'] ?? '';
    final startDate = meta['reportStartDate'] ?? '';
    final endDate = meta['reportEndDate'] ?? '';

    final dateRange = (startDate.isNotEmpty && endDate.isNotEmpty)
        ? '$startDate  →  $endDate'
        : startDate.isNotEmpty
            ? startDate
            : endDate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline_rounded,
                    color: Color(0xFF6366F1), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : 'Student Report',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          if (program.isNotEmpty ||
              semester.isNotEmpty ||
              academicYear.isNotEmpty ||
              dateRange.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (program.isNotEmpty)
                  _metaChip(Icons.school_outlined, program, isDark),
                if (semester.isNotEmpty)
                  _metaChip(Icons.calendar_view_month_rounded, semester, isDark),
                if (academicYear.isNotEmpty)
                  _metaChip(Icons.date_range_rounded, academicYear, isDark),
                if (dateRange.isNotEmpty)
                  _metaChip(Icons.schedule_rounded, dateRange, isDark),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF6366F1)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallCard(
    double overallPercent,
    int totalAttended,
    int totalLectures,
    bool isSafe,
    Map<String, dynamic> insight,
    bool isDark,
  ) {
    final statusColor = overallPercent >= overallTarget
        ? Colors.green
        : overallPercent >= (overallTarget - 10)
            ? Colors.orange
            : Colors.red;

    final statusIcon = overallPercent >= overallTarget
        ? Icons.check_circle_rounded
        : overallPercent >= (overallTarget - 10)
            ? Icons.warning_rounded
            : Icons.error_rounded;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Attendance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${overallPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Target: ${overallTarget.toStringAsFixed(0)}%  •  $totalAttended/$totalLectures',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 70,
                      width: 70,
                      child: CircularProgressIndicator(
                        value: overallPercent / 100,
                        backgroundColor: isDark ? Colors.white10 : Colors.black12,
                        color: statusColor,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Icon(statusIcon, color: statusColor, size: 34),
                  ],
                ),
              ],
            ),
          ),
          if (totalLectures > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: insight['isSafe']
                    ? Colors.green.withAlpha(isDark ? 38 : 25)
                    : Colors.red.withAlpha(isDark ? 38 : 25),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    insight['isSafe'] ? Icons.lightbulb_outline : Icons.warning_amber_rounded,
                    size: 18,
                    color: insight['isSafe']
                        ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
                        : (isDark ? Colors.red.shade400 : Colors.red.shade700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      insight['text'],
                      style: TextStyle(
                        color: insight['isSafe']
                            ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                            : (isDark ? Colors.red.shade300 : Colors.red.shade800),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(
    Subject subject,
    double percent,
    int attended,
    int total,
    bool isDark,
  ) {
    final statusColor = percent >= subjectTarget
        ? Colors.green
        : percent >= (subjectTarget - 10)
            ? Colors.orange
            : Colors.red;

    final insight = _getPredictiveInsight(attended, total, subjectTarget);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        subject.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : percent / 100,
                    color: statusColor,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$attended/$total lectures',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      percent >= subjectTarget ? 'Safe' : 'Risk',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (total > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: insight['isSafe']
                    ? Colors.green.withAlpha(isDark ? 38 : 25)
                    : Colors.red.withAlpha(isDark ? 38 : 25),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    insight['isSafe'] ? Icons.lightbulb_outline : Icons.warning_amber_rounded,
                    size: 14,
                    color: insight['isSafe']
                        ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
                        : (isDark ? Colors.red.shade400 : Colors.red.shade700),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      insight['text'],
                      style: TextStyle(
                        color: insight['isSafe']
                            ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                            : (isDark ? Colors.red.shade300 : Colors.red.shade800),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptySubjects(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'No subjects could be extracted from this report.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDark
              ? Colors.white.withOpacity(0.4)
              : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
