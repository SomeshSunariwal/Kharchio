import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _networkEvents = EventChannel('com.somesh.kharchio/network');

final networkConnectivityProvider = StreamProvider<bool>((ref) {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return Stream.value(false);
  }
  return _networkEvents.receiveBroadcastStream().cast<bool>().distinct();
});
