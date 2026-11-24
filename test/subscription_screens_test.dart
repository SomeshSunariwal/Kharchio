import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kharchio/core/categories.dart';
import 'package:kharchio/core/monthly_budgets.dart';
import 'package:kharchio/features/profile/budget_planner_screen.dart';
import 'package:kharchio/core/expense_store.dart';
import 'package:kharchio/core/planning_years.dart';
import 'package:kharchio/core/subscriptions.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/database/subscription_store.dart';
import 'package:kharchio/features/analysis/analysis_screen.dart';
import 'package:kharchio/features/expenses/expense_draft_card.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/features/profile/subscription_planner_screen.dart';
import 'package:kharchio/features/profile/categories_screen.dart';
import 'package:kharchio/features/profile/renew_subscription_popup.dart';
import 'package:kharchio/services/notifications/subscription_reminders.dart';
import 'package:kharchio/shared/app_dropdown.dart';
import 'package:kharchio/shared/category_donut.dart';
import 'package:kharchio/shared/category_spending_summary.dart';
import 'package:kharchio/shared/modern_date_picker.dart';
import 'package:kharchio/shared/widgets.dart'
    show ConnectedListCard, ExpenseTile, ScrollableListCard, TransactionList;

import 'subscriptions_test.dart' show plan, payment;

class _Expenses extends ExpenseStore {
  final List<Expense> expenses;
  _Expenses(this.expenses);
  @override
  List<Expense> build() => expenses;
}

class _Budgets extends MonthlyBudgets {
  @override
  Future<List<MonthlyBudget>> build() async => const [
    MonthlyBudget(year: 2026, month: 11, amount: 100, currency: 'INR'),
  ];
}

class _Categories extends CategoriesStore {
  @override
  List<ExpenseCategory> build() => defaultCategories;
}

class _RenewalStore implements SubscriptionStore {
  _RenewalStore(this.onSaved, {this.onSkipped, this.onLinked});
  final void Function(Expense, String, int) onSaved;
  final void Function(String, int)? onSkipped;
  final void Function(String, Map<int, String>)? onLinked;

  @override
  Future<void> link(String id, Map<int, String> expenses) async =>
      onLinked?.call(id, expenses);

  @override
  Future<void> skip(String id, int day) async => onSkipped?.call(id, day);

  @override
  Future<void> saveAndLink(Expense expense, String planId, int day) async {
    onSaved(expense, planId, day);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void usePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'subscription planner rows match the rendered Categories row height',
    (tester) async {
      usePhone(tester);
      Widget screen(Widget child) => ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(_Categories.new),
          monthlyBudgetsProvider.overrideWith(_Budgets.new),
          subscriptionsProvider.overrideWith(
            (ref) => Stream.value(SubscriptionState([plan], [])),
          ),
          subscriptionAlertPermissionProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(theme: appTheme(), home: child),
      );
      void expectIntroSpacing(String intro) {
        final bounds = tester.getRect(find.textContaining(intro));
        expect(bounds.top - tester.getBottomLeft(find.byType(AppBar)).dy, 6);
        expect(
          tester.getTopLeft(find.byType(ScrollableListCard)).dy - bounds.bottom,
          12,
        );
      }

      await tester.pumpWidget(screen(const CategoriesScreen()));
      await tester.pumpAndSettle();
      expectIntroSpacing('Choose categories');
      final categoryHeight = tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Education'),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .height;
      await tester.pumpWidget(screen(const SubscriptionPlannerScreen()));
      await tester.pumpAndSettle();
      expectIntroSpacing('Set up recurring payments');
      final subscriptionHeight = tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Spotify'),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .height;
      expect(subscriptionHeight, categoryHeight);
      final cardBounds = tester.getRect(find.byType(ScrollableListCard));
      final selectionBounds = tester.getRect(
        find
            .ancestor(of: find.text('Spotify'), matching: find.byType(InkWell))
            .first,
      );
      expect(selectionBounds.left, cardBounds.left + 1);
      expect(selectionBounds.right, cardBounds.right - 1);
      expect(selectionBounds.top, cardBounds.top + 1);

      await tester.tap(find.text('Spotify'));
      await tester.pumpAndSettle();
      final reminder = find.byWidgetPredicate(
        (w) => w is AppDropdown<int> && w.label == 'Renewal reminder',
      );
      expect(
        tester.widget<AppDropdown<int>>(reminder).value,
        plan.reminderDays,
      );
      expect(
        find.textContaining('Reminders use the selected renewal time'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(const BudgetPlannerScreen()));
      await tester.pumpAndSettle();
      expectIntroSpacing('Set a spending budget');
      expect(
        tester.getSize(find.byType(ListTile).first).height,
        categoryHeight,
      );
    },
  );

