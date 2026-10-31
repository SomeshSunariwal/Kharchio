import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../database/local_store.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/expense_date_picker.dart';
import '../../shared/widgets.dart';
import 'record_expense_modal.dart';

class ExpenseDraft {
  final String id;
  final TextEditingController title, description, amount;
  String category;
  TransactionType type;
  String? originalExpenseId;
  DateTime? date;
  ExpenseDraft({
    String? id,
    String title = '',
    String description = '',
    String amount = '',
    this.category = 'Groceries',
    this.type = TransactionType.expense,
    this.originalExpenseId,
    this.date,
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
  final List<ExpenseDraft>? initialDrafts;
  const AddExpenseScreen({
    super.key,
    this.expense,
    this.onSave,
    this.initialDrafts,
  });
  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseState();
}

class _AddExpenseState extends ConsumerState<AddExpenseScreen> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  late List<ExpenseDraft> drafts;
  late DateTime date;
  bool saving = false;
  bool loadingHistory = false;
  String? historyError;
  Expense? original;
  final savedEntries = <String, Expense>{};
  final removedRefunds = <String>{};
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
    drafts =
        widget.initialDrafts ??
        [
          if (e != null)
            ExpenseDraft(
              id: e.id,
              title: e.title,
              description: e.description,
              amount: e.amount.toString(),
              category: e.category,
              type: e.type,
              originalExpenseId: e.originalExpenseId,
              date: e.date,
            )
          else
            ExpenseDraft(category: ref.read(categoriesProvider).first.name),
        ];
    if (e != null) {
      loadingHistory = true;
      loadHistory(e);
    }
  }

  ExpenseDraft draftFrom(Expense e) => ExpenseDraft(
    id: e.id,
    title: e.title,
    description: e.description,
    amount: e.amount.toString(),
    category: e.category,
    type: e.type,
    originalExpenseId: e.originalExpenseId,
    date: e.date,
  );

