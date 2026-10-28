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
  final String label;
  final bool overBudget;
  final double? budget;
  const CategorySpendingSummary({
    super.key,
    required this.total,
    this.label = 'Total Spent',
    this.overBudget = false,
    this.budget,
  });

  @override
  Widget build(BuildContext context) {
    if (budget == null) {
      return _SummaryAmountCard(label: label, amount: total);
    }
    final color = overBudget ? red : green;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _SummaryAmountCard(label: 'Set Budget', amount: budget!),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryAmountCard(
            label: label,
            amount: total.abs(),
            accent: color,
          ),
        ),
      ],
    );
  }
}

class _SummaryAmountCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color? accent;
  const _SummaryAmountCard({
    required this.label,
    required this.amount,
    this.accent,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color:
          accent?.withValues(alpha: context.appColors.dark ? .12 : .07) ??
          context.appColors.field,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: accent?.withValues(alpha: .3) ?? context.appColors.line,
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: accent ?? context.appColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            context.money(amount),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: accent ?? context.appColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
