import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'categories.dart';
import 'demo_data.dart';
import 'expense.dart';
export 'expense.dart';

// Temporary review store. Demo fixtures can be disabled in demo_data.dart.
final expensesProvider = NotifierProvider<ExpenseStore, List<Expense>>(
  ExpenseStore.new,
);

class ExpenseStore extends Notifier<List<Expense>> {
  @override
  List<Expense> build() {
    final categories = ref.read(initialCategoriesProvider);
    final fallback =
        categories.where((c) => c.name == 'Others').firstOrNull ??
        categories.first;
    return createDemoExpenses()
        .map(
          (e) => categories.any((c) => c.name == e.category)
              ? e
              : _withCategory(e, fallback.name),
        )
        .toList();
  }

  void save(List<Expense> values) => state = [
    ...state.where((e) => !values.any((v) => v.id == e.id)),
    ...values,
  ]..sort((a, b) => b.date.compareTo(a.date));
  void delete(String id) => state = state.where((e) => e.id != id).toList();
  void reassignCategory(String from, String to) => state = state
      .map((e) => e.category == from ? _withCategory(e, to) : e)
      .toList();
  Expense _withCategory(Expense e, String category) => Expense(
    id: e.id,
    title: e.title,
    description: e.description,
    category: category,
    amount: e.amount,
    date: e.date,
  );
}

final selectedMonthProvider = NotifierProvider<MonthStore, DateTime>(
  MonthStore.new,
);

class MonthStore extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }
}
