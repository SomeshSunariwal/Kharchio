import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/subscriptions.dart';
import '../../core/theme.dart';
import '../../database/subscription_store.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/expense_date_picker.dart';
import '../../shared/widgets.dart';

String? validateSubscriptionAmount(String? input) {
  final value = input?.trim() ?? '';
  final amount = double.tryParse(value);
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value) ||
      amount == null ||
      amount <= 0 ||
      amount > 9999999999.99) {
    return 'Enter an amount greater than zero with up to 2 decimal places';
  }
  return null;
}

Widget subscriptionPickerRow(
  BuildContext context,
  String label,
  String value,
  IconData icon,
  VoidCallback? onTap, {
  bool compact = false,
}) {
  final tile = ListTile(
    contentPadding: compact
        ? const EdgeInsets.symmetric(horizontal: 10)
        : EdgeInsets.zero,
    dense: true,
    visualDensity: compact ? VisualDensity.standard : null,
    minTileHeight: compact ? settingsListRowHeight : null,
    minVerticalPadding: compact ? 6 : null,
    titleAlignment: compact ? ListTileTitleAlignment.center : null,
    titleTextStyle: compact
        ? TextStyle(fontSize: 13, color: context.appColors.ink)
        : null,
    subtitleTextStyle: compact
        ? TextStyle(fontSize: 12, color: context.appColors.muted)
        : null,
    leading: Icon(icon, size: 20, color: context.appColors.muted),
    title: Text(label),
    subtitle: compact
        ? Padding(padding: const EdgeInsets.only(top: 2), child: Text(value))
        : Text(value),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: onTap,
  );
  if (!compact) return tile;
  return Material(
    color: context.appColors.field,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.appColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: tile,
  );
}

class SubscriptionRenewalDialog extends ConsumerStatefulWidget {
  final SubscriptionPlan plan;
  final DateTime initialDue;
  const SubscriptionRenewalDialog({
    super.key,
    required this.plan,
    required this.initialDue,
  });

  @override
  ConsumerState<SubscriptionRenewalDialog> createState() => _RenewalState();
}

class _RenewalState extends ConsumerState<SubscriptionRenewalDialog> {
  late DateTime _due = widget.initialDue;
  SubscriptionPlan get _plan => widget.plan;
  int get _day => subscriptionDay(_due);
  bool _busy = false;
  String? _error;

  Future<void> _changeDue() async {
    final picked = await showExpenseDatePicker(context, _due);
    if (!mounted || picked == null) return;
    final state = ref.read(subscriptionsProvider).value;
    final match = subscriptionDueOnOrAfter(
      _plan,
      DateTime(picked.year, picked.month),
    );
    setState(() {
      if (state?.renewal(_plan.id, subscriptionDay(picked)) != null) {
        _due = picked;
        _error = null;
      } else if (match.year == picked.year && match.month == picked.month) {
        _due = match;
        _error = null;
      } else {
        _error = 'There is no scheduled renewal in that month.';
      }
    });
  }

