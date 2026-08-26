import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/services/app_break_reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects apps used for two hours or more', () {
    final now = DateTime.now();
    final usage = [
      AppUsage(
        packageName: 'below.limit',
        appName: 'Below',
        foreground: const Duration(hours: 1, minutes: 59),
        lastTimeUsed: now,
      ),
      AppUsage(
        packageName: 'at.limit',
        appName: 'At limit',
        foreground: const Duration(hours: 2),
        lastTimeUsed: now,
      ),
      AppUsage(
        packageName: 'over.limit',
        appName: 'Over limit',
        foreground: const Duration(hours: 4),
        lastTimeUsed: now,
      ),
    ];

    expect(
      AppBreakReminderService.appsOverThreshold(
        usage,
      ).map((app) => app.packageName),
      ['at.limit', 'over.limit'],
    );
  });
}
