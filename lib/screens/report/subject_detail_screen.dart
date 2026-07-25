import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/attendance_dao.dart';
import '../../models/subject.dart';
import '../../services/cloud_sync_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/calculation_utils.dart';
import '../../widgets/app_overlays.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;

  const SubjectDetailScreen({super.key, required this.subject});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  final AttendanceDao _attendanceDao = AttendanceDao();

  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  int _attended = 0;
  int _total = 0;

  // Skip calculator state
  List<DateTime> _skippableDates = [];
  final Map<DateTime, int> _skippableCounts = {}; // date -> lectures that day
  int _maxSkips = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (widget.subject.id == null) return;

    final records = await _attendanceDao.getAttendanceHistoryForSubject(
      widget.subject.id!,
    );

    int attendedCount = 0;
    int totalCount = 0;
    for (var record in records) {
      final status = record['status'];
      if (status == 'NU') continue; // NU doesn't count in stats
      totalCount++;
      if (status == 'P') {
        attendedCount++;
      }
    }

    // Calculate skippable dates from this subject's own lecture history
    _calculateSkippableDates(records, attendedCount, totalCount);

    if (!mounted) return;
    setState(() {
      _history = records;
      _total = totalCount;
      _attended = attendedCount;
      _isLoading = false;
    });
    _animController.forward(from: 0);
  }

  /// Works out how many upcoming lectures of this subject can be skipped while
  /// staying at or above the required percentage, and — crucially — *which
  /// days* those are. Delegates to [computeSkipPlan], which derives the
  /// recurring weekday pattern from this subject's own attendance history, so
  /// it does not depend on a manually-configured or inferred global timetable.
  void _calculateSkippableDates(
    List<Map<String, dynamic>> records,
    int attended,
    int total,
  ) {
    final plan = computeSkipPlan(
      history: records,
      attended: attended,
      total: total,
      requiredPercent: widget.subject.requiredPercent,
      today: DateTime.now(),
    );
    _maxSkips = plan.maxSkips;
    _skippableDates = plan.dates;
    _skippableCounts
      ..clear()
      ..addAll(plan.countPerDate);
  }

  // ✅ NEW: Delete Record Logic
  Future<void> _deleteRecord(int timetableId, String date) async {
    await _attendanceDao.deleteAttendance(timetableId, date);
    _loadHistory(); // Refresh the UI
    CloudSyncService().backupDataToCloud(); // Auto-sync

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attendance record deleted')));
  }

  // Toggle Record Logic:
  // pdf source:    P → A → P
  // manual source: NU → P → A → NU
  Future<void> _toggleStatus(
    int timetableId,
    String date,
    String currentStatus,
    String source,
  ) async {
    String newStatus;
    if (source == 'manual') {
      if (currentStatus == 'NU') {
        newStatus = 'P';
      } else if (currentStatus == 'P') {
        newStatus = 'A';
      } else {
        newStatus = 'NU';
      }
    } else {
      newStatus = currentStatus == 'P' ? 'A' : 'P';
    }

    await _attendanceDao.upsertAttendance(
      timetableId: timetableId,
      date: date,
      status: newStatus,
      source: 'manual',
    );

    _loadHistory();
    CloudSyncService().backupDataToCloud();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = context.appColors;

    final percent = _total == 0 ? 0.0 : (_attended / _total) * 100;
    final isSafe = percent >= widget.subject.requiredPercent;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        // Deliberately not a Hero. The container transform already carries this
        // title up from the tapped card: it lays the page out full-size and
        // clips it to a rect that grows from the tile, so the AppBar rides
        // along with everything else. A Hero on top of that animated the title
        // a second time, on the route's raw animation under Material's
        // front-loaded fastOutSlowIn rather than the transform's emphasized
        // easing — so it reached the top while the card was still expanding.
        title: Text(
          widget.subject.name,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.iconTheme,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
              children: [
                // OVERALL STATS CARD
                FadeTransition(
                    opacity: _fadeAnim,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.dividerColor,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Current Attendance',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${percent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: isSafe ? c.success : c.danger,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_attended / $_total Lectures Attended',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: _total == 0 ? 0.0 : percent / 100),
                              duration: const Duration(milliseconds: 1200),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) => LinearProgressIndicator(
                                value: value,
                                color: isSafe ? c.success : c.danger,
                                backgroundColor: theme.dividerColor,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Required: ${widget.subject.requiredPercent}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // SKIP CALCULATOR
                if (_maxSkips > 0)
                  FadeTransition(
                      opacity: _fadeAnim,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.green.withAlpha(20)
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? Colors.green.withAlpha(60)
                                  : Colors.green.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.event_available_rounded,
                                    size: 20,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Safe to Skip',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.green.withAlpha(40)
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$_maxSkips lecture${_maxSkips > 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.green.shade200
                                            : Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_skippableDates.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Upcoming lectures you can miss and still stay above ${widget.subject.requiredPercent.toStringAsFixed(0)}%:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: isDark
                                        ? Colors.green.shade400
                                        : Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: _skippableDates.map((date) {
                                    final count = _skippableCounts[date] ?? 1;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.cardColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: theme.dividerColor,
                                        ),
                                      ),
                                      child: Text(
                                        count > 1
                                            ? '${DateFormat('EEE, MMM d').format(date)}  ·  ${count}x'
                                            : DateFormat('EEE, MMM d').format(date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: theme.textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Text(
                                  'You are $_maxSkips lecture${_maxSkips > 1 ? 's' : ''} ahead of target. Specific dates will appear once this subject has a regular weekly pattern in your report.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: isDark
                                        ? Colors.green.shade400
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                // TIMELINE HEADER & UX HINT
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attendance History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      // ✅ Awesome UX Hint for the user
                      Text(
                        'Tap to edit • Swipe to delete',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodyMedium?.color,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

                // TIMELINE LIST
                Expanded(
                  child: _history.isEmpty
                      ? Center(
                          child: Text(
                            'No attendance recorded yet.',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final record = _history[index];
                            final dateStr = record['date'];
                            final status = record['status'];
                            final timetableId = record['timetable_entry_id'];

                            String strippedDateStr = dateStr.contains('_') ? dateStr.split('_')[0] : dateStr;
                            DateTime? parsedDate = DateTime.tryParse(strippedDateStr);
                            String formattedDate = dateStr;
                            if (parsedDate != null) {
                              formattedDate = DateFormat('EEEE, MMM d, yyyy').format(parsedDate);
                            }

                            final isPresent = status == 'P';
                            final isNU = status == 'NU';
                            final isManual = (record['source'] as String?) == 'manual';
                            final Color colorBg;
                            final Color colorIcon;
                            if (isNU) {
                              colorBg = isDark
                                  ? Colors.orange.shade400.withAlpha(48)
                                  : Colors.orange.withAlpha(48);
                              colorIcon = isDark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade700;
                            } else if (isPresent) {
                              colorBg = isDark
                                  ? Colors.green.shade400.withAlpha(64)
                                  : Colors.green.withAlpha(64);
                              colorIcon = isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700;
                            } else {
                              colorBg = isDark
                                  ? Colors.red.shade400.withAlpha(64)
                                  : Colors.red.withAlpha(64);
                              colorIcon = isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700;
                            }

                            // ✅ NEW: Wrapped Card in Dismissible for Swipe-to-Delete
                            return Dismissible(
                              key: Key('${timetableId}_$dateStr'),
                              direction: DismissDirection
                                  .endToStart, // Swipe Left only
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              confirmDismiss: (direction) async {
                                return await showAppDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: theme.cardColor,
                                    title: Text(
                                      'Delete Record?',
                                      style: TextStyle(
                                        color: theme.textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    content: Text(
                                      'Are you sure you want to delete this attendance record?',
                                      style: TextStyle(
                                        color:
                                            theme.textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (direction) {
                                _deleteRecord(timetableId, dateStr);
                              },
                              child: Card(
                                color: theme.cardColor,
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 12),
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.dividerColor),
                                ),
                                // ✅ NEW: Wrapped ListTile in InkWell for Tap-to-Edit
                                child: InkWell(
                                  onTap: () => _toggleStatus(
                                    timetableId,
                                    dateStr,
                                    status,
                                    record['source'] as String? ?? 'pdf',
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colorBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isNU
                                            ? Icons.help_outline_rounded
                                            : (isPresent
                                                ? Icons.check_rounded
                                                : Icons.close_rounded),
                                        color: colorIcon,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      formattedDate,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: theme.textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    subtitle: isNU
                                        ? Text(
                                            'Status not updated in PDF. Tap to set.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade400,
                                            ),
                                          )
                                        : isManual
                                            ? Text(
                                                'Manually marked',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: theme.textTheme.bodyMedium?.color?.withAlpha(160),
                                                ),
                                              )
                                            : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isManual)
                                          Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: theme.dividerColor.withAlpha(80),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Manual',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: theme.textTheme.bodyMedium?.color?.withAlpha(160),
                                              ),
                                            ),
                                          ),
                                        Text(
                                          isNU ? 'Not Updated' : (isPresent ? 'Present' : 'Absent'),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: colorIcon,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 16,
                                          color: theme.dividerColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
              ),
            ),
    );
  }
}
