import 'package:drift/drift.dart';

import '../database/app_database.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_store.dart';

class MonthlyBudget {
  final int year, month;
  final double amount;
  final String currency;
  const MonthlyBudget({
    required this.year,
    required this.month,
    required this.amount,
    required this.currency,
  });
  String get key => '$currency-$year-$month';
  Map<String, Object> toJson() => {
    'year': year,
    'month': month,
    'amount': amount,
    'currency': currency,
  };
}

final monthlyBudgetsProvider =
    AsyncNotifierProvider<MonthlyBudgets, List<MonthlyBudget>>(
      MonthlyBudgets.new,
    );

typedef BudgetMonth = ({int year, int month, String currencyCode});

final monthBudgetProvider = Provider.family<double?, BudgetMonth>((
  ref,
  period,
) {
  final budgets = ref.watch(monthlyBudgetsProvider).value;
  return budgets
      ?.where(
        (b) =>
            b.year == period.year &&
            b.month == period.month &&
            b.currency == period.currencyCode &&
            b.amount > 0,
      )
      .firstOrNull
      ?.amount;
});

double remainingMonthlyBudget(double budget, double spent) =>
    ((budget * 100).round() - (spent * 100).round()) / 100;

class MonthlyBudgets extends AsyncNotifier<List<MonthlyBudget>> {
  Future<void> _pending = Future.value();
  Future<List<MonthlyBudget>> _load() async {
    final db = ref.read(localStoreProvider).db;
    // -1 rows belong to transactions, but have no user-set budget.
    final rows =
        await (db.select(db.monthlyBudgetsTable)
              ..where((row) => row.budget.isBiggerThanValue(0))
              ..orderBy([
                (row) => OrderingTerm.desc(row.year),
                (row) => OrderingTerm.desc(row.month),
              ]))
            .get();
    return rows
        .map(
          (row) => MonthlyBudget(
            year: row.year,
            month: row.month,
            amount: row.budget,
            currency: row.currencyCode,
          ),
        )
        .toList();
  }

  @override
  Future<List<MonthlyBudget>> build() => _load();
  Future<void> _change(Future<void> Function() update) {
    final result = _pending.then((_) async {
      await future;
      await update();
      state = AsyncData(await _load());
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(MonthlyBudget budget) {
    if (budget.month < 1 ||
        budget.month > 12 ||
        budget.year < 1900 ||
        budget.year > 9999 ||
        !budget.amount.isFinite ||
        budget.amount <= 0 ||
        !const ['INR', 'USD'].contains(budget.currency)) {
      throw ArgumentError('Enter a valid month, year and positive budget.');
    }
    return _change(() async {
      final db = ref.read(localStoreProvider).db;
      await db
          .into(db.monthlyBudgetsTable)
          .insertOnConflictUpdate(
            MonthlyBudgetsTableCompanion.insert(
              id: budget.key,
              year: budget.year,
              month: budget.month,
              currencyCode: budget.currency,
              budget: Value(budget.amount),
            ),
          );
    });
  }

  Future<void> delete(MonthlyBudget budget) => _change(() async {
    final db = ref.read(localStoreProvider).db;
    // Retain the month and its foreign-key references when deleting its budget.
    await (db.update(db.monthlyBudgetsTable)
          ..where((row) => row.id.equals(budget.key)))
        .write(const MonthlyBudgetsTableCompanion(budget: Value(-1)));
  });
}
