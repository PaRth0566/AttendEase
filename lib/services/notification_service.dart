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

  static const String _channelId = 'attend_ease_master_urgent_v2';

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await _notificationsPlugin.initialize(initSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      'Critical Attendance Alerts',
      description: 'Urgent pop-up reminders for your attendance',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

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

  Future<void> scheduleSmartNotifications() async {
    await _notificationsPlugin.cancelAll();

    final prefs = await SharedPreferences.getInstance();
    final sem = prefs.getInt('semester') ?? 1;
    final overallTarget =
        prefs.getDouble('overall_required_attendance') ?? 75.0;

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    // ==========================================
    // 🔔 1. THE 8:00 PM REMINDER
    // ==========================================
    if (now.weekday <= 6) {
      final todayLectures = await _timetableDao.getEntriesForDay(
        now.weekday,
        sem,
      );
      if (todayLectures.isNotEmpty) {
        final markedAttendance = await _attendanceDao.getAttendanceForDate(
          todayKey,
        );

        if (markedAttendance.length < todayLectures.length && now.hour < 20) {
          final scheduleTime = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            20,
            0,
          );
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
    // 🚨 2. THE 10:30 PM RISK WARNING
    // ==========================================
    final tomorrow = now.add(const Duration(days: 1));

    if (tomorrow.weekday <= 6 &&
        (now.hour < 22 || (now.hour == 22 && now.minute < 30))) {
      final tomorrowLectures = await _timetableDao.getEntriesForDay(
        tomorrow.weekday,
        sem,
      );

      if (tomorrowLectures.isNotEmpty) {
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
        );

        if (overallPercent < overallTarget && totalL > 0) {
          await _scheduleAlarm(
            id: 2,
            title: 'Danger Zone 🚨',
            body:
                'Your overall attendance is ${overallPercent.toStringAsFixed(1)}%. You MUST attend tomorrow\'s classes to recover!',
            scheduledTime: scheduleTime,
          );
          return;
        }

        List<String> atRiskSubjectNames = [];
        for (final lecture in tomorrowLectures) {
          final subject = subjects.firstWhere((s) => s.id == lecture.subjectId);
          final subStat = stats[subject.id] ?? {'attended': 0, 'total': 0};
          double subPercent = subStat['total'] == 0
              ? 100.0
              : (subStat['attended']! / subStat['total']!) * 100;

          if (subPercent < subject.requiredPercent && subStat['total']! > 0) {
            if (!atRiskSubjectNames.contains(subject.name)) {
              atRiskSubjectNames.add(subject.name);
            }
          }
        }

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
      _channelId,
      'Critical Attendance Alerts',
      channelDescription: 'Urgent pop-up reminders for your attendance',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.reminder,
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
