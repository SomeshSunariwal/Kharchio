import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool filledAction = false,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) {
          void confirm() => Navigator.pop(context, true);
          final style = TextButton.styleFrom(
            backgroundColor: red,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          );
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (filledAction)
                FilledButton(
                  style: style,
                  onPressed: confirm,
                  child: Text(confirmLabel),
                )
              else
                TextButton(
                  style: style,
                  onPressed: confirm,
                  child: Text(confirmLabel),
                ),
            ],
          );
        },
      ) ==
      true;
}
