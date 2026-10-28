import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/destructive_confirmation.dart';
import '../../shared/expense_date_picker.dart';
import '../../shared/widgets.dart';
import 'record_expense_modal.dart';

class ExpenseDraft {
  final String id;
  final TextEditingController title, description, amount;
  String category;
  ExpenseDraft({
    String? id,
    String title = '',
    String description = '',
    String amount = '',
    this.category = 'Groceries',
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       title = TextEditingController(text: title),
       description = TextEditingController(text: description),
       amount = TextEditingController(
         text: double.tryParse(amount)?.toStringAsFixed(2) ?? amount,
       );
  void formatAmount() {
    final value = double.tryParse(amount.text);
    if (value != null && value.isFinite) {
      amount.text = value.toStringAsFixed(2);
    }
  }

  void dispose() {
    title.dispose();
    description.dispose();
    amount.dispose();
  }
}

class AddExpenseScreen extends ConsumerStatefulWidget {
  final Object? expense;
  final Future<void> Function(List<Expense>)? onSave;
  const AddExpenseScreen({super.key, this.expense, this.onSave});
  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseState();
}

class _AddExpenseState extends ConsumerState<AddExpenseScreen> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  late List<ExpenseDraft> drafts;
  late DateTime date;
  bool saving = false;
  bool get editing => widget.expense is Expense;

  @override
  void initState() {
    super.initState();
    final e = widget.expense is Expense ? widget.expense as Expense : null;
    date =
        e?.date ??
        (widget.expense is DateTime
            ? widget.expense as DateTime
            : DateTime.now());
    drafts = [
      if (e != null)
        ExpenseDraft(
          id: e.id,
          title: e.title,
          description: e.description,
          amount: e.amount.toString(),
          category: e.category,
        )
      else
        ExpenseDraft(category: ref.read(categoriesProvider).first.name),
    ];
  }

  @override
  void dispose() {
    for (final d in drafts) {
      d.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void add() {
    setState(
      () => drafts.add(
        ExpenseDraft(category: ref.read(categoriesProvider).first.name),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          // Reveal the new card above the actions without consuming the extra
          // scroll space reserved for opening its dropdown.
          (scroll.position.maxScrollExtent -
                  scroll.position.viewportDimension / 2 +
                  8)
              .clamp(0.0, scroll.position.maxScrollExtent),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!form.currentState!.validate()) return;
    if (saving) return;
    setState(() => saving = true);
    final now = DateTime.now();
    try {
      final values = drafts
          .map(
            (d) => Expense(
              id: d.id,
              title: d.title.text.trim(),
              description: d.description.text.trim(),
              category: d.category,
              amount: double.parse(d.amount.text),
              currencyCode: editing
                  ? (widget.expense as Expense).currencyCode
                  : context.currency.code,
              date: DateTime(
                date.year,
                date.month,
                date.day,
                editing ? date.hour : now.hour,
                editing ? date.minute : now.minute,
              ),
            ),
          )
          .toList();
      if (widget.onSave != null) {
        await widget.onSave!(values);
      } else {
        await ref.read(expensesProvider.notifier).save(values);
        if (mounted) context.pop();
      }
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not save expenses. Please try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> record() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<List<ExpenseDraft>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordExpenseModal(),
    );
    if (result != null && mounted) {
      setState(() {
        if (drafts.length == 1 &&
            drafts.first.title.text.isEmpty &&
            drafts.first.amount.text.isEmpty) {
          drafts.removeLast().dispose();
        }
        drafts.addAll(result);
      });
    }
  }

  Future<void> deleteExpense() async {
    if (saving) return;
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete expense?',
      message: 'This permanently removes the saved expense.',
    );
    if (confirmed == true && mounted) {
      setState(() => saving = true);
      try {
        await ref
            .read(expensesProvider.notifier)
            .delete((widget.expense as Expense).id);
        if (mounted) context.pop();
      } catch (_) {
        if (mounted) {
          notice(context, 'Could not delete the expense. Please try again.');
        }
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 52,
      leadingWidth: 40,
      titleSpacing: 0,
      title: Text(
        editing ? 'Edit Expense' : 'Add Expense',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final picked = await showExpenseDatePicker(context, date);
            if (picked != null && mounted) setState(() => date = picked);
          },
          icon: Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(
            DateFormat('dd MMM yy').format(date),
            style: TextStyle(
              color: context.appColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 700),
          child: Form(
            key: form,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      controller: scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      // The last card can move into the middle of the viewport,
                      // leaving space below its category dropdown.
                      padding: EdgeInsets.fromLTRB(
                        14,
                        8,
                        14,
                        constraints.maxHeight / 2,
                      ),
                      // Keep every field mounted so Save validates offscreen cards too.
                      child: Column(
                        children: [
                          for (var i = 0; i < drafts.length; i++)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: _card(drafts[i], i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Outside the list: these actions remain visible as the cards scroll.
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    border: Border(
                      top: BorderSide(color: context.appColors.line),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!editing) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _action(
                                'Add Expense',
                                Icons.add_circle_outline,
                                context.appColors.actionBlue,
                                context.appColors.actionBlue.withValues(
                                  alpha: .05,
                                ),
                                add,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: _action(
                                'Record Expense',
                                Icons.mic,
                                red,
                                red.withValues(alpha: .06),
                                record,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                      ],
                      _action(
                        editing
                            ? (saving ? 'Saving…' : 'Save Changes')
                            : 'Add Expenses (${drafts.length})',
                        Icons.check_circle,
                        Colors.white,
                        green,
                        save,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _action(
    String label,
    IconData icon,
    Color foreground,
    Color background,
    VoidCallback onTap,
  ) => SizedBox(
    width: double.infinity,
    height: 46,
    child: FilledButton.icon(
      onPressed: saving ? null : onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: background,
        foregroundColor: foreground,
        side: BorderSide(
          color: foreground == Colors.white
              ? green
              : foreground.withValues(alpha: .3),
        ),
      ),
    ),
  );

  InputDecoration _input(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(fontSize: 12, color: context.appColors.muted),
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  );

  Widget _card(ExpenseDraft d, int index) => SurfaceCard(
    key: ValueKey(d.id),
    padding: EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CategoryIcon(d.category, size: 27),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Expense ${index + 1}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Remove expense card',
              style: IconButton.styleFrom(foregroundColor: red),
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: saving
                  ? null
                  : editing
                  ? deleteExpense
                  : drafts.length == 1
                  ? null
                  : () => setState(() {
                      drafts.remove(d);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        d.dispose();
                      });
                    }),
              icon: Icon(Icons.delete_outline, size: 18),
              color: red,
            ),
          ],
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: d.title,
          style: TextStyle(fontSize: 12),
          textCapitalization: TextCapitalization.sentences,
          decoration: _input('Title'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Enter a title' : null,
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: d.description,
          style: TextStyle(fontSize: 12),
          minLines: 1,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: _input('Description (optional)', hint: 'Add a note…'),
        ),
        SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AppDropdown<String>(
                value: d.category,
                label: 'Category',
                scrollIntoViewOnOpen: true,
                options: [
                  for (var i = 0; i < context.categoryNames.length; i++)
                    AppDropdownOption(
                      context.categoryNames[i],
                      context.categoryNames[i],
                      icon: context.categoryIcons[i],
                    ),
                ],
                onChanged: (value) => setState(() => d.category = value),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Focus(
                onFocusChange: (focused) {
                  if (!focused) d.formatAmount();
                },
                child: TextFormField(
                  controller: d.amount,
                  style: TextStyle(fontSize: 13),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: _input(
                    'Amount (${context.currency.symbol})',
                    hint: '0.00',
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          RegExp(r'^\d{0,10}(\.\d{0,2})?$')
                              .hasMatch(newValue.text)
                          ? newValue
                          : oldValue,
                    ),
                  ],
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n <= 0
                        ? 'Invalid amount'
                        : null;
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
