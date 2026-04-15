import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/attendance_dao.dart';
import '../../models/subject.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;

  const SubjectDetailScreen({super.key, required this.subject});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final AttendanceDao _attendanceDao = AttendanceDao();

  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  int _attended = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (widget.subject.id == null) return;

    final records = await _attendanceDao.getAttendanceHistoryForSubject(
      widget.subject.id!,
    );

    int attendedCount = 0;
    for (var record in records) {
      if (record['status'] == 'P') {
        attendedCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _history = records;
      _total = records.length;
      _attended = attendedCount;
      _isLoading = false;
    });
  }

  // ✅ NEW: Delete Record Logic
  Future<void> _deleteRecord(int timetableId, String date) async {
    await _attendanceDao.deleteAttendance(timetableId, date);
    _loadHistory(); // Refresh the UI

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attendance record deleted')));
  }

  // ✅ NEW: Toggle Record Logic (P -> A, or A -> P)
  Future<void> _toggleStatus(
    int timetableId,
    String date,
    String currentStatus,
  ) async {
    String newStatus = currentStatus == 'P' ? 'A' : 'P';

    await _attendanceDao.upsertAttendance(
      timetableId: timetableId,
      date: date,
      status: newStatus,
    );

    _loadHistory(); // Refresh the UI
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final percent = _total == 0 ? 0.0 : (_attended / _total) * 100;
    final isSafe = percent >= widget.subject.requiredPercent;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
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
          : Column(
              children: [
                // OVERALL STATS CARD
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.primary.withAlpha(25)
                          : const Color(0xFFF2F4FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.primary.withAlpha(76),
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
                            color: isSafe ? Colors.green : Colors.red,
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
                        LinearProgressIndicator(
                          value: _total == 0 ? 0 : percent / 100,
                          color: isSafe ? Colors.green : Colors.red,
                          backgroundColor: theme.dividerColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(10),
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
                          color: Colors.grey.shade500,
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
                            final colorBg = isPresent
                                ? (isDark
                                      ? Colors.green.shade400.withAlpha(64)
                                      : Colors.green.withAlpha(64))
                                : (isDark
                                      ? Colors.red.shade400.withAlpha(64)
                                      : Colors.red.withAlpha(64));
                            final colorIcon = isPresent
                                ? (isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade700)
                                : (isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade700);

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
                                return await showDialog(
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
                                        isPresent
                                            ? Icons.check_rounded
                                            : Icons.close_rounded,
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
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          isPresent ? 'Present' : 'Absent',
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
    );
  }
}
