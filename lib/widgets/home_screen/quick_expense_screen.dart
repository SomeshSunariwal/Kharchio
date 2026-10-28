import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/expense.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../database/local_store.dart';
import '../../features/expenses/add_expense_screen.dart';
import '../../features/expenses/record_expense_modal.dart';
import '../../services/ai/expense_extractor.dart';
import '../../shared/app_notification.dart';
import '../../shared/widgets.dart';
import 'quick_expense_batch.dart';
import 'widget_capture_lifecycle.dart';

typedef QuickRecorderBuilder = Widget Function(
  Future<void> Function(List<ExtractedExpense>) onExtracted,
);

class QuickExpenseScreen extends ConsumerStatefulWidget {
  final bool record;
  @visibleForTesting
  final QuickRecorderBuilder? recorderBuilder;
  const QuickExpenseScreen({
    super.key,
    required this.record,
    this.recorderBuilder,
  });
  @override
  ConsumerState<QuickExpenseScreen> createState() => _QuickExpenseScreenState();
}

class _QuickExpenseScreenState extends ConsumerState<QuickExpenseScreen> {
  final captureToken = Object();
  @override
  void initState() {
    super.initState();
    HomeWidgetCapture.begin(captureToken);
  }

  @override
  void dispose() {
    HomeWidgetCapture.finish(captureToken);
    super.dispose();
  }

  late final batch = QuickExpenseBatch(ref.read(localStoreProvider));
  late final currency = ref.read(preferencesProvider).currency;
  List<Expense>? saved;
  bool saving = false, undoing = false;
  String? error;

  Future<void> _save(List<Expense> expenses) async {
    if (!mounted) return;
    setState(() => saving = true);
    try {
      final values = await batch.save(expenses);
      HomeWidgetCapture.finish(captureToken);
      if (mounted) {
        setState(() {
          saved = values;
          error = null;
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveExtracted(List<ExtractedExpense> values) {
    final capturedAt = DateTime.now();
    return _save([
      for (final e in values)
        Expense(
          id: '',
          title: e.title,
          description: e.description,
          amount: e.amount,
          category: e.category,
          currencyCode: currency.code,
          date: capturedAt,
        ),
    ]);
  }

  Future<void> _undo() async {
    if (undoing || batch.undone) return;
    setState(() {
      undoing = true;
      error = null;
    });
    try {
      await batch.undo();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not undo this capture. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => undoing = false);
    }
  }

  void _close() {
    if (saving || undoing) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The manual flow reuses the ordinary form, including its date/category checks.
    if (!widget.record && saved == null) {
      return PopScope(
        canPop: !saving,
        child: AddExpenseScreen(onSave: _save),
      );
    }
    final completed = saved != null;
    return PopScope(
      canPop: !saving && !undoing,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            'Quick Expense',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              onPressed: saving || undoing ? null : _close,
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: completed
                    ? _completion(context)
                    : widget.recorderBuilder?.call(_saveExtracted) ??
                          RecordExpenseModal(
                            onExtracted: _saveExtracted,
                            onOpenSettings: () => context.go('/profile'),
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completion(BuildContext context) {
    final undone = batch.undone;
    final values = saved!;
    final code = values.first.currencyCode;
    final displayCurrency = AppCurrency.values.firstWhere(
      (value) => value.code == code,
    );
    return Semantics(
      liveRegion: true,
      child: SurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              undone ? Icons.undo_rounded : Icons.check_circle_outline,
              size: 42,
              color: green,
            ),
            const SizedBox(height: 12),
            Text(
              undone
                  ? 'Expenses removed'
                  : '${values.length} expense${values.length == 1 ? '' : 's'} added',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              undone ? 'This capture has been removed from your ledger.' : 'Saved on this device. Your spending and budget are updated.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.appColors.muted),
            ),
            if (!undone) ...[
              const SizedBox(height: 16),
              for (final expense in values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          expense.title,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        displayCurrency.format(expense.amount),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              AppNotificationCard(message: error!, isError: true),
            ],
            const SizedBox(height: 18),
            if (!undone) ...[
              OutlinedButton.icon(
                onPressed: undoing ? null : _undo,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(undoing ? 'Undoing…' : 'Undo'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: undoing ? null : () => context.go('/'),
              child: const Text('View expenses'),
            ),
            TextButton(
              onPressed: undoing ? null : _close,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
