import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'widget_action_host.dart';

/// Optional Android refresh hook. A widget refresh failure must not undo a save.
class SpendingWidgetUpdates {
  static Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await homeWidgetChannel.invokeMethod<void>('refreshSpendingWidget');
    } on MissingPluginException {
      // Desktop previews and tests may not have native widgets.
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Spending widget refresh failed: ${e.code}');
    }
  }
}
