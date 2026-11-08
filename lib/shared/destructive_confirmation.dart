import 'package:flutter/material.dart';

import 'app_confirmation.dart';

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) => showAppConfirmation(
  context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  icon: Icons.delete_outline,
  destructive: true,
);
