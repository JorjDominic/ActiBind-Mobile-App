import 'package:actibind/features/activities/models/app_usage.dart';

abstract final class AppBreakReminderService {
  static const threshold = Duration(hours: 2);
  static List<AppUsage> appsOverThreshold(
    Iterable<AppUsage> usage, {
    Duration limit = threshold,
  }) => usage.where((app) => app.foreground >= limit).toList(growable: false);

  static int? milestoneFor(Duration usage) {
    final hours = usage.inHours;
    if (hours < 2) return null;
    return hours.clamp(2, 8);
  }
}
