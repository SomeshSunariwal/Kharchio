import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/categories.dart';
import '../core/expense_store.dart';
import '../core/preferences.dart';
import '../core/theme.dart';
import 'app_notification.dart';
import 'swipe_delete_expense.dart';

/// Keeps page controls outside the scrolling content without a fixed height.
class FixedHeaderPage extends StatelessWidget {
  final Widget header;
  final Widget child;
  final EdgeInsets headerPadding;

  const FixedHeaderPage({
    super.key,
    required this.header,
    required this.child,
    this.headerPadding = const EdgeInsets.fromLTRB(14, 6, 14, 12),
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: headerPadding, child: header),
      Expanded(child: child),
    ],
  );
}

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

const settingsListRowHeight = 52.0;
const settingsPageContentPadding = EdgeInsets.fromLTRB(14, 6, 14, 6);

/// Common settings-page frame; the content owns its loading and list states.
class PlannerPage extends StatelessWidget {
  const PlannerPage({
    super.key,
    required this.title,
    required this.child,
    required this.addLabel,
    required this.onAdd,
  });
  final String title, addLabel;
  final Widget child;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              Expanded(child: child),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(addLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shared equal-width dialog actions used by planner and renewal forms.
class DialogActionRow extends StatelessWidget {
  const DialogActionRow({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.secondaryLabel = 'Cancel',
    this.primaryIcon,
  });
  final Widget primaryLabel;
  final Widget? primaryIcon;
  final VoidCallback? onPrimary, onSecondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onSecondary,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: shape,
              side: BorderSide(color: context.appColors.line),
              foregroundColor: context.appColors.ink,
            ),
            child: Text(secondaryLabel),
          ),
        ),
        Expanded(
          child: FilledButton.icon(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: shape,
            ),
            icon: primaryIcon,
            label: primaryLabel,
          ),
        ),
      ],
    );
  }
}

class SettingsRowLabel extends StatelessWidget {
  const SettingsRowLabel(
    this.title,
    this.description, {
    super.key,
    this.descriptionError = false,
    this.descriptionMaxLines = 2,
  });

  final String title;
  final String description;
  final bool descriptionError;
  final int descriptionMaxLines;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(
        description,
        maxLines: descriptionMaxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: descriptionError ? red : context.appColors.muted,
        ),
      ),
    ],
  );
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Clip clipBehavior;
  const SurfaceCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.clipBehavior = Clip.none,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: clipBehavior,
    decoration: BoxDecoration(
      color: color ?? context.appColors.surface,
      borderRadius: borderRadius,
      border: Border.all(color: context.appColors.line),
    ),
    child: child,
  );
}

/// A fixed rounded frame with rows that scroll inside it.
class ScrollableListCard extends StatelessWidget {
  const ScrollableListCard({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      // Follow the inner edge of SurfaceCard's 1 px border.
      borderRadius: BorderRadius.circular(21),
      child: ListView.separated(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: context.appColors.line),
      ),
    ),
  );
}

/// The transaction viewport connects to navigation and rounds only its top.
class ConnectedListCard extends StatelessWidget {
  static const corners = BorderRadius.vertical(top: Radius.circular(22));
  final Widget child;
  const ConnectedListCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(1),
    borderRadius: corners,
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.hardEdge,
      child: child,
    ),
  );
}

class TransactionList extends StatelessWidget {
  const TransactionList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.empty,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget empty;
  final EdgeInsetsGeometry padding;

  Widget _divider(BuildContext context, int index) => Divider(
    height: 1,
    indent: 10,
    endIndent: 10,
    color: context.appColors.line,
  );

  @override
  Widget build(BuildContext context) {
    return ConnectedListCard(
      child: itemCount == 0
          ? empty
          : ListView.separated(
              padding: padding,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              separatorBuilder: _divider,
            ),
    );
  }
}

class CategoryIcon extends StatelessWidget {
  final String? category;
  final IconData? icon;
  final Color? color;
  final double size;
  const CategoryIcon(String this.category, {super.key, this.size = 48})
    : icon = null,
      color = null;
  const CategoryIcon.renewal({super.key, this.size = 48})
    : category = null,
      icon = Icons.autorenew_rounded,
      color = green;
  @override
  Widget build(BuildContext context) {
    final i = category == null ? 0 : context.categoryIndex(category!);
    final tint = color ?? context.categoryColors[i];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        icon ?? context.categoryIcons[i],
        color: tint,
        size: size * .52,
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onTap;
  final String? subscriptionName;
  final bool _isRenewal;
  const ExpenseTile(
    this.expense, {
    super.key,
    this.onTap,
    this.subscriptionName,
  }) : _isRenewal = false;

  const ExpenseTile.renewal(this.expense, {super.key, this.onTap})
    : _isRenewal = true,
      subscriptionName = null;

  @override
  Widget build(BuildContext context) {
    final color = _isRenewal
        ? green
        : context.categoryColors[context.categoryIndex(expense.category)];
    final textColor = context.appColors.dark
        ? Color.lerp(color, Colors.white, .32)!
        : color;
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    _isRenewal
                        ? 'Due'
                        : DateFormat('hh:mm a').format(expense.date),
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            _isRenewal
                ? const CategoryIcon.renewal(size: 30)
                : CategoryIcon(expense.category, size: 30),
            SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  SizedBox(height: 3),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _isRenewal
                          ? 'Subscription'
                          : subscriptionName == null
                          ? '${expense.isRefund ? 'Refund' : 'Expense'} · ${expense.category}'
                          : 'Subscription · $subscriptionName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 5),
            TransactionAmount(
              amount: expense.amount,
              isRefund: expense.isRefund,
              description: _isRenewal ? 'Subscription amount due' : null,
            ),
            Icon(Icons.chevron_right, color: context.appColors.muted, size: 16),
          ],
        ),
      ),
    );
    return _isRenewal
        ? Material(
            color: context.appColors.surface,
            clipBehavior: Clip.antiAlias,
            child: row,
          )
        : SwipeDeleteExpense(
            key: ValueKey(expense.id),
            expense: expense,
            child: row,
          );
  }
}

/// Direction icons distinguish outgoing expenses from incoming refunds.
class TransactionAmount extends StatelessWidget {
  final double amount;
  final bool isRefund;
  final String? formattedAmount;
  final String? description;
  const TransactionAmount({
    super.key,
    required this.amount,
    required this.isRefund,
    this.formattedAmount,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final color = isRefund ? green : red;
    final text = formattedAmount ?? context.money(amount);
    return Semantics(
      label:
          '${description ?? (isRefund ? 'Refund received' : 'Expense paid')} $text',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRefund ? Icons.south_west : Icons.north_east,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

void notice(BuildContext context, String message, {bool isError = false}) =>
    showAppNotification(context, message, isError: isError);
