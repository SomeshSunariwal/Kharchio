import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'widgets.dart' show SurfaceCard;

Future<bool> showAppConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  bool destructive = false,
}) async {
  final accent = destructive ? red : green;
  return await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .16),
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 420),
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: accent, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              namesRoute: true,
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              message,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.appColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: destructive ? red : null,
                          foregroundColor: destructive ? Colors.white : null,
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ==
      true;
}
