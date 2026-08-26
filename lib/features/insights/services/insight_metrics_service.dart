import 'package:actibind/features/activities/models/activity.dart';
import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/services/activity_service.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:actibind/features/insights/models/insight_metrics.dart';
import 'package:actibind/features/devices/services/device_app_activity_service.dart';
import 'package:actibind/features/devices/services/registered_device_service.dart';
import 'package:actibind/features/devices/models/registered_device.dart';
import 'package:intl/intl.dart';

class InsightMetricsService {
  InsightMetricsService._();

  static final _cache = <String, _MetricsCacheEntry>{};
  static final _inFlight = <String, Future<InsightMetrics>>{};
  static const _cacheLifetime = Duration(seconds: 30);

  static Future<InsightMetrics> load({required int days}) async {
    final key = '$days:${ActivityService.cacheRevision}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) < _cacheLifetime) {
      return cached.metrics;
    }
    if (_inFlight[key] != null) return _inFlight[key]!;
    final request = _compute(days: days);
    _inFlight[key] = request;
    try {
      final metrics = await request;
      _cache[key] = _MetricsCacheEntry(
        metrics: metrics,
        loadedAt: DateTime.now(),
      );
      if (_cache.length > 4) _cache.remove(_cache.keys.first);
      return metrics;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<InsightMetrics> _compute({required int days}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(Duration(days: days - 1));
    final results = await Future.wait([
      ActivityService.getActivities(
        from: from,
        to: today.add(const Duration(days: 1)),
      ),
      ActivityService.getActivities(
        from: from.subtract(Duration(days: days)),
        to: from,
      ),
      RegisteredDeviceService.getDevices(),
    ]);
    final activities = results[0] as List<Activity>;
    final previousActivities = results[1] as List<Activity>;
    final devices = results[2] as List<RegisteredDevice>;
    final pcDevices = devices.where((device) => device.isPc == true).toList();

    final pcRows = (await Future.wait(
      pcDevices.map(
        (device) => DeviceAppActivityService.getForDevice(
          deviceId: device.id,
          start: from,
          end: today,
        ),
      ),
    )).expand((rows) => rows).toList();
    final previousPcRows = (await Future.wait(
      pcDevices.map(
        (device) => DeviceAppActivityService.getForDevice(
          deviceId: device.id,
          start: from.subtract(Duration(days: days)),
          end: from.subtract(const Duration(days: 1)),
        ),
      ),
    )).expand((rows) => rows).toList();

    var phoneToday = Duration.zero;
    var phoneUsage = const <AppUsage>[];
    if (UsageStatsService.isSupported) {
      try {
        if (await UsageStatsService.hasPermission()) {
          phoneUsage = await UsageStatsService.getUsage(start: today, end: now);
          phoneToday = phoneUsage.fold<Duration>(
            Duration.zero,
            (total, item) => total + item.foreground,
          );
        }
      } catch (_) {
        // Scheduled activity remains a useful fallback.
      }
    }

    final previousScheduledTotal = previousActivities.fold<Duration>(
      Duration.zero,
      (total, item) => total + item.endsAt.difference(item.startsAt),
    );
    final elapsedDays = now.difference(from).inDays + 1;
    final scheduledToday = _elapsedDuration(
      activities.where((item) => _isToday(item.startsAt, today)),
      now,
    );
    final pcTodaySeconds = pcRows
        .where((row) => _isToday(row.usageDate, today))
        .fold<int>(0, (total, row) => total + row.totalSeconds);
    final pcToday = Duration(seconds: pcTodaySeconds);
    final todayValue = phoneToday + pcToday;

    final weekdayMinutes = List<int>.filled(7, 0);
    final hourlyActivityMinutes = List<int>.filled(24, 0);
    for (final activity in activities) {
      final duration = _effectiveDuration(activity, now);
      weekdayMinutes[activity.startsAt.weekday - 1] += duration.inMinutes;
      hourlyActivityMinutes[activity.startsAt.hour] += duration.inMinutes;
    }
    for (final row in pcRows) {
      weekdayMinutes[row.usageDate.weekday - 1] += row.totalSeconds ~/ 60;
    }
    weekdayMinutes[today.weekday - 1] += phoneToday.inMinutes;
    final maxDay = weekdayMinutes.fold<int>(0, (a, b) => a > b ? a : b);
    final levels = weekdayMinutes
        .map((value) => maxDay == 0 ? 0.08 : (value / maxDay).clamp(.08, 1.0))
        .toList(growable: false);
    final peakMinutes = hourlyActivityMinutes.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
    var peakWindow = 'Not enough scheduled activity yet';
    if (peakMinutes > 0) {
      final peakHour = hourlyActivityMinutes.indexOf(peakMinutes);
      final start = DateTime(2026, 1, 1, peakHour);
      peakWindow =
          '${DateFormat.jm().format(start)}–${DateFormat.jm().format(start.add(const Duration(hours: 1)))}';
    }

    final pcTotal = Duration(
      seconds: pcRows.fold<int>(0, (total, row) => total + row.totalSeconds),
    );
    final previousPcTotal = Duration(
      seconds: previousPcRows.fold<int>(
        0,
        (total, row) => total + row.totalSeconds,
      ),
    );
    final dailyAverage = Duration(
      milliseconds: (pcTotal + phoneToday).inMilliseconds ~/ elapsedDays,
    );
    final previousDailyAverage = Duration(
      milliseconds:
          (previousPcTotal + previousScheduledTotal).inMilliseconds ~/ days,
    );
    final change = previousDailyAverage.inMinutes == 0
        ? null
        : ((dailyAverage.inMinutes - previousDailyAverage.inMinutes) /
                  previousDailyAverage.inMinutes) *
              100;

    final combinedApps = <String, ({int seconds, Set<String> sources})>{};
    for (final item in phoneUsage) {
      final current = combinedApps[item.appName];
      combinedApps[item.appName] = (
        seconds: (current?.seconds ?? 0) + item.foreground.inSeconds,
        sources: {...?current?.sources, 'Phone'},
      );
    }
    for (final row in pcRows) {
      final current = combinedApps[row.appName];
      combinedApps[row.appName] = (
        seconds: (current?.seconds ?? 0) + row.totalSeconds,
        sources: {...?current?.sources, 'PC'},
      );
    }
    final topApps =
        combinedApps.entries
            .map(
              (entry) => InsightAppMetric(
                name: entry.key,
                duration: Duration(seconds: entry.value.seconds),
                source: entry.value.sources.join(' + '),
              ),
            )
            .toList()
          ..sort((a, b) => b.duration.compareTo(a.duration));

    return InsightMetrics(
      todayValue: todayValue,
      todayLabel: 'combined device usage today',
      dailyAverage: dailyAverage,
      previousDailyAverage: previousDailyAverage,
      averageChangePercent: change,
      goalProgress: todayValue.inMinutes == 0
          ? 0
          : (scheduledToday.inMinutes / todayValue.inMinutes).clamp(0, 1),
      dayLevels: levels,
      dayDurations: weekdayMinutes
          .map((minutes) => Duration(minutes: minutes))
          .toList(growable: false),
      peakWindow: peakWindow,
      phoneToday: phoneToday,
      pcToday: pcToday,
      connectedDeviceCount: devices
          .where((device) => device.connected == true)
          .length,
      overLimitAppCount: combinedApps.values
          .where((item) => item.seconds >= const Duration(hours: 2).inSeconds)
          .length,
      topApps: topApps.take(5).toList(growable: false),
    );
  }

  static Duration _elapsedDuration(
    Iterable<Activity> activities,
    DateTime now,
  ) => activities.fold(
    Duration.zero,
    (total, item) => total + _effectiveDuration(item, now),
  );

  static Duration _effectiveDuration(Activity activity, DateTime now) {
    if (!activity.startsAt.isBefore(now)) return Duration.zero;
    final end = activity.endsAt.isBefore(now) ? activity.endsAt : now;
    return end.isAfter(activity.startsAt)
        ? end.difference(activity.startsAt)
        : Duration.zero;
  }

  static bool _isToday(DateTime value, DateTime today) =>
      value.year == today.year &&
      value.month == today.month &&
      value.day == today.day;

  static String formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

class _MetricsCacheEntry {
  const _MetricsCacheEntry({required this.metrics, required this.loadedAt});
  final InsightMetrics metrics;
  final DateTime loadedAt;
}
