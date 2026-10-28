import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/monthly_budgets.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/swipe_delete_expense.dart';
import '../../shared/widgets.dart';

String budgetMonth(MonthlyBudget budget) =>
    DateFormat('MMMM yyyy').format(DateTime(budget.year, budget.month));

class BudgetPlannerScreen extends ConsumerWidget {
  const BudgetPlannerScreen({super.key});
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MonthlyBudget budget,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete monthly budget?'),
        content: Text(
          'Delete the budget for ${budgetMonth(budget)}? The month and its expenses will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: red,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(monthlyBudgetsProvider.notifier).delete(budget);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(monthlyBudgetsProvider);
    final currency = ref.watch(preferencesProvider.select((p) => p.currency));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Budget Planner',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                Expanded(
                  child: budgets.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load your monthly budgets.'),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(monthlyBudgetsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (all) {
                      final rows = all
                          .where((b) => b.currency == currency.code)
                          .toList();
                      return ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Text(
                            'Set a spending budget for each month. Tap a budget to edit it, or swipe left to delete.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.muted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            SurfaceCard(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Center(
                                  child: Text(
                                    'No monthly budgets yet.',
                                    style: TextStyle(
                                      color: context.appColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < rows.length; i++) ...[
                                    SwipeRevealDelete(
                                      key: ValueKey(rows[i].key),
                                      onDelete: () =>
                                          _delete(context, ref, rows[i]),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        minTileHeight: 50,
                                        dense: true,
                                        minVerticalPadding: 0,
                                        title: Text(
                                          budgetMonth(rows[i]),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        trailing: Text(
                                          currency.formatChart(rows[i].amount),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: green,
                                          ),
                                        ),
                                        onTap: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => _BudgetDialog(
                                            currency: currency,
                                            budget: rows[i],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (i < rows.length - 1)
                                      Divider(
                                        height: 1,
                                        color: context.appColors.line,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: budgets.hasValue
                          ? () => showDialog<void>(
                              context: context,
                              builder: (_) => _BudgetDialog(currency: currency),
                            )
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Budget'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetDialog extends ConsumerStatefulWidget {
  final AppCurrency currency;
  final MonthlyBudget? budget;
  const _BudgetDialog({required this.currency, this.budget});
  @override
  ConsumerState<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends ConsumerState<_BudgetDialog> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.budget?.amount.toStringAsFixed(2) ?? '',
  );
  late int month = widget.budget?.month ?? DateTime.now().month;
  late int year = widget.budget?.year ?? DateTime.now().year;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final budget = MonthlyBudget(
      year: year,
      month: month,
      amount: double.parse(amount.text.trim()),
      currency: widget.currency.code,
    );
    if (widget.budget == null &&
        ref
            .read(monthlyBudgetsProvider)
            .requireValue
            .any((b) => b.key == budget.key)) {
      setState(
        () => error =
            'A budget already exists for this month. Tap its row to edit it.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(monthlyBudgetsProvider.notifier).save(budget);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save the budget. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thisYear = DateTime.now().year;
    final years = {
      for (var y = thisYear - 10; y <= thisYear + 20; y++) y,
      year,
    }.toList()..sort();
    return PopScope(
      canPop: !saving,
      child: Dialog(
        backgroundColor: context.appColors.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: green,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.budget == null
                                ? 'Add Monthly Budget'
                                : 'Edit Monthly Budget',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Plan your monthly spending',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: saving ? null : () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: AppDropdown<int>(
                                  label: 'Month',
                                  value: month,
                                  enabled: !saving && widget.budget == null,
                                  options: [
                                    for (var m = 1; m <= 12; m++)
                                      AppDropdownOption(
                                        m,
                                        DateFormat('MMMM')
                                            .format(DateTime(2026, m)),
                                      ),
                                  ],
                                  onChanged: (value) => setState(() {
                                    month = value;
                                    error = null;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: AppDropdown<int>(
                                  label: 'Year',
                                  value: year,
                                  enabled: !saving && widget.budget == null,
                                  options: [
                                    for (final y in years)
                                      AppDropdownOption(y, '$y'),
                                  ],
                                  onChanged: (value) => setState(() {
                                    year = value;
                                    error = null;
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: amount,
                            style: const TextStyle(fontSize: 14),
                            enabled: !saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => save(),
                            decoration: InputDecoration(
                              labelText:
                                  'Monthly budget (${widget.currency.code})',
                              prefixText: '${widget.currency.symbol} ',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              final number = double.tryParse(text);
                              if (!RegExp(r'^\d+(\.\d{1,2})?$')
                                      .hasMatch(text) ||
                                  number == null ||
                                  !number.isFinite ||
                                  number <= 0) {
                                return 'Enter a positive amount with up to 2 decimals.';
                              }
                              if (number > 999999999999) {
                                return 'Enter a smaller budget.';
                              }
                              return null;
                            },
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              error!,
                              style: const TextStyle(fontSize: 12, color: red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: BorderSide(color: context.appColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: context.appColors.ink),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: saving ? null : save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(saving ? 'Saving…' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
