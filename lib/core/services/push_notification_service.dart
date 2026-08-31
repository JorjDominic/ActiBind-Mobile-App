import 'dart:async';

import 'package:actibind/core/services/notification_service.dart';
import 'package:actibind/core/services/supabase_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class PushNotificationService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static bool _initialized = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!_supported || _initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;
    // FCM messages reference our Android channels. Create them before a push can
    // arrive so delivery does not fall back to Firebase's generic channel.
    await NotificationService.initialize();
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    _tokenSubscription = messaging.onTokenRefresh.listen(_saveToken);
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
      (_) => registerCurrentDevice(),
    );
    _messageSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundMessage,
    );
    await registerCurrentDevice();
  }

  static Future<void> registerCurrentDevice() async {
    if (!_supported) return;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(token);
    } catch (error) {
      debugPrint('Could not register push notification device: $error');
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    var timezone = 'UTC';
    try {
      timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {}
    try {
      await SupabaseService.client.from('device_push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': 'android',
        'timezone': timezone,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (error) {
      debugPrint('Could not save push notification token: $error');
    }
  }

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    await _showDataMessage(message);
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    // Android displays notification payloads itself while the app is closed.
    if (message.notification != null) return;
    await _showDataMessage(message);
  }

  static Future<void> _showDataMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null || body == null) return;
    await NotificationService.initialize();
    await NotificationService.showPush(
      id:
          message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(1000000000),
      title: title,
      body: body,
      isBreakReminder: message.data['type'] == 'pc-break',
    );
  }

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    await _messageSubscription?.cancel();
    _initialized = false;
  }
}