  Future<void> _change(
    Future<void> Function(SubscriptionStore store) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(subscriptionStoreProvider));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not update this renewal. Please try again.';
        });
      }
    }
  }

  Future<void> _link() async {
    final linked = ref.read(subscriptionsProvider).value?.byExpense ?? {};
    final candidates = ref
        .read(expensesProvider)
        .where(
          (expense) =>
              !expense.isRefund &&
              expense.currencyCode == _plan.currencyCode &&
              !linked.containsKey(expense.id),
        )
        .toList();
    candidates.sort((a, b) {
      final aMatch = subscriptionMerchantMatches(_plan, a.title);
      final bMatch = subscriptionMerchantMatches(_plan, b.title);
      if (aMatch != bMatch) return aMatch ? -1 : 1;
      return b.date.compareTo(a.date);
    });
    final expense = await showDialog<Expense>(
      context: context,
      builder: (_) => _PickExpense(candidates: candidates),
    );
    if (mounted && expense != null) {
      await _change((store) => store.link(_plan.id, {_day: expense.id}));
    }
  }

  Future<void> _record() async {
    final expense = await showDialog<Expense>(
      context: context,
      builder: (_) => _RecordSubscriptionPayment(plan: _plan),
    );
    if (mounted && expense != null) {
      await _change((store) => store.saveAndLink(expense, _plan.id, _day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final renewal = ref
        .watch(subscriptionsProvider)
        .value
        ?.renewal(_plan.id, _day);
    final expenseId = renewal?.expenseId;
    final expense = expenseId == null
        ? null
        : ref
              .watch(expensesProvider)
              .where((e) => e.id == expenseId)
              .firstOrNull;
    final status = expense != null
        ? 'Paid ${DateFormat.yMMMd().format(expense.date)}'
        : renewal?.skipped == true
        ? 'Skipped'
        : subscriptionDay(DateTime.now()) >= _day
        ? 'Payment unconfirmed'
        : 'Upcoming';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('${_plan.name} renewal'),
        scrollable: true,
        content: SizedBox(
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              subscriptionPickerRow(
                context,
                'Renewal due',
                DateFormat.yMMMd().format(_due),
                Icons.calendar_month_outlined,
                _busy ? null : _changeDue,
              ),
              const SizedBox(height: 6),
              Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (expense != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('View expense'),
                  subtitle: Text(expense.title),
                  trailing: Text(
                    AppCurrency.fromCode(expense.currencyCode)
                        .format(expense.amount),
                  ),
                  onTap: _busy
                      ? null
                      : () {
                          final router = GoRouter.of(context);
                          Navigator.pop(context);
                          router.push('/add', extra: expense);
                        },
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _change(
                          (store) => store.unlink(_plan.id, _day, expense.id),
                        ),
                  child: const Text('Unlink payment'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: _busy ? null : _record,
                  child: const Text('Record payment'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _link,
                  child: const Text('Link an expense'),
                ),
                if (renewal?.skipped != true)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _change((store) => store.skip(_plan.id, _day)),
                    child: const Text('Skip this renewal'),
                  ),
              ],
              if (_error != null)
                Text(_error!, style: const TextStyle(color: red)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PickExpense extends StatefulWidget {
  final List<Expense> candidates;
  const _PickExpense({required this.candidates});

  @override
  State<_PickExpense> createState() => _PickExpenseState();
}

class _PickExpenseState extends State<_PickExpense> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final values = widget.candidates
        .where((e) => e.title.toLowerCase().contains(_query))
        .toList();
    return AlertDialog(
      title: const Text('Link an expense'),
      content: SizedBox(
        width: 360,
        height: MediaQuery.sizeOf(context).height * .38,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search expenses',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Expanded(
              child: values.isEmpty
                  ? const Center(child: Text('No matching expenses.'))
                  : ListView.builder(
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final expense = values[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            expense.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat.yMMMd().format(expense.date),
                          ),
                          trailing: Text(
                            AppCurrency.fromCode(expense.currencyCode)
                                .formatChart(expense.amount),
                          ),
                          onTap: () => Navigator.pop(context, expense),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _RecordSubscriptionPayment extends ConsumerStatefulWidget {
  final SubscriptionPlan plan;
  const _RecordSubscriptionPayment({required this.plan});

  @override
  ConsumerState<_RecordSubscriptionPayment> createState() =>
      _RecordPaymentState();
}

class _RecordPaymentState extends ConsumerState<_RecordSubscriptionPayment> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: (widget.plan.minor / 100).toStringAsFixed(2),
  );
  DateTime _date = DateTime.now();
  String? _category;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final category = categories.any((item) => item.name == _category)
        ? _category!
        : (categories
                      .where(
                        (item) =>
                            item.iconKey == 'subscriptions' ||
                            item.iconKey == 'others',
                      )
                      .firstOrNull ??
                  categories.first)
              .name;
    return AlertDialog(
      title: const Text('Record payment'),
      scrollable: true,
      content: SizedBox(
        width: 340,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              const Text('This adds an expense and links it to the renewal.'),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Paid amount (${widget.plan.currencyCode})',
                ),
                validator: validateSubscriptionAmount,
              ),
              subscriptionPickerRow(
                context,
                'Payment date',
                DateFormat.yMMMd().format(_date),
                Icons.calendar_month_outlined,
                () async {
                  final chosen = await showExpenseDatePicker(context, _date);
                  if (mounted && chosen != null) setState(() => _date = chosen);
                },
              ),
              if (subscriptionDay(_date) > subscriptionDay(DateTime.now()))
                const Text(
                  'Choose a payment date on or before today.',
                  style: TextStyle(color: red),
                ),
              AppDropdown<String>(
                value: category,
                label: 'Expense category',
                options: [
                  for (final item in categories)
                    AppDropdownOption(item.name, item.name, icon: item.icon),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: subscriptionDay(_date) > subscriptionDay(DateTime.now())
              ? null
              : () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    Expense(
                      id: const Uuid().v4(),
                      title: widget.plan.name,
                      category: category,
                      amount: double.parse(_amount.text.trim()),
                      date: _date,
                      currencyCode: widget.plan.currencyCode,
                    ),
                  );
                },
          child: const Text('Save payment'),
        ),
      ],
    );
  }
}
