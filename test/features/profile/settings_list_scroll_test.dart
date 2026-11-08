import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/categories.dart';
import 'package:kharchio/core/monthly_budgets.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/features/profile/budget_planner_screen.dart';
import 'package:kharchio/features/profile/categories_screen.dart';
import 'package:kharchio/shared/widgets.dart';

class _TestCategories extends CategoriesStore {
  @override
  List<ExpenseCategory> build() => [
    for (var i = 0; i < 24; i++)
      ExpenseCategory('Category $i', 0xFF00AE87, 'other'),
  ];
}

class _TestBudgets extends MonthlyBudgets {
  @override
  Future<List<MonthlyBudget>> build() async => [
    for (var i = 0; i < 24; i++)
      MonthlyBudget(
        year: 2025 + i ~/ 12,
        month: i % 12 + 1,
        amount: 100,
        currency: 'INR',
      ),
  ];
}

void main() {
  final screens = [
    (
      page: const CategoriesScreen(),
      firstRow: 'Category 0',
      description: 'Choose categories when adding expenses.',
      action: 'Add Category',
    ),
    (
      page: const BudgetPlannerScreen(),
      firstRow: 'January 2025',
      description: 'Set a spending budget for each month.',
      action: 'Add Budget',
    ),
  ];

  for (final screen in screens) {
    testWidgets('${screen.action} stays fixed as list rows scroll', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesProvider.overrideWith(_TestCategories.new),
            monthlyBudgetsProvider.overrideWith(_TestBudgets.new),
          ],
          child: MaterialApp(theme: appTheme(), home: screen.page),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byType(ScrollableListCard);
      final description = find.textContaining(screen.description);
      final action = find.text(screen.action);
      final firstRow = find.text(screen.firstRow).hitTestable();
      final cardBounds = tester.getRect(card);
      final descriptionBounds = tester.getRect(description);
      final actionBounds = tester.getRect(action);
      expect(firstRow, findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();

      expect(firstRow, findsNothing);
      expect(tester.getRect(card), cardBounds);
      expect(tester.getRect(description), descriptionBounds);
      expect(tester.getRect(action), actionBounds);
    });
  }
}
