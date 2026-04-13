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
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.65)
                    : const Color(0xFF475569),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B), const Color(0xFF1E293B)]
              : [const Color(0xFF6366F1), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall Attendance',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${overallPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$totalAttended of $totalLectures lectures  •  Target: ${overallTarget.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: overallPercent / 100,
                            backgroundColor: Colors.white.withOpacity(0.15),
                            color: Colors.white,
                            strokeWidth: 7,
                            strokeCap: StrokeCap.round,
                          ),
                          Icon(
                            isSafe
                                ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        insight['isSafe']
                            ? Icons.lightbulb_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          insight['text'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
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
    final bool safe = percent >= subjectTarget;
    final bool warning =
        !safe && percent >= (subjectTarget - 10);

    final Color accentColor = safe
        ? const Color(0xFF10B981)
        : warning
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    final insight =
        _getPredictiveInsight(attended, total, subjectTarget);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : percent / 100,
                          color: accentColor,
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.1)
                              : const Color(0xFFF1F5F9),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$attended / $total lectures',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withOpacity(0.45)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            '${percent.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    safe ? 'Safe' : warning ? 'Caution' : 'Risk',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (total > 0)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(isDark ? 0.08 : 0.06),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    insight['isSafe']
                        ? Icons.lightbulb_outline_rounded
                        : Icons.warning_amber_rounded,
                    size: 13,
                    color: accentColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      insight['text'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
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
