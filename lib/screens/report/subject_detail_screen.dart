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
                // ✅ OVERALL STATS CARD
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

                // ✅ TIMELINE HEADER
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Attendance History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ),

                // ✅ TIMELINE LIST
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

                            DateTime date = DateTime.parse(dateStr);
                            String formattedDate = DateFormat(
                              'EEEE, MMM d, yyyy',
                            ).format(date);

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

                            return Card(
                              color: theme.cardColor,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: theme.dividerColor),
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
                                trailing: Text(
                                  isPresent ? 'Present' : 'Absent',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorIcon,
                                    fontSize: 14,
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
