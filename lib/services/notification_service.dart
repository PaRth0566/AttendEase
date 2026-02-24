import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../database/attendance_dao.dart';
import '../database/subject_dao.dart';
import '../database/timetable_dao.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final AttendanceDao _attendanceDao = AttendanceDao();
  final TimetableDao _timetableDao = TimetableDao();
  final SubjectDao _subjectDao = SubjectDao();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await _notificationsPlugin.initialize(initSettings);

    // Request permission for Android 13+
    _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  // 🔥 THIS FUNCTION DOES THE MAGIC 🔥
  Future<void> scheduleSmartNotifications() async {
    // 1. Cancel any old scheduled notifications so they don't duplicate
    await _notificationsPlugin.cancelAll();

    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;
    final overallTarget =
        prefs.getDouble('overall_required_attendance') ?? 75.0;

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    // ==========================================
    // 🔔 1. THE 8:00 PM REMINDER (UNMARKED TODAY)
    // ==========================================
    if (now.weekday <= 6) {
      // If today is Mon-Sat
      final todayLectures = await _timetableDao.getEntriesForDay(
        now.weekday,
        sem,
      );
      if (todayLectures.isNotEmpty) {
        final markedAttendance = await _attendanceDao.getAttendanceForDate(
          todayKey,
        );

        // If not all lectures are marked, and it's before 8 PM
        if (markedAttendance.length < todayLectures.length && now.hour < 20) {
          final scheduleTime = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            20,
            0,
          ); // 8:00 PM
          await _scheduleAlarm(
            id: 1,
            title: 'Attendance Reminder 📝',
            body:
                'Hey! You have unmarked lectures for today. Tap to log your attendance!',
            scheduledTime: scheduleTime,
          );
        }
      }
    }

    // ==========================================
    // 🚨 2. THE 10:30 PM RISK WARNING (FOR TOMORROW)
    // ==========================================
    final tomorrow = now.add(const Duration(days: 1));

    // Check if tomorrow is Mon-Sat AND it's currently before 10:30 PM
    if (tomorrow.weekday <= 6 &&
        (now.hour < 22 || (now.hour == 22 && now.minute < 30))) {
      final tomorrowLectures = await _timetableDao.getEntriesForDay(
        tomorrow.weekday,
        sem,
      );

      if (tomorrowLectures.isNotEmpty) {
        // Calculate Attendance
        final stats = await _attendanceDao.getAttendanceStats();
        final subjects = await _subjectDao.getSubjectsBySemester(sem);

        int totalA = 0;
        int totalL = 0;
        for (final sub in subjects) {
          totalA += stats[sub.id]?['attended'] ?? 0;
          totalL += stats[sub.id]?['total'] ?? 0;
        }

        double overallPercent = totalL == 0 ? 100.0 : (totalA / totalL) * 100;
        final scheduleTime = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          22,
          30,
        ); // 10:30 PM

        // SCENARIO A: OVERALL IS AT RISK (Highest Priority)
        if (overallPercent < overallTarget && totalL > 0) {
          await _scheduleAlarm(
            id: 2,
            title: 'Danger Zone 🚨',
            body:
                'Your overall attendance is ${overallPercent.toStringAsFixed(1)}%. You MUST attend tomorrow\'s classes to recover!',
            scheduledTime: scheduleTime,
          );
          return; // Stop here, overall warning overrides individual subjects
        }

        // SCENARIO B: COMPILE ALL AT-RISK SUBJECTS FOR TOMORROW
        List<String> atRiskSubjectNames = [];

        for (final lecture in tomorrowLectures) {
          final subject = subjects.firstWhere((s) => s.id == lecture.subjectId);
          final subStat = stats[subject.id] ?? {'attended': 0, 'total': 0};
          double subPercent = subStat['total'] == 0
              ? 100.0
              : (subStat['attended']! / subStat['total']!) * 100;

          // If subject is below target AND not already in our list
          if (subPercent < subject.requiredPercent && subStat['total']! > 0) {
            if (!atRiskSubjectNames.contains(subject.name)) {
              atRiskSubjectNames.add(subject.name);
            }
          }
        }

        // If we found any at-risk subjects for tomorrow, send ONE combined notification
        if (atRiskSubjectNames.isNotEmpty) {
          String combinedNames = atRiskSubjectNames.join(', ');
          await _scheduleAlarm(
            id: 3,
            title: 'Subject Risk ⚠️',
            body:
                'Attendance is low in: $combinedNames. Don\'t miss these tomorrow!',
            scheduledTime: scheduleTime,
          );
        }
      }
    }
  }

  Future<void> _scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'attendance_channel',
      'Attendance Alerts',
      channelDescription: 'Reminders and Risk Alerts for AttendEase',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
