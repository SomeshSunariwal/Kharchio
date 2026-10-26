import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/preferences.dart';
import '../core/preview_data.dart';
import '../core/theme.dart';
import 'category_donut.dart';
import 'widgets.dart';

/// Analysis shares the exact donut layout and labels used by Dashboard.
class CategoryPieChart extends StatelessWidget {
  final List<Expense> expenses;
  final int? selectedIndex;
  final ValueChanged<int>? onCategorySelected;
  const CategoryPieChart({
    super.key,
    required this.expenses,
    this.selectedIndex,
    this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final totals = context.expenseCategories
        .map(
          (category) => expenses
              .where((expense) => expense.category == category.name)
              .fold<double>(0, (sum, expense) => sum + expense.amount),
        )
        .toList();
    final total = totals.fold<double>(0, (sum, amount) => sum + amount);
    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      color: context.appColors.dark
          ? context.appColors.surface
          : context.appColors.tint,
      child: Column(
        children: [
          CategorySpendingSummary(total: total),
          const SizedBox(height: 4),
          total > 0
              ? CategoryDonut(
                  totals: totals,
                  selectedIndex: selectedIndex,
                  onCategorySelected: onCategorySelected,
                )
              : SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'No expenses in this period',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class CategorySpendingSummary extends StatelessWidget {
  final double total;
  const CategorySpendingSummary({super.key, required this.total});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Total Spent',
        style: TextStyle(fontSize: 11, color: context.appColors.muted),
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          context.money(total),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}
