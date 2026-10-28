import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_store.dart';
import 'expense.dart';
export 'expense.dart';

final expensesProvider = NotifierProvider<ExpenseStore, List<Expense>>(
  ExpenseStore.new,
);

/// UI facade; all mutations and persistence live in the database repository.
class ExpenseStore extends Notifier<List<Expense>> {
  @override
  List<Expense> build() {
    final store = ref.read(localStoreProvider);
    final subscription = store.watchExpenses().listen(
      (values) => state = values,
    );
    ref.onDispose(subscription.cancel);
    return store.initialExpenses;
  }

  Future<void> save(List<Expense> values) =>
      ref.read(localStoreProvider).saveExpenses(values);
  Future<void> refresh() async {
    final values = await ref.read(localStoreProvider).readExpenses();
    if (ref.mounted) state = values;
  }

  Future<void> delete(String id) =>
      ref.read(localStoreProvider).deleteExpense(id);

  Future<void> reset() async {
    await ref.read(localStoreProvider).clearExpenses();
    state = [];
  }
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
