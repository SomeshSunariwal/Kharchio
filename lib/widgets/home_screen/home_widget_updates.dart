import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'widget_action_host.dart';

/// Optional Android refresh hook. A widget refresh failure must not undo a save.
class HomeWidgetUpdates {
  static Future<void> refreshSpending() => _refresh('refreshSpendingWidget');

  static Future<void> refreshSubscriptions() =>
      _refresh('refreshSubscriptionWidget');

  static Future<void> _refresh(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await homeWidgetChannel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop previews and tests may not have native widgets.
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Home widget refresh failed ($method): ${e.code}');
      }
    }
  }
}
