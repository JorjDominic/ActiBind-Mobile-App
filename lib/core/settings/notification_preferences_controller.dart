import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:actibind/core/services/supabase_service.dart';

class NotificationPreferencesController extends ChangeNotifier {
  NotificationPreferencesController._();

  static final instance = NotificationPreferencesController._();
  static const _prefix = 'notification_';

  bool activityReminders = true;
  bool routineReminders = true;
  bool phoneBreaks = true;
  bool pcBreaks = true;
  bool dailySummary = true;
  bool quietHours = false;
  int quietStartHour = 22;
  int quietEndHour = 7;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    activityReminders = prefs.getBool('${_prefix}activities') ?? true;
    routineReminders = prefs.getBool('${_prefix}routines') ?? true;
    phoneBreaks = prefs.getBool('${_prefix}phone_breaks') ?? true;
    pcBreaks = prefs.getBool('${_prefix}pc_breaks') ?? true;
    dailySummary = prefs.getBool('${_prefix}daily_summary') ?? true;
    quietHours = prefs.getBool('${_prefix}quiet_hours') ?? false;
    quietStartHour = prefs.getInt('${_prefix}quiet_start') ?? 22;
    quietEndHour = prefs.getInt('${_prefix}quiet_end') ?? 7;
    notifyListeners();
  }

  Future<void> setEnabled(String key, bool value) async {
    switch (key) {
      case 'activities':
        activityReminders = value;
        break;
      case 'routines':
        routineReminders = value;
        break;
      case 'phone_breaks':
        phoneBreaks = value;
        break;
      case 'pc_breaks':
        pcBreaks = value;
        break;
      case 'daily_summary':
        dailySummary = value;
        break;
      case 'quiet_hours':
        quietHours = value;
        break;
      default:
        throw ArgumentError.value(key, 'key');
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', value);
    await _sync();
  }

  Future<void> setQuietHours({required int start, required int end}) async {
    quietStartHour = start;
    quietEndHour = end;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_prefix}quiet_start', start);
    await prefs.setInt('${_prefix}quiet_end', end);
    await _sync();
  }

  Future<void> _sync() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.client.from('notification_preferences').upsert({
        'user_id': user.id,
        'activity_reminders': activityReminders,
        'routine_reminders': routineReminders,
        'phone_breaks': phoneBreaks,
        'pc_breaks': pcBreaks,
        'daily_summary': dailySummary,
        'quiet_hours': quietHours,
        'quiet_start_hour': quietStartHour,
        'quiet_end_hour': quietEndHour,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Local preferences remain authoritative until the migration is deployed.
    }
  }
}
