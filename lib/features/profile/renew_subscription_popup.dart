import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/subscriptions.dart';
import '../../core/theme.dart';
import '../../database/subscription_store.dart';
import '../../shared/expense_date_picker.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/widgets.dart';
import '../expenses/expense_draft_card.dart';

Future<void> showRenewSubscriptionPopup(
  BuildContext context,
  SubscriptionMatch renewal,
) => showDialog<void>(
  context: context,
  builder: (_) => RenewSubscriptionPopup(renewal: renewal),
);

class RenewSubscriptionPopup extends ConsumerStatefulWidget {
  const RenewSubscriptionPopup({super.key, required this.renewal});
  final SubscriptionMatch renewal;

  @override
  ConsumerState<RenewSubscriptionPopup> createState() => _RenewPopupState();
}

class _RenewPopupState extends ConsumerState<RenewSubscriptionPopup> {
  final _form = GlobalKey<FormState>();
  late final _draft = ExpenseDraft(
    title: widget.renewal.plan.name,
    amount: (widget.renewal.plan.minor / 100).toStringAsFixed(2),
    category: ref.read(categoriesProvider).first.name,
  );
  DateTime _paymentDate = DateTime.now();
  bool _saving = false;
  bool _linkMode = false;
  int _monthOffset = 0;
  String? _expenseId;

  Iterable<Expense> _eligibleExpenses(
    List<Expense> expenses,
    SubscriptionState? subscriptions,
  ) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - _monthOffset);
    return expenses.where(
      (expense) =>
          !expense.isRefund &&
          expense.currencyCode == widget.renewal.plan.currencyCode &&
          expense.date.year == month.year &&
          expense.date.month == month.month &&
          !(subscriptions?.byExpense.containsKey(expense.id) ?? false),
    );
  }

  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _complete({required bool skip}) async {
    if (_saving || (!skip && !_linkMode && !_form.currentState!.validate())) {
      return;
    }
    if (!skip &&
        _linkMode &&
        !_eligibleExpenses(
          ref.read(expensesProvider),
          ref.read(subscriptionsProvider).value,
        ).any((expense) => expense.id == _expenseId)) {
      setState(() => _error = 'Select an available expense to link.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final renewal = widget.renewal;
      final store = ref.read(subscriptionStoreProvider);
      if (skip) {
        await store.skip(renewal.plan.id, renewal.dueDay);
      } else if (_linkMode) {
        await store.link(renewal.plan.id, {renewal.dueDay: _expenseId!});
      } else {
        await store.saveAndLink(
          Expense(
            id: _draft.id,
            title: _draft.title.text.trim(),
            description: _draft.description.text.trim(),
            category: _draft.category,
            amount: double.parse(_draft.amount.text.trim()),
            date: _paymentDate,
            currencyCode: renewal.plan.currencyCode,
          ),
          renewal.plan.id,
          renewal.dueDay,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not ${skip ? 'skip' : 'save'} this renewal. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final renewal = widget.renewal;
    final categories = ref.watch(categoriesProvider);
    final currency = AppCurrency.fromCode(renewal.plan.currencyCode);
    final candidates = _linkMode
        ? (_eligibleExpenses(
            ref.watch(expensesProvider),
            ref.watch(subscriptionsProvider).value,
          ).toList()..sort((a, b) => b.date.compareTo(a.date)))
        : <Expense>[];
    final selected = candidates
        .where((expense) => expense.id == _expenseId)
        .firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 420),
        child: SurfaceCard(
          padding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: green.withValues(alpha: .12),
                        foregroundColor: green,
                        child: const Icon(Icons.autorenew_rounded, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Renewal',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due ${DateFormat.yMMMd().format(subscriptionDate(renewal.dueDay))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ExpenseDraftCard(
                    d: _draft,
                    categories: categories,
                    currency: currency,
                    expenseLabel: 'Renewal',
                    allowRefund: false,
                    linkMode: _linkMode,
                    onLinkModeChanged: (value) => setState(() {
                      _linkMode = value;
                      _error = null;
                    }),
                    linkFields: [
                      AppDropdown<int>(
                        value: _monthOffset,
                        label: 'Payment month',
                        enabled: !_saving,
                        options: const [
                          AppDropdownOption(0, 'This month'),
                          AppDropdownOption(1, 'Last month'),
                        ],
                        onChanged: (value) => setState(() {
                          _monthOffset = value;
                          _expenseId = null;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      AppDropdown<String>(
                        value: selected?.id ?? '',
                        label: 'Expense to link',
                        searchable: true,
                        enabled: !_saving,
                        options: [
                          for (final expense in candidates)
                            AppDropdownOption(
                              expense.id,
                              expense.title,
                              leadingText: DateFormat('dd MMM')
                                  .format(expense.date),
                              trailingText: currency.formatChart(
                                expense.amount,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _expenseId = value;
                          _error = null;
                        }),
                      ),
                      if (candidates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('No unlinked expenses in this month.'),
                        ),
                      if (selected != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Paid ${DateFormat.yMMMd().format(selected.date)} · ${currency.formatChart(selected.amount)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.muted,
                            ),
                          ),
                        ),
                    ],
                    editable: !_saving,
                    onCategoryChanged: (value) =>
                        setState(() => _draft.category = value),
                    additionalFields: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final date = await showExpenseDatePicker(
                                    context,
                                    _paymentDate,
                                  );
                                  if (mounted && date != null) {
                                    setState(
                                      () => _paymentDate = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        _paymentDate.hour,
                                        _paymentDate.minute,
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                          ),
                          label: Text(DateFormat.yMMMd().format(_paymentDate)),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(color: red)),
                    ),
                  const SizedBox(height: 12),
                  DialogActionRow(
                    secondaryLabel: 'Skip',
                    onSecondary: _saving ? null : () => _complete(skip: true),
                    onPrimary: _saving || (_linkMode && selected == null)
                        ? null
                        : () => _complete(skip: false),
                    primaryLabel: Text(
                      _saving
                          ? 'Saving…'
                          : _linkMode
                          ? 'Link payment'
                          : 'Renew',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