  Future<void> loadHistory(Expense clicked) async {
    try {
      final entries = await ref.read(localStoreProvider).readExpenses();
      final rootId = clicked.isRefund ? clicked.originalExpenseId : clicked.id;
      final root = entries
          .where((e) => !e.isRefund && e.id == rootId)
          .firstOrNull;
      final refunds =
          root == null
                ? <Expense>[]
                : entries
                      .where(
                        (e) => e.isRefund && e.originalExpenseId == root.id,
                      )
                      .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        for (final d in drafts) {
          d.dispose();
        }
        original = root;
        final group = root == null ? [clicked] : [root, ...refunds];
        savedEntries.addEntries(group.map((e) => MapEntry(e.id, e)));
        drafts = group.map(draftFrom).toList();
        date = root?.date ?? clicked.date;
        loadingHistory = false;
        historyError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loadingHistory = false;
          historyError = 'Could not load transaction history.';
        });
      }
    }
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
    if (editing && original == null) return;
    setState(
      () => drafts.add(
        editing
            ? ExpenseDraft(
                title: 'Refund for ${original!.title}',
                category: original!.category,
                type: TransactionType.refund,
                originalExpenseId: original!.id,
                date: DateTime.now(),
              )
            : ExpenseDraft(category: ref.read(categoriesProvider).first.name),
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
              type: d.type,
              originalExpenseId: d.type == TransactionType.refund
                  ? d.originalExpenseId
                  : null,
              currencyCode: editing
                  ? (widget.expense as Expense).currencyCode
                  : context.currency.code,
              date:
                  d.date ??
                  DateTime(
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
        await ref.read(localStoreProvider).db.transaction(() async {
          await ref.read(expensesProvider.notifier).save(values);
          for (final id in removedRefunds) {
            await ref.read(expensesProvider.notifier).delete(id);
          }
        });
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 52,
      leadingWidth: 40,
      titleSpacing: 0,
      title: Text(
        editing
            ? (original == null && !loadingHistory
                  ? 'Edit Refund'
                  : 'Expense History')
            : 'Add Expense',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton.icon(
          onPressed: editing
              ? null
              : () async {
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
          child: loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : historyError != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(historyError!),
                    TextButton(
                      onPressed: () {
                        setState(() => loadingHistory = true);
                        loadHistory(widget.expense as Expense);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Form(
                  key: form,
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
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
                            if (editing && original != null) ...[
                              _action(
                                'Add Refund',
                                Icons.south_west,
                                green,
                                green.withValues(alpha: .06),
                                add,
                              ),
                              SizedBox(height: 6),
                            ],
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
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 210),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.appColors.field,
                    border: Border.all(color: context.appColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedAlign(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeInOutCubic,
                          alignment: d.type == TransactionType.refund
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: .5,
                            heightFactor: 1,
                            child: AnimatedContainer(
                              key: ValueKey(
                                'transaction-type-highlight-${d.id}',
                              ),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeInOutCubic,
                              decoration: BoxDecoration(
                                color:
                                    (d.type == TransactionType.refund
                                            ? green
                                            : red)
                                        .withValues(
                                          alpha: context.appColors.dark
                                              ? .15
                                              : .08,
                                        ),
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _typeTab(
                            d,
                            TransactionType.expense,
                            'Expense',
                            Icons.north_east,
                            red,
                          ),
                          _typeTab(
                            d,
                            TransactionType.refund,
                            'Refund',
                            Icons.south_west,
                            green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: d.type == TransactionType.refund
                  ? 'Remove refund card'
                  : 'Remove expense card',
              style: IconButton.styleFrom(foregroundColor: red),
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: saving
                  ? null
                  : editing && d.type == TransactionType.expense
                  ? null
                  : drafts.length == 1
                  ? null
                  : () => setState(() {
                      drafts.remove(d);
                      if (savedEntries.containsKey(d.id)) {
                        removedRefunds.add(d.id);
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        d.dispose();
                      });
                    }),
              icon: Icon(Icons.delete_outline, size: 18),
              color: red,
            ),
          ],
        ),
        SizedBox(height: 10),
        TextFormField(
          controller: d.title,
          readOnly: editing && d.type == TransactionType.expense,
          style: TextStyle(fontSize: 12),
          textCapitalization: TextCapitalization.sentences,
          decoration: _input('Title'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Enter a title' : null,
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: d.description,
          readOnly: editing && d.type == TransactionType.expense,
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
                enabled: (!editing || original == null) && !saving,
                leadingIcon:
                    context.categoryIcons[context.categoryIndex(d.category)],
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
                  style: TextStyle(
                    fontSize: 13,
                    color: d.type == TransactionType.refund ? green : red,
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      _input(
                        'Amount (${context.currency.symbol})',
                        hint: '0.00',
                      ).copyWith(
                        prefixIcon: Icon(
                          d.type == TransactionType.refund
                              ? Icons.south_west
                              : Icons.north_east,
                          size: 16,
                          color: d.type == TransactionType.refund ? green : red,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 36,
                        ),
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
        if (d.type == TransactionType.refund &&
            (!editing || original == null)) ...[
          SizedBox(height: 10),
          _originalPayment(d),
        ],
        if (editing && d.date != null) ...[
          SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('transaction-date-${d.id}'),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: green,
                disabledForegroundColor: context.appColors.muted,
              ),
              onPressed: saving || d.type == TransactionType.expense
                  ? null
                  : () async {
                      final picked = await showExpenseDatePicker(
                        context,
                        d.date!,
                      );
                      if (picked != null && mounted) {
                        setState(
                          () => d.date = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            d.date!.hour,
                            d.date!.minute,
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.calendar_today_outlined, size: 13),
              label: Text(
                DateFormat('dd MMM yy').format(d.date!),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _typeTab(
    ExpenseDraft draft,
    TransactionType type,
    String label,
    IconData icon,
    Color color,
  ) {
    final selected = draft.type == type;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: saving || editing
                ? null
                : () => setState(() => draft.type = type),
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? color : context.appColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? color : context.appColors.muted,
                      ),
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

  Widget _originalPayment(ExpenseDraft draft) {
    final currency = editing
        ? (widget.expense as Expense).currencyCode
        : context.currency.code;
    final payments = ref
        .watch(expensesProvider)
        .where(
          (e) => !e.isRefund && e.id != draft.id && e.currencyCode == currency,
        )
        .toList();
    final linked = payments
        .where((e) => e.id == draft.originalExpenseId)
        .firstOrNull;
    return AppDropdown<String>(
      value: linked?.id ?? '',
      label: 'Original expense (optional)',
      enabled: !saving,
      scrollIntoViewOnOpen: true,
      options: [
        const AppDropdownOption('', 'Standalone refund'),
        for (final payment in payments)
          AppDropdownOption(
            payment.id,
            '${payment.title} · ${context.money(payment.amount)}',
          ),
      ],
      onChanged: (id) => setState(() {
        draft.originalExpenseId = id == '' ? null : id;
        final payment = payments.where((e) => e.id == id).firstOrNull;
        if (payment != null) draft.category = payment.category;
      }),
    );
  }
}
