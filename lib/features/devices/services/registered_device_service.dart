import 'dart:convert';
import 'dart:math';

import 'package:actibind/core/services/supabase_service.dart';
import 'package:actibind/features/devices/models/registered_device.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicePairing {
  const DevicePairing({required this.device, required this.code});

  final RegisteredDevice device;
  final String code;
}

class RegisteredDeviceService {
  RegisteredDeviceService._();

  static SupabaseClient get _supabase => SupabaseService.client;

  static Future<List<RegisteredDevice>> getDevices() async {
    final response = await _supabase
        .from('registered_devices')
        .select()
        .order('created_at');
    return response.map(RegisteredDevice.fromJson).toList();
  }

  static Future<DevicePairing> createDevice({
    required String name,
    required String type,
    required String platform,
  }) async {
    if (type == 'pc') {
      throw const FormatException(
        'Start pairing in the ActiBind PC app, then connect its code here.',
      );
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to register a device.');
    }
    final code = _generatePairingCode();
    final codeHash = sha256.convert(utf8.encode(code)).toString();
    final response = await _supabase
        .from('registered_devices')
        .insert({
          'user_id': user.id,
          'name': name.trim(),
          'device_type': type,
          'platform': platform,
          'connected': false,
          'pairing_code_hash': codeHash,
          'pairing_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
        })
        .select()
        .single();
    return DevicePairing(
      device: RegisteredDevice.fromJson(response),
      code: code,
    );
  }

  static Future<String> connectWithCode(String code) async {
    final normalized = code
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    if (normalized.length != 8) {
      throw const FormatException('Enter the 8-character pairing code.');
    }
    final result = await _supabase.rpc(
      'claim_registered_device',
      params: {
        'p_pairing_code_hash': sha256
            .convert(utf8.encode(normalized))
            .toString(),
      },
    );
    final rows = result as List<dynamic>;
    if (rows.isEmpty) {
      throw const FormatException(
        'The pairing code is invalid or has expired.',
      );
    }
    return (rows.first as Map<String, dynamic>)['device_name'] as String;
  }

  static Future<DevicePairing> renewPairingCode(RegisteredDevice device) async {
    if (device.connected) {
      throw const FormatException('This device is already connected.');
    }
    final code = _generatePairingCode();
    final codeHash = sha256.convert(utf8.encode(code)).toString();
    final response = await _supabase
        .from('registered_devices')
        .update({
          'pairing_code_hash': codeHash,
          'pairing_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', device.id)
        .eq('connected', false)
        .select()
        .single();
    return DevicePairing(
      device: RegisteredDevice.fromJson(response),
      code: code,
    );
  }

  static String _generatePairingCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      8,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static Future<RegisteredDevice> updateDevice({
    required String id,
    required String name,
    required String platform,
  }) async {
    final response = await _supabase
        .from('registered_devices')
        .update({
          'name': name.trim(),
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return RegisteredDevice.fromJson(response);
  }

  static Future<void> revokeDevice(String id) async {
    final result = await _supabase.rpc(
      'revoke_registered_device',
      params: {'p_device_id': id},
    );
    if (result != true) {
      throw StateError('The device could not be disconnected.');
    }
  }

  static Future<void> deleteDevicePermanently(String id) async {
    final result = await _supabase.rpc(
      'delete_registered_device_permanently',
      params: {'p_device_id': id},
    );
    if (result != true) {
      throw StateError('The device could not be deleted.');
    }
  }
}
