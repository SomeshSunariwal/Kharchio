import 'package:flutter/services.dart';

abstract interface class LocalSharePlatform {
  Stream<Map<String, dynamic>> get events;
  Future<dynamic> invoke(String method, [Map<String, dynamic>? arguments]);
}

class AndroidLocalSharePlatform implements LocalSharePlatform {
  static const channel = MethodChannel('com.expense.kharchio/local_share');
  static const eventChannel = EventChannel(
    'com.expense.kharchio/local_share/events',
  );
  @override
  Stream<Map<String, dynamic>> get events => eventChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic>? arguments]) =>
      channel.invokeMethod(method, arguments);
}
