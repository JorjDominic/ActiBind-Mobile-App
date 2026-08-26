import 'package:actibind/features/devices/services/app_name_service.dart';

class DeviceAppActivity {
  const DeviceAppActivity({
    required this.id,
    required this.deviceId,
    required this.usageDate,
    required this.appName,
    required this.packageName,
    required this.windowTitle,
    required this.deviceTimezone,
    required this.totalSeconds,
    required this.lastSyncedAt,
  });

  final String id;
  final String deviceId;
  final DateTime usageDate;
  final String appName;
  final String packageName;
  final String windowTitle;
  final String deviceTimezone;
  final int totalSeconds;
  final DateTime lastSyncedAt;

  factory DeviceAppActivity.fromJson(Map<String, dynamic> json) {
    final seconds = json['total_seconds'];
    return DeviceAppActivity(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      usageDate: DateTime.parse(json['usage_date'] as String),
      appName: AppNameService.officialName(
        json['app_name'] as String,
        json['package_name'] as String? ?? '',
      ),
      packageName: (json['package_name'] as String? ?? '').trim(),
      windowTitle: (json['window_title'] as String? ?? '').trim(),
      deviceTimezone: (json['device_timezone'] as String? ?? '').trim(),
      totalSeconds: seconds is int ? seconds : int.parse(seconds.toString()),
      lastSyncedAt: DateTime.parse(json['last_synced_at'] as String).toLocal(),
    );
  }
}
