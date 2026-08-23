import 'package:actibind/features/devices/models/device_app_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parses bigint-compatible activity and normalizes nullable metadata',
    () {
      final activity = DeviceAppActivity.fromJson({
        'id': 'activity-id',
        'device_id': 'device-id',
        'usage_date': '2026-08-23',
        'app_name': ' Chrome ',
        'package_name': null,
        'window_title': null,
        'device_timezone': null,
        'total_seconds': '3720',
        'last_synced_at': '2026-08-23T12:00:00Z',
      });

      expect(activity.appName, 'Chrome');
      expect(activity.packageName, isEmpty);
      expect(activity.windowTitle, isEmpty);
      expect(activity.totalSeconds, 3720);
    },
  );
}
