import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/preferences.dart';
import '../../core/subscriptions.dart';
import '../../database/subscription_store.dart';
import 'pending_payment_reviews.dart';

const _channel = MethodChannel('com.somesh.kharchio/subscription_reminders');

bool get supportsSubscriptionReminders =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

typedef SubscriptionReminder = ({
  String planId,
  int dueDay,
  DateTime at,
  bool followUp,
  String message,
});

List<SubscriptionReminder> subscriptionReminders(
  SubscriptionState state,
  DateTime now, {
  required int limit,
  bool retainDelayedAlerts = false,
}) {
  final cutoff = retainDelayedAlerts
      ? now.subtract(const Duration(hours: 12))
      : now;
  final reminders = <SubscriptionReminder>[];
  final dueFormat = DateFormat('d MMM');
  for (final plan in state.plans) {
    final days = plan.reminderDays;
    if (!plan.active || days == null) continue;
    final currency = AppCurrency.fromCode(plan.currencyCode);
    final amount = currency.formatChart(plan.minor / 100);
    final first = subscriptionDueOnOrAfter(
      plan,
      shiftSubscriptionDate(cutoff, -2),
    );
    var due = subscriptionDay(first) < plan.anchorDay
        ? subscriptionDate(plan.anchorDay)
        : first;
    for (
      var cycle = 0;
      cycle < 24;
      cycle++, due = subscriptionCycle(plan, due, 1)
    ) {
      final dueDay = subscriptionDay(due);
      if (state.settled(plan.id, dueDay)) continue;
      final dueLabel = dueFormat.format(due);
      for (final followUp in [false, true]) {
        final at = DateTime(
          due.year,
          due.month,
          due.day + (followUp ? 2 : -days),
          plan.reminderMinutes ~/ 60,
          plan.reminderMinutes % 60,
        );
        if (!at.isAfter(cutoff)) continue;
        reminders.add((
          planId: plan.id,
          dueDay: dueDay,
          at: at,
          followUp: followUp,
          message: followUp
              ? '${plan.name} payment due $dueLabel is still unconfirmed.'
              : '${plan.name} renews ${days == 0 ? 'today' : 'on $dueLabel'} for $amount.',
        ));
      }
    }
  }
  reminders.sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(limit).toList();
}

final subscriptionAlertPermissionProvider = FutureProvider<bool>((ref) async {
  if (!supportsSubscriptionReminders) return false;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return await paymentNotificationChannel.invokeMethod<bool>(
          'hasAlertPermission',
        ) ??
        false;
  }
  return await _channel.invokeMethod<bool>('hasPermission') ?? false;
});

Future<void> enableSubscriptionAlerts() async {
  if (!supportsSubscriptionReminders) return;
  if (defaultTargetPlatform == TargetPlatform.android) {
    await paymentNotificationChannel.invokeMethod<void>('enableAlerts');
  } else {
    await _channel.invokeMethod<void>('requestPermission');
  }
}

class SubscriptionReminderHost extends ConsumerStatefulWidget {
  final Widget child;
  final ValueChanged<SubscriptionDue> openRenewal;
  const SubscriptionReminderHost({
    super.key,
    required this.child,
    required this.openRenewal,
  });

  @override
  ConsumerState<SubscriptionReminderHost> createState() =>
      _SubscriptionReminderHostState();
}

class _SubscriptionReminderHostState
    extends ConsumerState<SubscriptionReminderHost> {
  AppLifecycleListener? _lifecycle;
  bool _syncing = false, _dirty = false;

  @override
  void initState() {
    super.initState();
    if (!supportsSubscriptionReminders) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reminderTapped') await _consumeTap();
    });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.invalidate(subscriptionAlertPermissionProvider);
        unawaited(_consumeTap());
        unawaited(_sync());
      },
    );
    ref.listenManual(
      subscriptionsProvider,
      (_, _) => unawaited(_sync()),
      fireImmediately: true,
    );
    ref.listenManual(subscriptionAlertPermissionProvider, (_, permission) {
      if (permission.value == true) unawaited(_sync());
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeTap()),
    );
  }

  Future<void> _consumeTap() async {
    if (!mounted) return;
    try {
      final tap = await _channel.invokeMapMethod<String, Object?>('consumeTap');
      if (!mounted || tap == null) return;
      if (tap case {'planId': final String id, 'dueDay': final int day}) {
        widget.openRenewal((planId: id, dueDay: day));
      }
    } on MissingPluginException {
      // Tests and previews can run without a native notification host.
    } on PlatformException catch (error) {
      debugPrint('Could not open subscription reminder: ${error.code}');
    }
  }

  Future<void> _sync() async {
    _dirty = true;
    if (_syncing) return;
    _syncing = true;
    try {
      while (mounted && _dirty) {
        _dirty = false;
        final state = ref.read(subscriptionsProvider).value;
        if (state == null) continue;
        final reminders = subscriptionReminders(
          state,
          DateTime.now(),
          limit: defaultTargetPlatform == TargetPlatform.iOS ? 60 : 240,
          retainDelayedAlerts: defaultTargetPlatform == TargetPlatform.android,
        );
        await _channel.invokeMethod<void>(
          'replaceReminders',
          jsonEncode([
            for (final reminder in reminders)
              {
                'id':
                    '${reminder.planId}:${reminder.dueDay}:${reminder.followUp ? 'late' : 'before'}',
                'planId': reminder.planId,
                'dueDay': reminder.dueDay,
                'year': reminder.at.year,
                'month': reminder.at.month,
                'day': reminder.at.day,
                'hour': reminder.at.hour,
                'minute': reminder.at.minute,
                'message': reminder.message,
              },
          ]),
        );
      }
    } on MissingPluginException {
      // Tests and previews can run without a native notification host.
    } on PlatformException catch (error) {
      debugPrint('Could not schedule subscription reminders: ${error.code}');
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    if (_lifecycle != null) _channel.setMethodCallHandler(null);
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
