import 'package:actibind/core/services/supabase_service.dart';
import 'package:actibind/features/devices/models/device_app_activity.dart';
import 'package:actibind/features/devices/models/device_app_window_activity.dart';

class DeviceAppActivityService {
  DeviceAppActivityService._();

  static Future<List<DeviceAppActivity>> getForDevice({
    required String deviceId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (end.isBefore(start)) {
      throw const FormatException('The activity date range is invalid.');
    }
    final from = _date(start);
    final through = _date(end);
    final response = await SupabaseService.client
        .from('device_app_activity')
        .select()
        .eq('device_id', deviceId)
        .gte('usage_date', from)
        .lte('usage_date', through)
        .order('total_seconds', ascending: false);
    return response.map(DeviceAppActivity.fromJson).toList();
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Future<List<DeviceAppWindowActivity>> getWindowBreakdown({
    required String deviceId,
    required DateTime start,
    required DateTime end,
    required String appName,
    required String packageName,
  }) async {
    if (end.isBefore(start)) {
      throw const FormatException('The activity date range is invalid.');
    }
    final response = await SupabaseService.client
        .from('device_app_window_activity')
        .select('window_title,total_seconds')
        .eq('device_id', deviceId)
        .eq('app_name', appName)
        .eq('package_name', packageName)
        .gte('usage_date', _date(start))
        .lte('usage_date', _date(end))
        .order('total_seconds', ascending: false);
    return response.map(DeviceAppWindowActivity.fromJson).toList();
  }

  static Future<List<Map<String, Object?>>> getWindowActivityForDevice({
    required String deviceId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (end.isBefore(start)) {
      throw const FormatException('The activity date range is invalid.');
    }
    final response = await SupabaseService.client
        .from('device_app_window_activity')
        .select(
          'usage_date,app_name,package_name,window_title,total_seconds,'
          'first_used_at,last_used_at,last_synced_at',
        )
        .eq('device_id', deviceId)
        .gte('usage_date', _date(start))
        .lte('usage_date', _date(end))
        .order('total_seconds', ascending: false);
    return response
        .map<Map<String, Object?>>((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}
