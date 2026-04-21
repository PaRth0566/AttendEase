import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../theme/theme_provider.dart';

class AuraAIDashboard extends StatelessWidget {
  final List<Subject> subjects;
  final Map<int, Map<String, int>> attendanceStats;
  final double overallTarget;
  final double subjectTarget;
  final Map<String, String>? reportMeta;

  const AuraAIDashboard({
    super.key,
    required this.subjects,
    required this.attendanceStats,
    required this.overallTarget,
    required this.subjectTarget,
    this.reportMeta,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    int totalAttended = 0;
    int totalLectures = 0;
    
    for (var stat in attendanceStats.values) {
      totalAttended += stat['attended'] ?? 0;
      totalLectures += stat['total'] ?? 0;
    }
    
    final double overallPercentage = totalLectures == 0 
        ? 0.0 
        : (totalAttended / totalLectures) * 100;

    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 24 : 48,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Student Overview',
                style: TextStyle(
                  fontSize: isMobile ? 24 : 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Real-time attendance analytics and predictive tracking for the current semester.',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 32),

              // Main Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  if (w < 1024) {
                     return Column(
                       crossAxisAlignment: CrossAxisAlignment.stretch,
                       children: [
                         _buildLeftColumn(context, isDark, totalAttended, totalLectures, overallPercentage),
                         const SizedBox(height: 32),
                         _buildRightColumn(context, isDark),
                       ],
                     );
                  }
                  
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildLeftColumn(context, isDark, totalAttended, totalLectures, overallPercentage),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        flex: 8,
                        child: _buildRightColumn(context, isDark),
                      ),
                    ],
                  );
                }
              ),
              const SizedBox(height: 48),
              _buildDisclaimer(isDark, isMobile),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftColumn(BuildContext context, bool isDark, int totalAttended, int totalLectures, double overallPercentage) {
    final bool isSafe = overallPercentage >= overallTarget;
    final Map<String, dynamic> insight = {
      'isSafe': isSafe,
      'text': isSafe
          ? (() {
              int canSkip = (totalAttended / (overallTarget / 100)).floor() -
                  totalLectures;
              return canSkip > 0
                  ? "You can safely skip $canSkip ${canSkip == 1 ? 'lecture' : 'lectures'}."
                  : "You are on track. Maintain attendance to stay above ${overallTarget.toStringAsFixed(0)}%.";
            })()
          : (() {
              int required = (((overallTarget / 100) * totalLectures -
                          totalAttended) /
                      (1 - (overallTarget / 100)))
                  .ceil();
              return "Attend next $required ${required == 1 ? 'lecture' : 'lectures'} to reach ${overallTarget.toStringAsFixed(0)}% target.";
            })(),
    };

    final w = MediaQuery.of(context).size.width;
    final bool isSmallMobile = w < 600;
    final double cardPadding = isSmallMobile ? 16.0 : 32.0;
    final double circleSize = isSmallMobile ? 160.0 : 192.0;
    final double innerCircleSize = isSmallMobile ? 110.0 : 130.0;

    Color progressColor;
    if (overallPercentage >= overallTarget) {
      progressColor = const Color(0xFF4ADE80); // Green
    } else if (overallPercentage >= overallTarget - 10) {
      progressColor = const Color(0xFFFBBF24); // Amber
    } else {
      progressColor = const Color(0xFFF87171); // Red
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Profile Card
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.2)
                          : const Color(0xFFE2E8F0),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                      blurRadius: isDark ? 24 : 10,
                      offset: const Offset(0, 4),
                    )
                  ]),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(cardPadding),
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
                                      reportMeta?['studentName']?.isNotEmpty ==
                                              true
                                          ? reportMeta!['studentName']!
                                          : 'Julian Drake',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A))),
                                  const SizedBox(height: 4),
                                  Text(
                                      reportMeta?['program']?.isNotEmpty == true
                                          ? reportMeta!['program']!
                                          : 'Computer Science',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 1.2,
                                          color: isDark
                                              ? const Color(0xFFC7D2FE)
                                              : const Color(0xFF4F46E5))),
                                  const SizedBox(height: 2),
                                  Text(
                                      'Semester ${reportMeta?['semester'] ?? '4'} • ${reportMeta?['academicYear'] ?? '2024'}',
                                      style: TextStyle(
                                          fontSize: isSmallMobile ? 11 : 12,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B))),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.access_time_rounded, size: 14, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5)),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${reportMeta?['reportStartDate'] ?? '01 Feb 2026'} → ${reportMeta?['reportEndDate'] ?? '01 Apr 2026'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                        SizedBox(height: isSmallMobile ? 24 : 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Overall Attendance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                                const SizedBox(height: 4),
                                Text(
                                  '${overallPercentage.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: isSmallMobile ? 40 : 48,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    letterSpacing: -1,
                                  )
                                ),
                                const SizedBox(height: 4),
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: progressColor),
                                    children: [
                                      TextSpan(text: 'Target: ${overallTarget.toStringAsFixed(0)}%  •  $totalAttended/$totalLectures'),
                                    ]
                                  )
                                ),
                              ]
                            ),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: CircularProgressIndicator(
                                    value: totalLectures == 0 ? 0 : (totalAttended / totalLectures),
                                    strokeWidth: 8,
                                    strokeCap: StrokeCap.round,
                                    backgroundColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
                                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                                  )
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: progressColor.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    overallPercentage >= overallTarget ? Icons.check_rounded : Icons.warning_amber_rounded,
                                    color: progressColor,
                                    size: 24,
                                  )
                                ),
                              ]
                            )
                          ]
                        ),
                      ],
                    ),
                  ),
                  if (totalLectures > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: insight['isSafe']
                            ? Colors.green.withAlpha(isDark ? 38 : 25)
                            : Colors.red.withAlpha(isDark ? 38 : 25),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            insight['isSafe']
                                ? Icons.lightbulb_outline
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: insight['isSafe']
                                ? (isDark
                                    ? Colors.green.shade400
                                    : Colors.green.shade700)
                                : (isDark
                                    ? Colors.red.shade400
                                    : Colors.red.shade700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              insight['text'],
                              style: TextStyle(
                                color: insight['isSafe']
                                    ? (isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade800)
                                    : (isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade800),
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
            ),
          ),
        ),
         
      ],
    );
  }

  Widget _buildRightColumn(BuildContext context, bool isDark) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(
           'Subject Breakdown',
           style: TextStyle(
             fontSize: isMobile ? 20 : 24,
             fontWeight: FontWeight.w600,
             color: isDark ? Colors.white : const Color(0xFF0F172A),
           ),
         ),
         const SizedBox(height: 16),
         LayoutBuilder(builder: (ctx, constraints) {
           final double cardW = constraints.maxWidth < 600 ? double.infinity : (constraints.maxWidth - 16) / 2;
           return Wrap(
             spacing: 16,
             runSpacing: 16,
             children: subjects.map((subject) {
                return SizedBox(
                  width: cardW,
                  child: _buildSubjectCard(subject, isDark),
                );
             }).toList(),
           );
         }),
       ],
     );
   }

  Widget _buildSubjectCard(Subject subject, bool isDark) {
    final stats = attendanceStats[subject.id];
    final attended = stats?['attended'] ?? 0;
    final total = stats?['total'] ?? 0;
    final double percentNumber = total == 0 ? 0 : (attended / total) * 100;
    
    // Status Logic
    String status = "On Track";
    Color statusColor = const Color(0xFF4ADE80);
    Color statusBg = const Color(0xFF22C55E).withOpacity(0.2);
    IconData statusIcon = Icons.check_circle_outline_rounded;
    String statusMessage = "";
    
    if (total > 0) {
      if (percentNumber >= subjectTarget) {
        int canSkip = (attended / (subjectTarget / 100)).floor() - total;
        if (percentNumber < subjectTarget + 10) {
          status = "At Risk";
          statusColor = const Color(0xFFFBBF24);
          statusBg = const Color(0xFFF59E0B).withOpacity(0.2);
          statusIcon = Icons.warning_amber_rounded;
        }
        if (canSkip > 0) {
           statusMessage = "Safely above target. You can skip $canSkip ${canSkip == 1 ? 'lecture' : 'lectures'}.";
        } else {
           statusMessage = "On target track. Do not skip the next lecture.";
        }
      } else {
        status = "Critical";
        statusColor = const Color(0xFFF87171);
        statusBg = const Color(0xFFEF4444).withOpacity(0.2);
        statusIcon = Icons.error_outline_rounded;
        
        int requiredToAttend = (((subjectTarget / 100) * total - attended) / (1 - (subjectTarget / 100))).ceil();
        if (requiredToAttend > 0) {
           statusMessage = "Critical. Attend next $requiredToAttend ${requiredToAttend == 1 ? 'lecture' : 'lectures'} to reach target.";
        } else {
           statusMessage = "Action required immediately to reach target.";
        }
      }
    } else {
      statusMessage = "No lectures recorded yet.";
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 185),
          decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : const Color(0xFFE2E8F0),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: isDark ? 16 : 8,
                  offset: const Offset(0, 4),
                )
              ]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            subject.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              height: 1.3,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(100),
                            border:
                                Border.all(color: statusColor.withOpacity(0.5)),
                            boxShadow: isDark
                                ? [
                                    BoxShadow(
                                      color: statusColor.withOpacity(0.3),
                                      blurRadius: 15,
                                    )
                                  ]
                                : null,
                          ),
                          child: Text(status.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: statusColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            RichText(
                              text: TextSpan(
                                  text: '$attended / $total ',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A)),
                                  children: [
                                    TextSpan(
                                        text: 'Lectures',
                                        style: TextStyle(
                                            fontWeight: FontWeight.normal,
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B))),
                                  ]),
                            ),
                            Text('${percentNumber.toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    shadows: isDark
                                        ? [
                                            Shadow(
                                                color: statusColor
                                                    .withOpacity(0.5),
                                                blurRadius: 10)
                                          ]
                                        : null)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withOpacity(0.4)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.05)),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: total == 0 ? 0 : percentNumber / 100.0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: isDark
                                    ? [
                                        BoxShadow(
                                            color: statusColor.withOpacity(0.8),
                                            blurRadius: 10)
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (total > 0)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: percentNumber >= subjectTarget
                        ? Colors.green.withAlpha(isDark ? 38 : 25)
                        : Colors.red.withAlpha(isDark ? 38 : 25),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        percentNumber >= subjectTarget
                            ? Icons.lightbulb_outline
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: percentNumber >= subjectTarget
                            ? (isDark
                                ? Colors.green.shade400
                                : Colors.green.shade700)
                            : (isDark
                                ? Colors.red.shade400
                                : Colors.red.shade700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: TextStyle(
                            color: percentNumber >= subjectTarget
                                ? (isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade800)
                                : (isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade800),
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
        ),
      ),
    );
  }

  Widget _buildDisclaimer(bool isDark, bool isMobile) {
    return Container(
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
                fontSize: isMobile ? 12 : 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.red.shade200 : Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
