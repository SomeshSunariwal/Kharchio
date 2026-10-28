import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'widget_capture_lifecycle.dart';

const homeWidgetChannel = MethodChannel('com.expense.kharchio/home_widgets');

String? widgetActionRoute(Object? value) {
  if (value is! Map ||
      value['id'] is! String ||
      (value['id'] as String).isEmpty) {
    return null;
  }
  return switch (value['action']) {
    'add' => '/widgets/add',
    'record' => '/widgets/record',
    _ => null,
  };
}

/// Registers once under MaterialApp. Dispatches after routing is ready and never
/// stacks two widget capture flows (or two microphones) on repeated taps.
class HomeWidgetActionHost extends StatefulWidget {
  final GoRouter router;
  final Widget child;
  const HomeWidgetActionHost({
    super.key,
    required this.router,
    required this.child,
  });
  @override
  State<HomeWidgetActionHost> createState() => _HomeWidgetActionHostState();
}

class _HomeWidgetActionHostState extends State<HomeWidgetActionHost> {
  final seen = <String>{};
  bool scheduled = false;
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      homeWidgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'launchAction') _launch(call.arguments);
      });
      unawaited(_consume());
    }
  }

  Future<void> _consume() async {
    try {
      _launch(
        await homeWidgetChannel.invokeMethod<Object?>('consumeLaunchAction'),
      );
    } on MissingPluginException {
      // Non-Android previews and widget tests have no native widget host.
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Home widget launch failed: ${e.code}');
    }
  }

  void _launch(Object? value) {
    if (!mounted) return;
    final route = widgetActionRoute(value);
    if (route == null) return;
    final id = (value as Map)['id'] as String;
    if (!seen.add(id) || scheduled) return;
    if (seen.length > 32) seen.remove(seen.first);
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      final configuration = widget.router.routerDelegate.currentConfiguration;
      if (configuration.matches.isNotEmpty &&
          configuration.last.matchedLocation.startsWith('/widgets/')) {
        if (!HomeWidgetCapture.isActive) {
          unawaited(widget.router.pushReplacement<void>(route));
        }
        return;
      }
      unawaited(widget.router.push<void>(route));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      homeWidgetChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
