import 'package:flutter/services.dart';

/// A small platform bridge backed by SharedPreferences (Java) and UserDefaults.
abstract final class NativeSettings {
  static const _channel = MethodChannel('com.expense.kharchio/settings');

  static Future<void> writeThemeMode(String mode) =>
      _channel.invokeMethod<void>('setThemeMode', {'value': mode});

  static Future<Map<String, String>> readAll() async =>
      await _channel.invokeMapMethod<String, String>('getSettings') ?? {};

  static Future<void> writePreference(String key, String value) => _channel
      .invokeMethod<void>('setPreference', {'key': key, 'value': value});
}
