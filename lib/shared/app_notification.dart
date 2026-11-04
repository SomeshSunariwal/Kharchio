import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppNotificationHost extends StatefulWidget {
  final Widget child;
  const AppNotificationHost({super.key, required this.child});

  @override
  State<AppNotificationHost> createState() => _AppNotificationHostState();
}

class _AppNotificationHostState extends State<AppNotificationHost>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final slide = Tween(
    begin: const Offset(0, 1.5),
    end: Offset.zero,
  ).animate(curve);
  Timer? timer;
  String? message;
  bool isError = false;
  double? progress;
  int generation = 0;

  void show(String value, bool error, double? fraction) {
    if (!mounted) return;
    final updatingProgress =
        message != null && progress != null && fraction != null;
    timer?.cancel();
    generation++;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    controller.duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    controller.reverseDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    setState(() {
      message = value;
      isError = error;
      progress = fraction;
    });
    controller.forward(from: updatingProgress ? null : 0);
    if (fraction == null || fraction >= 1) {
      timer = Timer(const Duration(seconds: 5), hide);
    }
  }

  Future<void> hide() async {
    final current = generation;
    timer?.cancel();
    try {
      await controller.reverse().orCancel;
      if (mounted && current == generation) setState(() => message = null);
    } on TickerCanceled {
      /* A newer notification replaced this one. */
    }
  }

  void dismiss() {
    timer?.cancel();
    generation++;
    controller.stop();
    setState(() => message = null);
  }

  @override
  void dispose() {
    timer?.cancel();
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _NotificationScope(
    show: show,
    // The host lives inside Scaffold.body, so navigation paints over its slide.
    child: Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (message != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: SlideTransition(
              position: slide,
              child: Dismissible(
                key: ValueKey(generation),
                direction: progress != null && progress! < 1
                    ? DismissDirection.none
                    : DismissDirection.down,
                resizeDuration: null,
                onDismissed: (_) => dismiss(),
                child: Semantics(
                  liveRegion: true,
                  child: AppNotificationCard(
                    message: message!,
                    isError: isError,
                    progress: progress,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _NotificationScope extends InheritedWidget {
  final void Function(String, bool, double?) show;
  const _NotificationScope({required this.show, required super.child});
  @override
  bool updateShouldNotify(_NotificationScope oldWidget) => false;
}

class AppNotificationCard extends StatelessWidget {
  final String message;
  final bool isError;
  final double? progress;
  const AppNotificationCard({
    super.key,
    required this.message,
    this.isError = false,
    this.progress,
  });
  @override
  Widget build(BuildContext context) {
    final tone = isError ? red : green;
    return Material(
      color: Color.alphaBlend(
        tone.withValues(alpha: 0.09),
        context.appColors.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tone.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : progress != null && progress! < 1
                  ? Icons.sync
                  : Icons.check_circle_outline,
              color: tone,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isError ? red : context.appColors.ink,
                          ),
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          '${(progress! * 100).floor()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      semanticsLabel: 'Import progress',
                      semanticsValue: '${(progress! * 100).floor()}%',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showAppNotification(
  BuildContext context,
  String message, {
  bool isError = false,
  double? progress,
}) {
  final host = context.getInheritedWidgetOfExactType<_NotificationScope>();
  if (host != null) {
    host.show(message, isError, progress);
    return;
  }
  // Standalone routes use the same rounded card, without the shell navigation.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        dismissDirection: DismissDirection.down,
        duration: progress != null && progress < 1
            ? const Duration(days: 1)
            : const Duration(seconds: 5),
        content: AppNotificationCard(
          message: message,
          isError: isError,
          progress: progress,
        ),
      ),
    );
}

typedef AppNotificationUpdate = void Function(
  String message, {
  bool isError,
  double? progress,
});

/// Capture the shell messenger so a background import can finish after navigation.
AppNotificationUpdate appNotificationUpdater(BuildContext context) {
  final host = context.getInheritedWidgetOfExactType<_NotificationScope>();
  return (message, {isError = false, progress}) {
    if (host != null) {
      host.show(message, isError, progress);
    } else if (context.mounted) {
      showAppNotification(
        context,
        message,
        isError: isError,
        progress: progress,
      );
    }
  };
}
