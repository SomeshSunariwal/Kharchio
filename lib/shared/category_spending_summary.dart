import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../core/theme.dart';

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
