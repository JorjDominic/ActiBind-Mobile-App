import 'dart:async';

import 'package:actibind/app.dart';
import 'package:actibind/core/config/supabase_config.dart';
import 'package:actibind/core/services/push_notification_service.dart';
import 'package:actibind/core/services/home_widget_service.dart';
import 'package:actibind/core/settings/family_mode_controller.dart';
import 'package:actibind/core/settings/developer_mode_controller.dart';
import 'package:actibind/core/settings/daily_summary_controller.dart';
import 'package:actibind/core/settings/notification_preferences_controller.dart';
import 'package:actibind/core/settings/privacy_controller.dart';
import 'package:actibind/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await PushNotificationService.handleBackgroundMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await FamilyModeController.instance.load();
  await DeveloperModeController.instance.load();
  await DailySummaryController.instance.load();
  await NotificationPreferencesController.instance.load();
  await PrivacyController.instance.load();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(
      // Persisted refresh tokens keep the user signed in between launches,
      // while automatic refresh replaces short-lived access tokens.
      autoRefreshToken: true,
    ),
  );

  await PushNotificationService.initialize();

  runApp(const App());
  unawaited(HomeWidgetService.refreshAll());
}