  testWidgets('Skip closes the renewal popup without recording a payment', (
    tester,
  ) async {
    var skipped = false;
    var saved = false;
    final store = _RenewalStore(
      (_, _, _) => saved = true,
      onSkipped: (id, day) {
        skipped = id == plan.id && day == plan.anchorDay;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(_Categories.new),
          subscriptionStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRenewSubscriptionPopup(context, (
                  plan: plan,
                  dueDay: plan.anchorDay,
                )),
                child: const Text('Open renewal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open renewal'));
    await tester.pumpAndSettle();
    expect(find.text('Refund'), findsNothing);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(skipped, isTrue);
    expect(saved, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets(
    'Link searches the chosen month and reuses the existing payment',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.now();
      final previous = DateTime(now.year, now.month - 1, 5);
      final expenses = [
        payment('current', now, title: 'Current payment'),
        payment('previous', previous, title: 'Spotify old payment', amount: 99),
        payment('other', previous, title: 'Groceries'),
        payment('linked', previous, title: 'Already linked'),
        payment('usd', previous, title: 'USD payment', currency: 'USD'),
        Expense(
          id: 'refund',
          title: 'Refund payment',
          category: 'Others',
          amount: 99,
          date: previous,
          currencyCode: 'INR',
          type: TransactionType.refund,
        ),
      ];
      Map<int, String>? linked;
      var saved = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesProvider.overrideWith(_Categories.new),
            expensesProvider.overrideWith(() => _Expenses(expenses)),
            subscriptionsProvider.overrideWith(
              (ref) => Stream.value(
                SubscriptionState(
                  [plan],
                  [
                    SubscriptionRenewal(
                      planId: plan.id,
                      dueDay: plan.anchorDay,
                      skipped: false,
                      expenseId: 'linked',
                    ),
                  ],
                ),
              ),
            ),
            subscriptionStoreProvider.overrideWithValue(
              _RenewalStore(
                (_, _, _) => saved = true,
                onLinked: (id, links) {
                  expect(id, plan.id);
                  linked = links;
                },
              ),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: RenewSubscriptionPopup(
                renewal: (plan: plan, dueDay: plan.anchorDay + 100),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      final month = find.byWidgetPredicate(
        (w) => w is AppDropdown<int> && w.label == 'Payment month',
      );
      final picker = find.byWidgetPredicate(
        (w) => w is AppDropdown<String> && w.label == 'Expense to link',
      );
      expect(
        tester.widget<AppDropdown<String>>(picker).options.map((o) => o.value),
        ['current'],
      );
      await tester.tap(month);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppDropdown<String>>(picker)
            .options
            .map((o) => o.value)
            .toSet(),
        {'previous', 'other'},
      );
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'groceries');
      await tester.pumpAndSettle();
      expect(find.textContaining('Groceries'), findsOneWidget);
      expect(find.textContaining('Spotify old payment'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pumpAndSettle();
      expect(find.textContaining('Groceries'), findsOneWidget);
      expect(find.textContaining('Spotify old payment'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'spotify');
      await tester.pumpAndSettle();
      expect(find.textContaining('Groceries'), findsNothing);
      await tester.tap(find.textContaining('Spotify old payment').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link payment'));
      await tester.pumpAndSettle();
      expect(linked, {plan.anchorDay + 100: 'previous'});
      expect(saved, isFalse);
      expect(expenses[1].date, previous);
      expect(expenses[1].amount, 99);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standard expense card retains Expense and Refund tabs', (
    tester,
  ) async {
    final draft = ExpenseDraft();
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ExpenseDraftCard(
              d: draft,
              categories: defaultCategories,
              currency: AppCurrency.values.firstWhere((c) => c.code == 'INR'),
              onCategoryChanged: (value) =>
                  update(() => draft.category = value),
              onTypeChanged: (value) => update(() => draft.type = value),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Link'), findsNothing);
    expect(find.text('Title'), findsOneWidget);
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(draft.type, TransactionType.refund);
    expect(find.text('Title'), findsOneWidget);
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    expect(draft.type, TransactionType.expense);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense day view hides the analysis view selector', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(_Categories.new),
          expensesProvider.overrideWith(() => _Expenses([])),
          subscriptionsProvider.overrideWith(
            (ref) => Stream.value(SubscriptionState([], [])),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(),
          home: const Scaffold(body: AnalysisScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jan'));
    await tester.pumpAndSettle();
    expect(find.text('Your Days at a glance'), findsOneWidget);
    await tester.ensureVisible(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppDropdown && w.label == 'Analysis view',
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Back to days'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is AppDropdown && w.label == 'Analysis view',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renewal date picker blocks earlier months through navigation and year selection',
    (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ModernDatePicker(
              initialDate: DateTime(2026, 10, 15),
              firstDate: DateTime(2026, 11),
              includeTime: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sun, 1 Nov 2026'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Previous month',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Previous month',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Previous month',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-month-selector')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<YearPicker>(find.byType(YearPicker)).firstDate,
        DateTime(2026, 11),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expense date picker keeps its compact calendar and inline actions',
    (tester) async {
      Widget calendar(double scale) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ModernDatePicker(initialDate: DateTime(2026, 11, 23)),
        ),
      );
      await tester.pumpWidget(calendar(1));
      await tester.pumpAndSettle();
      expect(find.text('Select date'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Previous month',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Hour'), findsNothing);
      expect(tester.getSize(find.byType(GridView)).height, 200);
      expect(
        tester.getCenter(find.text('Today')).dy,
        tester.getCenter(find.text('Apply')).dy,
      );
      final selector = find.byKey(const ValueKey('calendar-month-selector'));
      final width = tester.getSize(selector).width;
      await tester.pumpWidget(calendar(0.75));
      await tester.pumpAndSettle();
      expect(tester.getSize(selector).width, lessThan(width));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renewal list fills the viewport below its header', (
    tester,
  ) async {
    usePhone(tester);
    for (final count in [0, 1]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              itemCount: count,
              itemBuilder: (_, _) => const SizedBox(height: 48),
              empty: const Center(child: Text('No upcoming renewals')),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(TransactionList)).height, 800);
      expect(find.byType(CustomScrollView), findsNothing);
    }
  });

  testWidgets(
    'transaction rows scroll inside the fixed rounded dashboard card',
    (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionList(
              itemCount: 30,
              itemBuilder: (_, index) =>
                  SizedBox(height: 60, child: Text('Renewal $index')),
              empty: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      final bounds = tester.getRect(find.byType(ConnectedListCard));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ConnectedListCard)), bounds);
      expect(find.text('Renewal 0').hitTestable(), findsNothing);
      expect(find.text('Renewal 8').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('planner offers a reminder lead time up to seven days', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionsProvider.overrideWith(
            (ref) => Stream.value(SubscriptionState([plan], [])),
          ),
          subscriptionAlertPermissionProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          theme: appTheme(),
          home: const SubscriptionPlannerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final addButton = find.ancestor(
      of: find.text('Add Subscription'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      tester.getSize(addButton).width,
      tester.getSize(find.byType(ScrollableListCard)).width,
    );
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('Next renewal date and time'), findsOneWidget);
    final dateRow = find.widgetWithText(ListTile, 'Next renewal date and time');
    final tile = tester.widget<ListTile>(dateRow);
    final labelTop = tester.getTopLeft(find.byWidget(tile.title!)).dy;
    final valueBottom = tester.getBottomLeft(find.byWidget(tile.subtitle!)).dy;
    final textCenter = (labelTop + valueBottom) / 2;
    expect(
      tester.getCenter(find.byWidget(tile.leading!)).dy,
      closeTo(textCenter, 1),
    );
    expect(
      tester.getCenter(find.byWidget(tile.trailing!)).dy,
      closeTo(textCenter, 1),
    );

    final lead = find.byWidgetPredicate(
      (widget) =>
          widget is AppDropdown<int> && widget.label == 'Renewal reminder',
    );
    expect(tester.widget<AppDropdown<int>>(lead).value, 3);
    expect(
      find.textContaining('Reminders use the selected renewal time'),
      findsNothing,
    );
    await tester.ensureVisible(lead);
    await tester.tap(lead);
    await tester.pumpAndSettle();
    expect(find.text('7 days before'), findsOneWidget);
    expect(find.text('8 days before'), findsNothing);
    await tester.ensureVisible(find.text('7 days before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days before'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add Subscription opens the form from an empty dark planner', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionsProvider.overrideWith(
            (ref) => Stream.value(SubscriptionState([], [])),
          ),
          subscriptionAlertPermissionProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          theme: appTheme(brightness: Brightness.dark),
          home: const SubscriptionPlannerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No subscriptions yet.'), findsOneWidget);
    await tester.tap(find.text('Add Subscription'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Next renewal date and time'), findsOneWidget);
    expect(find.text('Save subscription'), findsOneWidget);
    final dateTime = find.text('Next renewal date and time');
    await tester.ensureVisible(dateTime);
    await tester.tap(dateTime);
    await tester.pumpAndSettle();
    expect(find.text('Select date and time'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    final calendarDialog = find.byType(Dialog).last;
    final calendarSize = tester.getSize(calendarDialog);
    final monthSelector = find.byKey(const ValueKey('calendar-month-selector'));
    final initialWidth = tester.getSize(monthSelector).width;
    final monthArrow = find.descendant(
      of: monthSelector,
      matching: find.byIcon(Icons.keyboard_arrow_down),
    );
    final arrowPosition = tester.getCenter(monthArrow);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(tester.getSize(monthSelector).width, initialWidth);
    expect(tester.getCenter(monthArrow), arrowPosition);
    expect(tester.getSize(calendarDialog), calendarSize);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(monthSelector);
    await tester.pumpAndSettle();
    expect(tester.getSize(calendarDialog), calendarSize);
    await tester.tap(find.byTooltip('Back to calendar'));
    await tester.pumpAndSettle();
    final period = find.byWidgetPredicate(
      (widget) => widget is AppDropdown<bool>,
    );
    await tester.ensureVisible(period);
    await tester.tap(period);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9:00 PM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Analysis uses the shared list and removes a renewal when payment is saved',
    (tester) async {
      usePhone(tester);
      final due = DateUtils.dateOnly(DateTime.now());
      final dueDay = subscriptionDay(due);
      final year = PlanningYears.clamp(due.year);
      final spotify = plan.copyWith(anchorDay: dueDay);
      final settled = plan.copyWith(
        id: 'netflix',
        name: 'Netflix',
        anchorDay: dueDay,
        intervalMonths: 12,
      );
      final paidExpense = payment(
        'paid-expense',
        due,
        title: 'Netflix paid',
        amount: 79,
      );
      final subscriptions = SubscriptionState(
        [spotify, settled],
        [
          SubscriptionRenewal(
            planId: settled.id,
            dueDay: dueDay,
            skipped: false,
            expenseId: 'paid-expense',
          ),
        ],
      );
      Expense? savedPayment;
      final changes = StreamController<SubscriptionState>.broadcast();
      addTearDown(changes.close);
      final store = _RenewalStore((expense, planId, day) {
        savedPayment = expense;
        changes.add(
          SubscriptionState(subscriptions.plans, [
            ...subscriptions.renewals.values,
            SubscriptionRenewal(
              planId: planId,
              dueDay: day,
              skipped: false,
              expenseId: expense.id,
            ),
          ]),
        );
      });
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: AnalysisScreen()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesProvider.overrideWith(() => _Expenses([paidExpense])),
            categoriesProvider.overrideWith(_Categories.new),
            subscriptionStoreProvider.overrideWithValue(store),
            subscriptionsProvider.overrideWith((ref) async* {
              yield subscriptions;
              yield* changes.stream;
            }),
          ],
          child: MaterialApp.router(theme: appTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('$year'))
            .didExceedMaxLines,
        isFalse,
      );
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subscriptions'));
      await tester.pumpAndSettle();
      expect(find.text('$year'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('$year'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(find.text('Subscriptions paid'), findsOneWidget);
      expect(
        tester
            .widget<CategorySpendingSummary>(
              find.byType(CategorySpendingSummary),
            )
            .total,
        79,
      );
      final gridGap =
          tester.getTopLeft(find.text('Upcoming renewals')).dy -
          tester.getBottomLeft(find.byType(GridView)).dy;
      expect(gridGap, inInclusiveRange(12, 18));
      final selectService = tester
          .widget<CategoryDonut>(find.byType(CategoryDonut))
          .onCategorySelected!;
      selectService(0);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.text('Payment History'), findsOneWidget);
      final serviceDropdown = find.byWidgetPredicate(
        (w) => w is AppDropdown<String> && w.label == 'Subscription service',
      );
      final collapsedGap =
          tester.getTopLeft(find.text('Payment History')).dy -
          tester.getBottomLeft(serviceDropdown).dy;
      expect(collapsedGap, inInclusiveRange(12, 18));

      final historyList = tester.widget<TransactionList>(
        find.byType(TransactionList),
      );
      expect(historyList.itemCount, 1);
      final paidRow = historyList.itemBuilder(
        tester.element(find.byType(TransactionList)),
        0,
      ) as ExpenseTile;
      expect(paidRow.expense.id, paidExpense.id);
      expect(paidRow.expense.amount, 79);
      tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController
          .jumpTo(0);
      await tester.pumpAndSettle();
      tester
          .widget<CategoryDonut>(find.byType(CategoryDonut))
          .onCategorySelected!(0);
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 10 &&
            find
                .text(DateFormat.MMM().format(due))
                .first
                .hitTestable()
                .evaluate()
                .isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -90));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text(DateFormat.MMM().format(due)).first);
      await tester.pumpAndSettle();
      expect(find.text('Your Days at a glance'), findsNothing);
      expect(find.byType(GridView), findsNothing);
      final renewal = find.widgetWithText(ExpenseTile, 'Spotify');
      await tester.scrollUntilVisible(
        renewal.hitTestable(),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Upcoming renewals'), findsOneWidget);
      expect(find.text('Payment history'), findsNothing);
      expect(find.byType(TransactionList), findsOneWidget);
      expect(find.widgetWithText(ExpenseTile, 'Netflix'), findsNothing);
      await tester.tap(renewal);
      await tester.pumpAndSettle();
      expect(find.text('Renewal'), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Refund'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Skip')).dx,
        lessThan(tester.getCenter(find.text('Renew')).dx),
      );
      await tester.tap(find.text('Renew'));
      await tester.pumpAndSettle();
      expect(savedPayment?.title, 'Spotify');
      expect(savedPayment?.amount, 119);
      expect(renewal, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
