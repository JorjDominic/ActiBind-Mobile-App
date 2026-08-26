import 'package:actibind/core/services/supabase_service.dart';
import 'package:actibind/features/notifications/models/app_notification.dart';

abstract final class AppNotificationService {
  static Future<List<AppNotification>> getRecent({int limit = 30}) async {
    final rows = await SupabaseService.client
        .from('app_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromJson).toList(growable: false);
  }

  static Future<void> markAllRead() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    await SupabaseService.client
        .from('app_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', user.id)
        .isFilter('read_at', null);
  }
}
