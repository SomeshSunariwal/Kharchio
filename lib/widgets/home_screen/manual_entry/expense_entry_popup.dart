import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/categories.dart';
import '../../../core/expense.dart';
import '../../../core/preferences.dart';
import '../../../core/theme.dart';
import '../../../database/local_store.dart';
import '../../../shared/app_dropdown.dart';
import '../../../shared/app_notification.dart';
import '../../../shared/widgets.dart';
import '../quick_expense_batch.dart';
import '../spending_widget_updates.dart';
import '../widget_action_host.dart';

/// Runs in a translucent Android task, with the launcher visible behind it.
class ExpenseEntryPopup extends ConsumerStatefulWidget {
  final String focus;
  const ExpenseEntryPopup({super.key, this.focus = 'title'});
  @override
  ConsumerState<ExpenseEntryPopup> createState() => _ExpenseEntryPopupState();
}

class _ExpenseEntryPopupState extends ConsumerState<ExpenseEntryPopup> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  late final batch = QuickExpenseBatch(ref.read(localStoreProvider));
  String? category;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> _close({bool saved = false}) async {
    if (saving && !saved) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await homeWidgetChannel.invokeMethod<void>('closeEntry', {
        'saved': saved,
      });
    } on MissingPluginException {
      await SystemNavigator.pop();
    } on PlatformException {
      await SystemNavigator.pop();
    }
  }

  ExpenseCategory _selectedCategory(List<ExpenseCategory> categories) =>
      categories.where((c) => c.name == category).firstOrNull ??
      categories.first;

  Future<void> _save() async {
    if (saving || !form.currentState!.validate()) return;
    final categories = ref.read(categoriesProvider);
    final selected = _selectedCategory(categories);
    final currency = ref.read(preferencesProvider).currency;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await batch.save([
        Expense(
          id: '',
          title: title.text.trim(),
          description: description.text.trim(),
          amount: double.parse(amount.text),
          category: selected.name,
          currencyCode: currency.code,
          date: DateTime.now(),
        ),
      ]);
      // Complete the refresh request before this popup's Flutter engine exits.
      await SpendingWidgetUpdates.refresh();
      if (mounted) await _close(saved: true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the expense. Please try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    counterText: '',
    labelStyle: TextStyle(fontSize: 12, color: context.appColors.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  );
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final currency = ref.watch(preferencesProvider).currency;
    final selected = _selectedCategory(categories);
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: saving ? null : () => _close(),
          child: ColoredBox(
            color: Colors.black.withValues(alpha: .16),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GestureDetector(
                      onTap: () {},
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: form,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  CategoryIcon(selected.name, size: 28),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Expense 1',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close',
                                    onPressed: saving ? null : () => _close(),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: title,
                                enabled: !saving,
                                autofocus: widget.focus == 'title',
                                maxLength: 200,
                                style: const TextStyle(fontSize: 12),
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.next,
                                decoration: _input('Title'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Enter a title'
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: description,
                                enabled: !saving,
                                autofocus: widget.focus == 'description',
                                maxLength: 500,
                                style: const TextStyle(fontSize: 12),
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.next,
                                decoration: _input('Description (optional)'),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: AppDropdown<String>(
                                      label: 'Category',
                                      value: selected.name,
                                      enabled: !saving,
                                      options: [
                                        for (final c in categories)
                                          AppDropdownOption(c.name, c.name),
                                      ],
                                      onChanged: (value) =>
                                          setState(() => category = value),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: amount,
                                      enabled: !saving,
                                      autofocus: widget.focus == 'amount',
                                      style: const TextStyle(fontSize: 12),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.]'),
                                        ),
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _save(),
                                      decoration: _input(
                                        'Amount (${currency.symbol})',
                                      ),
                                      validator: (value) {
                                        final text = value?.trim() ?? '';
                                        final number = double.tryParse(text);
                                        if (!RegExp(r'^\d+(\.\d{1,2})?$')
                                                .hasMatch(text) ||
                                            number == null ||
                                            !number.isFinite ||
                                            number <= 0 ||
                                            number > 9999999999.99) {
                                          return 'Enter a valid amount';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 10),
                                AppNotificationCard(
                                  message: error!,
                                  isError: true,
                                ),
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: FilledButton.icon(
                                  onPressed: saving ? null : _save,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text(
                                    saving ? 'Adding…' : 'Add Expense',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
