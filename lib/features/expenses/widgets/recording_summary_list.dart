import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/preferences.dart';
import '../../../services/ai/expense_extractor.dart';

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
                    Text(
                      '${i + 1}.',
                      style: TextStyle(fontSize: 12, color: colors.muted),
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
                            expense.category,
                            style: TextStyle(fontSize: 10, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.money(expense.amount),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
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
