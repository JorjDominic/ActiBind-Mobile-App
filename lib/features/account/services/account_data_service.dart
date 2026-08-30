import 'dart:convert';

import 'package:actibind/core/services/supabase_service.dart';
import 'package:flutter/services.dart';

abstract final class AccountDataService {
  static const _tables = [
    'activities',
    'routines',
    'routine_occurrences',
    'todos',
    'notes',
    'registered_devices',
    'device_app_activity',
    'device_app_window_activity',
    'app_notifications',
  ];

  static Future<int> copyExportToClipboard() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) throw StateError('Sign in before exporting data.');
    final export = <String, Object?>{
      'format': 'ActiBind account export',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'user': {'id': user.id, 'email': user.email},
    };
    var recordCount = 0;
    for (final table in _tables) {
      try {
        final rows = await SupabaseService.client.from(table).select();
        export[table] = rows;
        recordCount += rows.length;
      } catch (error) {
        export[table] = {'unavailable': error.runtimeType.toString()};
      }
    }
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(export)),
    );
    return recordCount;
  }

  static Future<void> deleteAccount() async {
    final response = await SupabaseService.client.functions.invoke(
      'delete-account',
      body: {'confirmation': 'DELETE'},
    );
    if (response.status != 200) {
      throw StateError('Account deletion could not be completed.');
    }
    await SupabaseService.client.auth.signOut();
  }
}
