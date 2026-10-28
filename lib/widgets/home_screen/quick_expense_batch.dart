import 'package:uuid/uuid.dart';

import '../../core/expense.dart';
import '../../database/local_store.dart';

/// A widget capture commits once, atomically, through the regular repository.
/// Undo removes only this capture's UUIDs, including captures with many expenses.
class QuickExpenseBatch {
  final LocalStore store;
  QuickExpenseBatch(this.store);
  Future<List<Expense>>? _saving;
  List<Expense>? _saved;
  Future<void>? _undoing;
  bool undone = false;

  Future<List<Expense>> save(List<Expense> expenses) {
    if (_saved != null) return Future.value(_saved);
    if (expenses.isEmpty) {
      return Future.error(ArgumentError('No expenses to save.'));
    }
    return _saving ??= _persist(expenses);
  }

  Future<List<Expense>> _persist(List<Expense> expenses) async {
    final values = List<Expense>.unmodifiable(
      expenses.map(
        (e) => Expense(
          id: const Uuid().v4(),
          title: e.title,
          description: e.description,
          amount: e.amount,
          category: e.category,
          currencyCode: e.currencyCode,
          date: e.date,
        ),
      ),
    );
    try {
      await store.saveExpenses(values);
      _saved = values;
      return values;
    } catch (_) {
      _saving = null;
      rethrow;
    }
  }

  Future<void> undo() {
    if (undone || _saved == null) return Future.value();
    return _undoing ??= _undo();
  }

  Future<void> _undo() async {
    try {
      await store.db.transaction(() async {
        for (final expense in _saved!) {
          await store.deleteExpense(expense.id);
        }
      });
      undone = true;
    } catch (_) {
      _undoing = null;
      rethrow;
    }
  }
}
