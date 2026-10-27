import '../core/preferences.dart';
import '../core/categories.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/preview_data.dart';
import 'swipe_delete_expense.dart';

class AppIcon extends StatelessWidget {
  final double size;
  const AppIcon({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/kharchio_icon.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
    semanticLabel: 'Kharchio app icon',
  );
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  const SurfaceCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.appColors.surface,
      borderRadius: borderRadius,
      border: Border.all(color: context.appColors.line),
    ),
    child: child,
  );
}

/// The transaction viewport connects to navigation and rounds only its top.
class ConnectedListCard extends StatelessWidget {
  final Widget child;
  const ConnectedListCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(1),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.hardEdge,
      child: child,
    ),
  );
}

class CategoryIcon extends StatelessWidget {
  final String category;
  final double size;
  const CategoryIcon(this.category, {super.key, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final i = context.categoryIndex(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.categoryColors[i].withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        context.categoryIcons[i],
        color: context.categoryColors[i],
        size: size * .52,
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onTap;
  const ExpenseTile(this.expense, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final color =
        context.categoryColors[context.categoryIndex(expense.category)];
    final textColor = context.appColors.dark
        ? Color.lerp(color, Colors.white, .32)!
        : color;
    return SwipeDeleteExpense(
      key: ValueKey(expense.id),
      expense: expense,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd MMM yy').format(expense.date),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      DateFormat('hh:mm a').format(expense.date),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              CategoryIcon(expense.category, size: 30),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 3),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        expense.category,
                        style: TextStyle(color: textColor, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 5),
              Text(
                context.money(expense.amount),
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.appColors.muted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void notice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
