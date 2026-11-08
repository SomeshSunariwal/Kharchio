import 'expense.dart';

/// Shared, single-pass totals for charts, calendars and month cards.
class ExpenseSummary {
  factory ExpenseSummary(Iterable<Expense> values) {
    final expenses = List<Expense>.unmodifiable(values);
    var total = 0.0;
    var paymentsTotal = 0.0;
    var refundsTotal = 0.0;
    final byCategory = <String, double>{};
    final byMonth = <int, double>{};
    final byDay = <int, double>{};
    for (final expense in expenses) {
      final impact = expense.spendingImpact;
      total += impact;
      if (expense.isRefund) {
        refundsTotal += expense.amount;
      } else {
        paymentsTotal += expense.amount;
      }
      byCategory.update(
        expense.category,
        (v) => v + impact,
        ifAbsent: () => impact,
      );
      byMonth.update(
        expense.month,
        (v) => v + impact,
        ifAbsent: () => impact,
      );
      byDay.update(
        expense.date.day,
        (v) => v + impact,
        ifAbsent: () => impact,
      );
    }
    return ExpenseSummary._(
      expenses,
      total,
      paymentsTotal,
      refundsTotal,
      Map.unmodifiable(byCategory),
      Map.unmodifiable(byMonth),
      Map.unmodifiable(byDay),
    );
  }

  const ExpenseSummary._(
    this.expenses,
    this.total,
    this.paymentsTotal,
    this.refundsTotal,
    this.byCategory,
    this.byMonth,
    this.byDay,
  );
  final List<Expense> expenses;
  final double total;
  final double paymentsTotal;
  final double refundsTotal;
  final Map<String, double> byCategory;
  final Map<int, double> byMonth;
  final Map<int, double> byDay;

  double categoryTotal(String name) => byCategory[name] ?? 0;
}
