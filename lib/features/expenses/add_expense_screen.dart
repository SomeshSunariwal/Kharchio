import 'package:flutter/material.dart';
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
import 'expense_draft_card.dart';
import 'record_expense_modal.dart';

export 'expense_draft_card.dart' show ExpenseDraft;

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
    final source = editing
        ? drafts.firstWhere((d) => d.id == original!.id)
        : null;
    setState(
      () => drafts.add(
        editing
            ? ExpenseDraft(
                title: 'Refund for ${source!.title.text.trim()}',
                category: source.category,
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
                                        child: _card(drafts[i]),
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

  Widget _card(ExpenseDraft d) => ExpenseDraftCard(
    d: d,
    categories: context.expenseCategories,
    currency: context.currency,
    editable: !saving,
    onCategoryChanged: (value) => setState(() => d.category = value),
    onTypeChanged: editing ? null : (type) => setState(() => d.type = type),
    onRemove:
        saving ||
            (editing && d.type == TransactionType.expense) ||
            drafts.length == 1
        ? null
        : () => setState(() {
            drafts.remove(d);
            if (savedEntries.containsKey(d.id)) removedRefunds.add(d.id);
            WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
          }),
    additionalFields: [
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
  );

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
