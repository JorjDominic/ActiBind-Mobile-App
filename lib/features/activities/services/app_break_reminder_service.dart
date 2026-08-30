import 'package:actibind/core/services/notification_service.dart';
import 'package:actibind/core/settings/notification_preferences_controller.dart';
import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppBreakReminderService {
  static const threshold = Duration(hours: 2);
  static const _preferencePrefix = 'app_break_reminder';
  static bool _checking = false;

  static List<AppUsage> appsOverThreshold(
    Iterable<AppUsage> usage, {
    Duration limit = threshold,
  }) => usage.where((app) => app.foreground >= limit).toList(growable: false);

  static int? milestoneFor(Duration usage) {
    final hours = usage.inHours;
    if (hours < 2) return null;
    return hours.clamp(2, 8);
  }

  static Future<void> checkNow() async {
    if (_checking || !UsageStatsService.isSupported) return;
    final notificationPrefs = NotificationPreferencesController.instance;
    if (!notificationPrefs.phoneBreaks || _isQuietTime(notificationPrefs)) {
      return;
    }
    _checking = true;
    try {
      if (!await UsageStatsService.hasPermission()) return;

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final usage = await UsageStatsService.getUsage(
        start: start,
        end: now,
        forceRefresh: true,
      );
      final preferences = await SharedPreferences.getInstance();
      final day = _dayKey(now);

      for (final app in appsOverThreshold(usage)) {
        final milestone = milestoneFor(app.foreground);
        if (milestone == null) continue;
        final key = '$_preferencePrefix.$day.${app.packageName}.${milestone}h';
        if (preferences.getBool(key) == true) continue;

        await NotificationService.showBreakReminder(
          id: _notificationId(day, app.packageName, milestone),
          appName: app.appName,
          usage: app.foreground,
          milestoneHours: milestone,
        );
        await preferences.setBool(key, true);
      }

      await _removeOldKeys(preferences, keepDay: day);
    } catch (error) {
      debugPrint('Could not check app break reminders: $error');
    } finally {
      _checking = false;
    }
  }

  static bool _isQuietTime(NotificationPreferencesController prefs) {
    if (!prefs.quietHours) return false;
    final hour = DateTime.now().hour;
    return prefs.quietStartHour > prefs.quietEndHour
        ? hour >= prefs.quietStartHour || hour < prefs.quietEndHour
        : hour >= prefs.quietStartHour && hour < prefs.quietEndHour;
  }

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static int _notificationId(String day, String packageName, int milestone) =>
      300000000 +
      Object.hash(day, packageName, milestone).abs().remainder(600000000);

  static Future<void> _removeOldKeys(
    SharedPreferences preferences, {
    required String keepDay,
  }) async {
    final currentPrefix = '$_preferencePrefix.$keepDay.';
    final staleKeys = preferences
        .getKeys()
        .where(
          (key) =>
              key.startsWith('$_preferencePrefix.') &&
              !key.startsWith(currentPrefix),
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      await preferences.remove(key);
    }
  }
}
