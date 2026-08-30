import 'package:actibind/features/activities/services/activity_service.dart';
import 'package:actibind/features/routines/services/routine_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract final class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _syncing = false;
  static bool _canScheduleExactly = false;
  static int _scheduledReminderCount = 0;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'schedule_reminders_v3',
      'Activity and routine reminders',
      channelDescription: 'Upcoming and finished activities and routines',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      onlyAlertOnce: false,
      ticker: 'ActiBind schedule reminder',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static const _breakDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'wellbeing_break_reminders_v1',
      'Wellbeing break reminders',
      channelDescription: 'Reminders to take a break after extended app use',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ticker: 'ActiBind break reminder',
    ),
  );

  static bool get _supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  static Future<void> initialize() async {
    if (_initialized || !_supported) return;
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'schedule_reminders_v3',
          'Activity and routine reminders',
          description: 'Upcoming and finished activities and routines',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'wellbeing_break_reminders_v1',
          'Wellbeing break reminders',
          description: 'Reminders to take a break after extended app use',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
    _initialized = true;
  }

  static Future<void> requestPermissionAndSync() async {
    if (!_supported) return;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsEnabled =
          await android?.areNotificationsEnabled() ?? false;
      if (!notificationsEnabled) {
        await android?.requestNotificationsPermission();
      }
      _canScheduleExactly =
          await android?.canScheduleExactNotifications() ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    await syncSchedule();
  }

  static Future<void> syncSchedule() async {
    if (!_supported || _syncing) return;
    _syncing = true;
    try {
      await initialize();
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android reminders are delivered by FCM so aggressive OEM process
        // management cannot defer them. Remove legacy local alarms to avoid
        // duplicate notifications after push delivery succeeds.
        await _plugin.cancelAllPendingNotifications();
        return;
      }
      final now = DateTime.now();
      final through = now.add(const Duration(days: 30));
      final activities = await ActivityService.getActivities(
        from: now.subtract(const Duration(hours: 1)),
        to: through,
      );
      final routines = await RoutineService.getRoutines(forceRefresh: true);

      await _plugin.cancelAllPendingNotifications();
      _scheduledReminderCount = 0;
      var id = 10000 + now.millisecondsSinceEpoch.remainder(1000000000);

      for (final activity in activities) {
        if (activity.startsAt.isAfter(now)) {
          id = await _schedulePair(
            id: id,
            name: activity.name,
            kind: 'Activity',
            startsAt: activity.startsAt,
            endsAt: activity.endsAt,
            reminderMinutes: activity.reminderMinutes,
          );
        }
      }

      final dates = [
        for (var offset = 0; offset < 7; offset++)
          DateTime(now.year, now.month, now.day + offset),
      ];
      final occurrenceResults = await Future.wait(
        dates.map(RoutineService.getOccurrences),
      );
      for (var dayIndex = 0; dayIndex < dates.length; dayIndex++) {
        final date = dates[dayIndex];
        final occurrences = occurrenceResults[dayIndex];
        for (final routine in routines.where((item) => item.occursOn(date))) {
          final status = occurrences[routine.id]?.status ?? 'scheduled';
          if (status != 'scheduled') continue;
          final startsAt = routine.startsAt(date);
          final endsAt = routine.endsAt(date);
          if (endsAt.isAfter(now)) {
            id = await _schedulePair(
              id: id,
              name: routine.name,
              kind: 'Routine',
              startsAt: startsAt,
              endsAt: endsAt,
              reminderMinutes: routine.reminderMinutes,
            );
          }
        }
      }
    } catch (error) {
      debugPrint('Could not synchronize notifications: $error');
    } finally {
      _syncing = false;
    }
  }

  static Future<void> showPush({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  static Future<void> showBreakReminder({
    required int id,
    required String appName,
    required Duration usage,
    required int milestoneHours,
  }) async {
    if (!_supported) return;
    await initialize();
    final hours = usage.inMinutes / 60;
    final formattedHours = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    await _plugin.show(
      id: id,
      title: '$milestoneHours-hour app milestone',
      body:
          'Phone activity: You have used $appName for $formattedHours hours today. '
          'Rest your eyes, stretch, and come back when you are ready.',
      notificationDetails: _breakDetails,
    );
  }

  static Future<int> _schedulePair({
    required int id,
    required String name,
    required String kind,
    required DateTime startsAt,
    required DateTime endsAt,
    required int reminderMinutes,
  }) async {
    final now = DateTime.now();
    final reminderAt = startsAt.subtract(Duration(minutes: reminderMinutes));
    if (reminderMinutes > 0 && reminderAt.isAfter(now)) {
      await _schedule(
        id++,
        reminderAt,
        '$kind starting soon',
        '$name starts in $reminderMinutes minutes.',
      );
    }
    if (startsAt.isAfter(now)) {
      await _schedule(
        id++,
        startsAt,
        '$kind started',
        '$name is starting now.',
      );
    }
    if (endsAt.isAfter(now)) {
      await _schedule(
        id++,
        endsAt,
        '$kind time is over',
        '$name has reached its scheduled end time.',
      );
    }
    return id;
  }

  static Future<void> _schedule(
    int id,
    DateTime at,
    String title,
    String body,
  ) async {
    // Keep below iOS's pending-notification ceiling with room for system use.
    if (_scheduledReminderCount >= 60) return;
    _scheduledReminderCount++;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: _canScheduleExactly
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
