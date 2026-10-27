import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_summary.dart';
import 'preview_data.dart';

typedef ExpensePeriod = ({int year, int? month, int? day, String currencyCode});

/// Cached by period. Search, category selection and animation rebuilds reuse
/// these results; expense mutations invalidate the derived summaries.
final expenseSummaryProvider = Provider.autoDispose
    .family<ExpenseSummary, ExpensePeriod>(_summarize);

ExpenseSummary _summarize(Ref ref, ExpensePeriod period) {
  final values = period.month == null
      ? ref
            .watch(expensesProvider)
            .where(
              (e) =>
                  e.date.year == period.year &&
                  e.currencyCode == period.currencyCode,
            )
      : ref
            .watch(
              expenseSummaryProvider((
                year: period.year,
                month: period.day == null ? null : period.month,
                day: null,
                currencyCode: period.currencyCode,
              )),
            )
            .expenses;
  final filtered = values
      .where(
        (e) =>
            (period.month == null || e.date.month == period.month) &&
            (period.day == null || e.date.day == period.day),
      )
      .toList();
  if (period.day != null) filtered.sort((a, b) => b.date.compareTo(a.date));
  return ExpenseSummary(filtered);
}
