import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/notifications/pending_payment_reviews.dart';
import '../../shared/widgets.dart';

class PaymentNotificationsSection extends StatefulWidget {
  const PaymentNotificationsSection({super.key});

  @override
  State<PaymentNotificationsSection> createState() =>
      _PaymentNotificationsSectionState();
}

class _PaymentNotificationsSectionState
    extends State<PaymentNotificationsSection>
    with WidgetsBindingObserver {
  bool? _hasAccess;
  bool _hasAlerts = false;

  @override
  void initState() {
    super.initState();
    if (!supportsPaymentNotifications) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    if (supportsPaymentNotifications) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final access = await paymentNotificationChannel.invokeMethod<bool>(
        'hasAccess',
      );
      final alerts = await paymentNotificationChannel.invokeMethod<bool>(
        'hasAlertPermission',
      );
      if (mounted) {
        setState(() {
          _hasAccess = access ?? false;
          _hasAlerts = alerts ?? false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _hasAccess = false);
    } on MissingPluginException {
      if (mounted) setState(() => _hasAccess = false);
    }
  }

  Future<void> _open(String method) async {
    try {
      await paymentNotificationChannel.invokeMethod<void>(method);
    } on PlatformException {
      if (mounted) {
        notice(
          context,
          'Could not open Android notification settings.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsPaymentNotifications) return const SizedBox.shrink();
    final divider = Divider(
      height: 1,
      indent: 14,
      endIndent: 14,
      color: context.appColors.line,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Payment notifications',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                _row(
                  Icons.notifications_outlined,
                  _hasAccess == false
                      ? 'Enable notification access'
                      : 'Notification access',
                  switch (_hasAccess) {
                    null => 'Checking Android permissions…',
                    true => 'Enabled. Detects likely payments on this device.',
                    false =>
                      'Allow Kharchio to check notifications from other apps.',
                  },
                  _hasAccess == null ? null : () => _open('openAccessSettings'),
                ),
                if (_hasAccess == true && !_hasAlerts) ...[
                  divider,
                  _row(
                    Icons.notifications_active_outlined,
                    'Allow review alerts',
                    'Get a reminder when Kharchio is in the background.',
                    () => _open('enableAlerts'),
                  ),
                ],
                divider,
                _row(
                  Icons.receipt_long_outlined,
                  'Review detected expenses',
                  'Check and edit drafts before saving.',
                  _hasAccess == null
                      ? null
                      : () => context.push('/payment-reviews'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    IconData icon,
    String title,
    String description,
    VoidCallback? action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    dense: true,
    minTileHeight: settingsRowMinHeight,
    minVerticalPadding: 0,
    minLeadingWidth: 18,
    horizontalTitleGap: 10,
    leading: Icon(icon, size: 20, color: green),
    title: SettingsRowLabel(title, description),
    trailing: action == null ? null : const Icon(Icons.chevron_right, size: 18),
    enabled: action != null,
    onTap: action,
  );
}
