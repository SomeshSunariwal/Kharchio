import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preview_data.dart';
import '../../core/categories.dart';
import '../../core/preferences.dart';
import 'spending_widget_updates.dart';

/// The popup uses another Flutter engine/SQLite connection. Refresh on resume
/// because Drift notifications are scoped to the connection that made a write.
class WidgetDataRefreshHost extends ConsumerStatefulWidget {
  final Widget child;
  const WidgetDataRefreshHost({super.key, required this.child});
  @override
  ConsumerState<WidgetDataRefreshHost> createState() =>
      _WidgetDataRefreshHostState();
}

class _WidgetDataRefreshHostState extends ConsumerState<WidgetDataRefreshHost>
    with WidgetsBindingObserver {
  Timer? refreshTimer;
  void _queueWidgetRefresh() {
    refreshTimer?.cancel();
    refreshTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) unawaited(SpendingWidgetUpdates.refresh());
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueWidgetRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(expensesProvider.notifier).refresh();
    } catch (e) {
      if (kDebugMode) debugPrint('Widget expense refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expensesProvider, (_, _) => _queueWidgetRefresh());
    ref.listen(categoriesProvider, (_, _) => _queueWidgetRefresh());
    ref.listen(
      preferencesProvider.select((p) => p.currency),
      (_, _) => _queueWidgetRefresh(),
    );
    return widget.child;
  }
}
