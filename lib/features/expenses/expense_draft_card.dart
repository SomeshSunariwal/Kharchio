import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/categories.dart';
import '../../core/expense.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/widgets.dart';

class ExpenseDraft {
  final String id;
  final TextEditingController title, description, amount;
  String category;
  TransactionType type;
  String? originalExpenseId;
  DateTime? date;
  ExpenseDraft({
    String? id,
    String title = '',
    String description = '',
    String amount = '',
    this.category = 'Groceries',
    this.type = TransactionType.expense,
    this.originalExpenseId,
    this.date,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       title = TextEditingController(text: title),
       description = TextEditingController(text: description),
       amount = TextEditingController(
         text: double.tryParse(amount)?.toStringAsFixed(2) ?? amount,
       );
  void formatAmount() {
    final value = double.tryParse(amount.text);
    if (value != null && value.isFinite) {
      amount.text = value.toStringAsFixed(2);
    }
  }

  void dispose() {
    title.dispose();
    description.dispose();
    amount.dispose();
  }
}

class ExpenseDraftCard extends StatelessWidget {
  const ExpenseDraftCard({
    super.key,
    required this.d,
    required this.categories,
    required this.currency,
    required this.onCategoryChanged,
    this.editable = true,
    this.shimmer,
    this.onTypeChanged,
    this.onRemove,
    this.additionalFields = const [],
    this.expenseLabel = 'Expense',
    this.allowRefund = true,
    this.linkMode = false,
    this.onLinkModeChanged,
    this.linkFields = const [],
  });

  final ExpenseDraft d;
  final List<ExpenseCategory> categories;
  final AppCurrency currency;
  final ValueChanged<String> onCategoryChanged;
  final bool editable;
  final Animation<double>? shimmer;
  final ValueChanged<TransactionType>? onTypeChanged;
  final VoidCallback? onRemove;
  final List<Widget> additionalFields;
  final String expenseLabel;
  final bool allowRefund;
  final bool linkMode;
  final ValueChanged<bool>? onLinkModeChanged;
  final List<Widget> linkFields;

  Widget _field(BuildContext context, Widget child) => CustomPaint(
    foregroundPainter: shimmer == null
        ? null
        : _FieldShimmerPainter(
            shimmer!,
            green.withValues(alpha: context.appColors.dark ? .20 : .12),
          ),
    child: child,
  );

  InputDecoration _input(BuildContext context, String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(fontSize: 12, color: context.appColors.muted),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );

  @override
  Widget build(BuildContext context) {
    final hasSecondTab = allowRefund || onLinkModeChanged != null;
    final selectedRight = onLinkModeChanged != null
        ? linkMode
        : d.type == TransactionType.refund;
    final ValueChanged<bool>? onTabChanged = !editable
        ? null
        : onLinkModeChanged ??
              (onTypeChanged == null
                  ? null
                  : (right) => onTypeChanged!(
                      right ? TransactionType.refund : TransactionType.expense,
                    ));
    return SurfaceCard(
      key: ValueKey(d.id),
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: hasSecondTab ? 210 : 110,
                    ),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: context.appColors.line.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: AnimatedAlign(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            curve: Curves.easeInOutCubic,
                            alignment: selectedRight
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: hasSecondTab ? .5 : 1,
                              heightFactor: 1,
                              child: AnimatedContainer(
                                key: ValueKey(
                                  'transaction-type-highlight-${d.id}',
                                ),
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                curve: Curves.easeInOutCubic,
                                decoration: BoxDecoration(
                                  color: selectedRight ? green : red,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: context.appColors.dark
                                            ? .2
                                            : .12,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _typeTab(
                              context,
                              expenseLabel,
                              Icons.north_east,
                              red,
                              selected: !selectedRight,
                              onTap: onTabChanged == null
                                  ? null
                                  : () => onTabChanged(false),
                            ),
                            if (hasSecondTab)
                              _typeTab(
                                context,
                                onLinkModeChanged != null ? 'Link' : 'Refund',
                                onLinkModeChanged != null
                                    ? Icons.link_rounded
                                    : Icons.south_west,
                                green,
                                selected: selectedRight,
                                onTap: onTabChanged == null
                                    ? null
                                    : () => onTabChanged(true),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: d.type == TransactionType.refund
                    ? 'Remove refund card'
                    : 'Remove expense card',
                style: IconButton.styleFrom(foregroundColor: red),
                visualDensity: VisualDensity.compact,
                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: Icon(Icons.delete_outline, size: 18),
                color: red,
              ),
            ],
          ),
          SizedBox(height: 10),
          if (linkMode)
            ...linkFields
          else ...[
            _field(
              context,
              TextFormField(
                controller: d.title,
                enabled: editable,
                style: TextStyle(fontSize: 12),
                textCapitalization: TextCapitalization.sentences,
                decoration: _input(context, 'Title'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a title' : null,
              ),
            ),
            SizedBox(height: 8),
            _field(
              context,
              TextFormField(
                controller: d.description,
                enabled: editable,
                style: TextStyle(fontSize: 12),
                minLines: 1,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: _input(
                  context,
                  'Description (optional)',
                  hint: 'Add a note…',
                ),
              ),
            ),
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    context,
                    AppDropdown<String>(
                      value: d.category,
                      label: 'Category',
                      enabled: editable,
                      leadingIcon: categories
                          .where((c) => c.name == d.category)
                          .firstOrNull
                          ?.icon,
                      scrollIntoViewOnOpen: true,
                      options: [
                        for (final category in categories)
                          AppDropdownOption(
                            category.name,
                            category.name,
                            icon: category.icon,
                          ),
                      ],
                      onChanged: onCategoryChanged,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _field(
                    context,
                    Focus(
                      onFocusChange: (focused) {
                        if (!focused) d.formatAmount();
                      },
                      child: TextFormField(
                        controller: d.amount,
                        enabled: editable,
                        style: TextStyle(
                          fontSize: 13,
                          color: d.type == TransactionType.refund ? green : red,
                        ),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            _input(
                              context,
                              'Amount (${currency.symbol})',
                              hint: '0.00',
                            ).copyWith(
                              prefixIcon: Icon(
                                d.type == TransactionType.refund
                                    ? Icons.south_west
                                    : Icons.north_east,
                                size: 16,
                                color: d.type == TransactionType.refund
                                    ? green
                                    : red,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 36,
                              ),
                            ),
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (oldValue, newValue) =>
                                RegExp(r'^\d{0,10}(\.\d{0,2})?$')
                                    .hasMatch(newValue.text)
                                ? newValue
                                : oldValue,
                          ),
                        ],
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return n == null || !n.isFinite || n <= 0
                              ? 'Invalid amount'
                              : null;
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ...additionalFields,
          ],
        ],
      ),
    );
  }

  Widget _typeTab(
    BuildContext context,
    String label,
    IconData icon,
    Color color, {
    required bool selected,
    VoidCallback? onTap,
  }) {
    final foreground = selected
        ? (color == red ? Colors.white : const AppColors(false).ink)
        : color;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldShimmerPainter extends CustomPainter {
  _FieldShimmerPainter(this.animation, this.highlight)
    : super(repaint: animation);

  final Animation<double> animation;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Rect.fromLTWH(
      size.width * (animation.value * 1.4 - .4),
      0,
      size.width * .4,
      size.height,
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          highlight.withValues(alpha: 0),
          highlight,
          highlight.withValues(alpha: 0),
        ],
      ).createShader(band);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FieldShimmerPainter oldDelegate) =>
      animation != oldDelegate.animation || highlight != oldDelegate.highlight;
}
