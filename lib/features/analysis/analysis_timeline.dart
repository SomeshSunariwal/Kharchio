import '../../core/expense.dart';

enum AnalysisPeriod { year, month, day }

/// Non-cumulative category spending, grouped into complete calendar/time buckets.
/// Integer minor units keep aggregation consistent with the SQLite ledger.
class AnalysisTimeline {
  final AnalysisPeriod period;
  final DateTime date;
  final int bucketCount;
  final Map<String, List<double>> byCategory;

  AnalysisTimeline({
    required Iterable<Expense> expenses,
    required this.period,
    required this.date,
    required String currencyCode,
  }) : bucketCount = _bucketCount(period, date),
       byCategory = _aggregate(expenses, period, date, currencyCode);

  static int _bucketCount(AnalysisPeriod period, DateTime date) =>
      switch (period) {
        AnalysisPeriod.year => 12,
        AnalysisPeriod.month => DateTime(date.year, date.month + 1, 0).day,
        AnalysisPeriod.day => 24,
      };

  static Map<String, List<double>> _aggregate(
    Iterable<Expense> expenses,
    AnalysisPeriod period,
    DateTime date,
    String currency,
  ) {
    final count = _bucketCount(period, date);
    final amounts = <String, List<int>>{};
    for (final expense in expenses) {
      if (expense.currencyCode != currency ||
          expense.year != date.year ||
          (period != AnalysisPeriod.year && expense.month != date.month) ||
          (period == AnalysisPeriod.day && expense.date.day != date.day)) {
        continue;
      }
      final bucket = switch (period) {
        AnalysisPeriod.year => expense.month - 1,
        AnalysisPeriod.month => expense.date.day - 1,
        AnalysisPeriod.day => expense.date.hour,
      };
      final values = amounts.putIfAbsent(
        expense.category,
        () => List.filled(count, 0),
      );
      values[bucket] += (expense.amount * 100).round();
    }
    return Map.unmodifiable({
      for (final entry in amounts.entries)
        entry.key: List<double>.unmodifiable(
          entry.value.map((minor) => minor / 100),
        ),
    });
  }
}
