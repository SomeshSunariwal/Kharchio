import 'expense.dart';

/// Shared, single-pass totals for charts, calendars and month cards.
class ExpenseSummary {
  factory ExpenseSummary(Iterable<Expense> values) {
    final expenses = List<Expense>.unmodifiable(values);
    var total = 0.0;
    final byCategory = <String, double>{};
    final byMonth = <int, double>{};
    final byDay = <int, double>{};
    for (final expense in expenses) {
      total += expense.amount;
      byCategory.update(
        expense.category,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
      byMonth.update(
        expense.date.month,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
      byDay.update(
        expense.date.day,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    return ExpenseSummary._(
      expenses,
      total,
      Map.unmodifiable(byCategory),
      Map.unmodifiable(byMonth),
      Map.unmodifiable(byDay),
    );
  }

  const ExpenseSummary._(
    this.expenses,
    this.total,
    this.byCategory,
    this.byMonth,
    this.byDay,
  );
  final List<Expense> expenses;
  final double total;
  final Map<String, double> byCategory;
  final Map<int, double> byMonth;
  final Map<int, double> byDay;

  double categoryTotal(String name) => byCategory[name] ?? 0;
}
