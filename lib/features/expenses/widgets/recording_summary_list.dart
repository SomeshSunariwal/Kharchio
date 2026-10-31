import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../services/ai/expense_extractor.dart';
import '../../../shared/widgets.dart';

class RecordingSummaryList extends StatelessWidget {
  const RecordingSummaryList({
    super.key,
    required this.expenses,
    required this.scroll,
  });
  final List<ExtractedExpense> expenses;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: ListView.separated(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            itemCount: expenses.length,
            separatorBuilder: (context, i) =>
                Divider(height: 1, color: colors.line),
            itemBuilder: (context, i) {
              final expense = expenses[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: expense.isRefund ? 'Refund' : 'Expense',
                      child: Container(
                        key: ValueKey('review-type-$i'),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (expense.isRefund ? green : red).withValues(
                            alpha: .08,
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          expense.isRefund
                              ? Icons.south_west
                              : Icons.north_east,
                          color: expense.isRefund ? green : red,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            expense.description.isEmpty
                                ? 'No description'
                                : expense.description,
                            style: TextStyle(fontSize: 11, color: colors.muted),
                          ),
                          Text(
                            '${expense.isRefund ? 'Refund' : 'Expense'} · ${expense.category}',
                            style: TextStyle(fontSize: 10, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TransactionAmount(
                      amount: expense.amount,
                      isRefund: expense.isRefund,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
