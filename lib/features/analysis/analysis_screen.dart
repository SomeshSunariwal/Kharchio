import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/expense_summary.dart';
import '../../core/expense_summary_provider.dart';
import '../../core/monthly_budgets.dart';
import '../../core/planning_years.dart';
import '../../core/preferences.dart';
import '../../core/subscriptions.dart';
import '../../core/theme.dart';
import '../../database/subscription_store.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/category_donut.dart';
import '../../shared/category_spending_summary.dart';
import '../../shared/collapsing_expense_overview.dart';
import '../../shared/widgets.dart';
import '../profile/renew_subscription_popup.dart';
import 'analysis_chart_pager.dart';
import 'analysis_timeline.dart';

enum _AnalysisView { expenses, subscriptions }

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});
  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisState();
}

class _AnalysisState extends ConsumerState<AnalysisScreen> {
  late DateTime date;
  AnalysisPeriod period = AnalysisPeriod.year;
  String? selectedCategory;
  String? selectedService;
  _AnalysisView view = _AnalysisView.expenses;
  bool movingForward = true;
  int chartPage = 0;

  @override
  void initState() {
    super.initState();
    date = DateTime(PlanningYears.clamp(DateTime.now().year));
  }

  void _open(AnalysisPeriod next, DateTime value) {
    if (view == _AnalysisView.subscriptions && next == AnalysisPeriod.day) {
      return;
    }
    setState(() {
      if (next != period) movingForward = next.index > period.index;
      period = next;
      date = value;
    });
  }

  void _selectYear(int year) {
    final lastDay = DateTime(year, date.month + 1, 0).day;
    _open(period, DateTime(year, date.month, date.day.clamp(1, lastDay)));
  }

  @override
  Widget build(BuildContext context) {
    final currencyCode = context.currency.code;
    final subscriptions = view == _AnalysisView.subscriptions;
    final state = ref.watch(subscriptionsProvider).value;
    String? serviceFor(Expense expense) =>
        state?.planForExpense(expense.id)?.name;
    final years = PlanningYears.values;
    final yearStart = DateTime(date.year);
    final today = DateUtils.dateOnly(DateTime.now());
    var renewalStart = yearStart;
    if (date.year == today.year) {
      for (final plan in state?.plans ?? <SubscriptionPlan>[]) {
        final anchor = subscriptionDate(plan.anchorDay);
        if (anchor.isBefore(renewalStart)) renewalStart = anchor;
      }
    }
    final renewals = subscriptions && state != null
        ? state
              .upcomingRenewals(
                renewalStart,
                DateTime(date.year, 12, 31),
                currencyCode,
                asOf: today,
              )
              .toList()
        : <SubscriptionMatch>[];
    final paid = subscriptions
        ? ref
              .watch(expensesProvider)
              .where(
                (expense) =>
                    !expense.isRefund &&
                    expense.currencyCode == currencyCode &&
                    expense.date.year == date.year &&
                    serviceFor(expense) != null,
              )
              .toList()
        : <Expense>[];
    final services = {
      for (final renewal in renewals) renewal.plan.name,
      for (final expense in paid) serviceFor(expense)!,
    }.toList()..sort();
    final groups = subscriptions
        ? [
            for (var i = 0; i < services.length; i++)
              ExpenseCategory(
                services[i],
                defaultCategories[i % defaultCategories.length].colorValue,
                'subscriptions',
              ),
          ]
        : context.expenseCategories;
    final groupNames = [for (final group in groups) group.name];
    final selectedRenewals = {
      for (final renewal in renewals)
        if (((period == AnalysisPeriod.year ||
                    renewal.dueDay ~/ 100 % 100 == date.month) &&
                (period != AnalysisPeriod.day ||
                    renewal.dueDay % 100 == date.day)) ||
            (renewal.dueDay < subscriptionDay(today) &&
                date.year == today.year &&
                (period == AnalysisPeriod.year || date.month == today.month) &&
                (period != AnalysisPeriod.day || date.day == today.day)))
          '${renewal.plan.id}:${renewal.dueDay}': renewal,
    };
    final selectedSummary = subscriptions
        ? ExpenseSummary([
            for (final expense in paid)
              if ((period == AnalysisPeriod.year ||
                      expense.date.month == date.month) &&
                  (period != AnalysisPeriod.day ||
                      expense.date.day == date.day))
                Expense(
                  id: expense.id,
                  title: expense.title,
                  category: serviceFor(expense)!,
                  amount: expense.amount,
                  date: expense.date,
                  currencyCode: currencyCode,
                ),
          ])
        : ref.watch(
            expenseSummaryProvider((
              year: date.year,
              month: period == AnalysisPeriod.year ? null : date.month,
              day: period == AnalysisPeriod.day ? date.day : null,
              currencyCode: currencyCode,
            )),
          );
    final selected = selectedSummary.expenses;
    final heading = DateFormat(switch (period) {
      AnalysisPeriod.year => 'yyyy',
      AnalysisPeriod.month => 'MMM yyyy',
      AnalysisPeriod.day => 'dd MMM yyyy',
    }).format(date);
    final filter = subscriptions ? selectedService : selectedCategory;
    final categoryFilter = groupNames.contains(filter) ? filter : null;
    final selectedIndex = categoryFilter == null
        ? null
        : groupNames.indexOf(categoryFilter);
    List<Expense> filtered(List<Expense> values) => categoryFilter == null
        ? values
        : values.where((e) => e.category == categoryFilter).toList();
    final visible = filtered(selected);
    final totals = [
      for (final name in groupNames) selectedSummary.categoryTotal(name),
    ];
    final total = selectedSummary.total;
    final budget = subscriptions || period == AnalysisPeriod.year
        ? null
        : ref.watch(
            monthBudgetProvider((
              year: date.year,
              month: date.month,
              currencyCode: currencyCode,
            )),
          );
    final monthlySpent = budget == null
        ? total
        : ref
              .watch(
                expenseSummaryProvider((
                  year: date.year,
                  month: date.month,
                  day: null,
                  currencyCode: currencyCode,
                )),
              )
              .total;
    final displayedTotal = budget == null
        ? subscriptions && categoryFilter != null
              ? selectedSummary.categoryTotal(categoryFilter)
              : total
        : remainingMonthlyBudget(budget, monthlySpent);
    void setFilter(String? name) => setState(() {
      if (subscriptions) {
        selectedService = name;
      } else {
        selectedCategory = name;
      }
    });
    void selectCategory(int index) => setFilter(
      categoryFilter == groupNames[index] ? null : groupNames[index],
    );
    final textScaler = MediaQuery.textScalerOf(context);
    const viewWidth = 120.0;
    const selectorGap = 8.0;
    final yearLabel = TextPainter(
      text: TextSpan(
        text: '${date.year}',
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    // Reserve the calendar icon, chevron and field padding around the year.
    final yearWidth = (yearLabel.width + 84).clamp(112.0, double.infinity);
    yearLabel.dispose();
    final selectors = Wrap(
      alignment: WrapAlignment.end,
      spacing: selectorGap,
      runSpacing: selectorGap,
      children: [
        if (period != AnalysisPeriod.day)
          SizedBox(
            width: viewWidth,
            child: AppDropdown<_AnalysisView>(
              value: view,
              label: 'Analysis view',
              compact: true,
              options: const [
                AppDropdownOption(_AnalysisView.expenses, 'Expenses'),
                AppDropdownOption(_AnalysisView.subscriptions, 'Subscriptions'),
              ],
              onChanged: (value) => setState(() {
                if (view == value) return;
                view = value;
                period = AnalysisPeriod.year;
                date = DateTime(date.year);
              }),
            ),
          ),
        SizedBox(
          width: yearWidth,
          child: AppDropdown<int>(
            value: date.year,
            label: 'Year',
            compact: true,
            leadingIcon: Icons.calendar_month_outlined,
            options: [
              for (final year in years) AppDropdownOption(year, '$year'),
            ],
            onChanged: _selectYear,
          ),
        ),
      ],
    );
    const headingLabel = Text(
      'Analysis',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    );
    final title = LayoutBuilder(
      builder: (context, constraints) {
        final titleWidth = textScaler.scale(80);
        if (constraints.maxWidth <
            titleWidth +
                (period == AnalysisPeriod.day ? 0 : viewWidth + selectorGap) +
                yearWidth +
                selectorGap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              headingLabel,
              Align(alignment: Alignment.centerRight, child: selectors),
            ],
          );
        }
        return Row(
          children: [
            const Expanded(child: headingLabel),
            selectors,
          ],
        );
      },
    );
    final resultsHeading = Column(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: period == AnalysisPeriod.year ? 0 : 28,
              height: 32,
              child: period == AnalysisPeriod.year
                  ? null
                  : IconButton(
                      tooltip: period == AnalysisPeriod.day
                          ? 'Back to days'
                          : 'Back to months',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _open(
                        period == AnalysisPeriod.day
                            ? AnalysisPeriod.month
                            : AnalysisPeriod.year,
                        DateTime(date.year, date.month),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 18),
                    ),
            ),
            Expanded(
              child: Text(
                switch (period) {
                  AnalysisPeriod.year => 'Your Months at a glance',
                  AnalysisPeriod.month =>
                    subscriptions ? 'Subscriptions' : 'Your Days at a glance',
                  AnalysisPeriod.day =>
                    subscriptions
                        ? (categoryFilter == null
                              ? 'Upcoming renewals'
                              : 'Payment History')
                        : 'Transactions',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (categoryFilter != null && !subscriptions)
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Clear category filter',
                  onPressed: () => setFilter(null),
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ),
            if (period != AnalysisPeriod.year)
              Text(
                heading,
                style: TextStyle(fontSize: 11, color: context.appColors.muted),
              ),
          ],
        ),
        if (subscriptions && services.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AppDropdown<String>(
              value: categoryFilter ?? '',
              label: 'Subscription service',
              compact: true,
              options: [
                const AppDropdownOption('', 'All subscriptions'),
                for (final service in services)
                  AppDropdownOption(service, service),
              ],
              onChanged: (value) => setFilter(value.isEmpty ? null : value),
            ),
          ),
        if (!subscriptions) const SizedBox(height: 12),
      ],
    );
    final scale = MediaQuery.textScalerOf(context);
    final pieHeight = CategoryDonut.heightFor(
      (MediaQuery.sizeOf(context).width.clamp(0.0, 700.0) - 54).clamp(
        0.0,
        double.infinity,
      ),
      totals,
      scale,
    );
    final chartHeader = CollapsingExpenseOverview(
      summary: CategorySpendingSummary(
        total: budget == null ? displayedTotal.abs() : displayedTotal,
        label: subscriptions
            ? 'Subscriptions paid'
            : budget == null
            ? (total < 0 ? 'Net Refund' : 'Net Spent')
            : displayedTotal < 0
            ? 'Overspending'
            : 'Saving',
        budget: budget,
        overBudget: budget != null && displayedTotal < 0,
      ),
      summaryHeight: scale.scale(11) * 1.5 + 2 + scale.scale(24) * 1.5 + 16,
      footer: resultsHeading,
      footerHeight:
          (subscriptions ? 44 : 56) +
          (scale.scale(17) - 17).clamp(0, 40) +
          (subscriptions && services.isNotEmpty
              ? 40 + (scale.scale(12) - 12).clamp(0, 20) * 2
              : 0),
      expanded: totals.any((value) => value != 0)
          ? CategoriesScope(
              categories: groups,
              child: AnalysisChartPager(
                totals: totals,
                timeline: AnalysisTimeline(
                  expenses: selected,
                  period: period,
                  date: date,
                  currencyCode: currencyCode,
                ),
                page: chartPage,
                budget: budget,
                onPageChanged: (page) => setState(() => chartPage = page),
                selectedIndex: selectedIndex,
                onCategorySelected: selectCategory,
              ),
            )
          : Center(
              child: Text(
                subscriptions
                    ? 'No subscription payments in this period'
                    : 'No expenses in this period',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ),
      // Both pages share a fixed viewport so the line's X-axis cannot drift
      // vertically during a horizontal swipe.
      expandedHeight: totals.any((value) => value != 0) ? 24 + pieHeight : 120,
      totals: totals,
      colors: [for (final group in groups) group.color],
      names: groupNames,
      selectedIndex: selectedIndex,
      onCategorySelected: selectCategory,
    );
    final overview = subscriptions
        ? _SubscriptionOverview(
            chart: chartHeader,
            calendar: switch (period) {
              AnalysisPeriod.year => _months(filtered(selected)),
              AnalysisPeriod.month ||
              AnalysisPeriod.day => const SizedBox.shrink(),
            },
            calendarHeight: period == AnalysisPeriod.year
                ? monthTileHeight * 4 + 42
                : 0,
            title: categoryFilter == null
                ? 'Upcoming renewals'
                : 'Payment History',
          )
        : chartHeader;
    final results = subscriptions
        ? _subscriptionResults(
            selectedRenewals,
            history: categoryFilter == null ? null : visible,
            payments: {for (final expense in paid) expense.id: expense},
          )
        : switch (period) {
            AnalysisPeriod.year => ListView(
              padding: const EdgeInsets.only(bottom: 72),
              children: [_months(filtered(selected))],
            ),
            AnalysisPeriod.month => ListView(
              padding: const EdgeInsets.only(bottom: 72),
              children: [_days(filtered(selected))],
            ),
            AnalysisPeriod.day => TransactionList(
              padding: const EdgeInsets.only(bottom: 72),
              itemCount: visible.length,
              empty: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    categoryFilter == null
                        ? 'No transactions for this day'
                        : 'No transactions in $categoryFilter for this day',
                    style: TextStyle(color: context.appColors.muted),
                  ),
                ),
              ),
              itemBuilder: (context, index) => ExpenseTile(
                visible[index],
                onTap: () => context.push('/add', extra: visible[index]),
                subscriptionName: serviceFor(visible[index]),
              ),
            ),
          };
    return SafeArea(
      child: FixedHeaderPage(
        header: title,
        headerPadding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NestedScrollView(
              headerSliverBuilder: (nestedContext, innerBoxIsScrolled) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    nestedContext,
                  ),
                  sliver: SliverPersistentHeader(
                    pinned: true,
                    delegate: overview,
                  ),
                ),
              ],
              body: Padding(
                padding: EdgeInsets.fromLTRB(14, overview.minExtent, 14, 0),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        transitionBuilder: (child, animation) =>
                            AnimatedBuilder(
                              animation: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                              builder: (context, panel) {
                                final incoming = child.key == ValueKey(period);
                                final direction = movingForward ? 1.0 : -1.0;
                                return IgnorePointer(
                                  ignoring: !incoming,
                                  child: ExcludeSemantics(
                                    excluding: !incoming,
                                    child: FractionalTranslation(
                                      translation: Offset(
                                        (incoming ? direction : -direction) *
                                            .3 *
                                            (1 - animation.value),
                                        0,
                                      ),
                                      child: panel,
                                    ),
                                  ),
                                );
                              },
                            ),
                        child: KeyedSubtree(
                          key: ValueKey(period),
                          child: results,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!subscriptions)
              Positioned(
                right: 26,
                bottom: 12,
                child: SizedBox.square(
                  dimension: 48,
                  child: FloatingActionButton(
                    heroTag: 'analysis-add-expense',
                    tooltip: 'Add expense',
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    onPressed: () => context.push('/add', extra: date),
                    child: const Icon(Icons.add_rounded, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionResults(
    Map<String, SubscriptionMatch> renewals, {
    required List<Expense>? history,
    required Map<String, Expense> payments,
  }) {
    final items = history != null
        ? ([...history]..sort((a, b) => b.date.compareTo(a.date)))
        : ([
            for (final entry in renewals.entries)
              Expense(
                id: entry.key,
                title: entry.value.plan.name,
                category: entry.value.plan.name,
                amount: entry.value.plan.minor / 100,
                date: subscriptionDate(entry.value.dueDay),
                currencyCode: entry.value.plan.currencyCode,
              ),
          ]..sort((a, b) => a.date.compareTo(b.date)));
    return TransactionList(
      itemCount: items.length,
      empty: Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            history == null
                ? 'No upcoming renewals in this period.'
                : 'No payments for this selection.',
          ),
        ),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        if (history != null) {
          final expense = payments[item.id]!;
          return ExpenseTile(
            expense,
            subscriptionName: item.category,
            onTap: () => context.push('/add', extra: expense),
          );
        }
        final renewal = renewals[item.id]!;
        return ExpenseTile.renewal(
          item,
          key: ValueKey(item.id),
          onTap: () => showRenewSubscriptionPopup(context, renewal),
        );
      },
    );
  }

  double get monthTileHeight =>
      75 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 30) * 3;

  Widget _months(List<Expense> annual) {
    final summary = ExpenseSummary(annual);
    final total = summary.total;
    return GridView.builder(
      primary: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: monthTileHeight,
      ),
      itemBuilder: (context, index) {
        final month = index + 1;
        final sum = summary.byMonth[month] ?? 0;
        return Material(
          color: context.appColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: context.appColors.dark
                  ? context.appColors.line.withValues(alpha: .65)
                  : const Color(0xFFBFC5CD),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                _open(AnalysisPeriod.month, DateTime(date.year, month)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('MMM').format(DateTime(date.year, month)),
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: context.appColors.muted.withValues(alpha: .6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(
                      context.currency.formatWhole(sum),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: sum > 0
                            ? context.appColors.ink
                            : context.appColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: total <= 0 ? 0 : (sum / total).clamp(0.0, 1.0),
                    backgroundColor: context.appColors.line.withValues(
                      alpha: .5,
                    ),
                    color: context.appColors.actionBlue.withValues(alpha: .7),
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _days(List<Expense> monthly) {
    final summary = ExpenseSummary(monthly);
    final offset = DateTime(date.year, date.month).weekday - 1;
    final count = DateTime(date.year, date.month + 1, 0).day;
    final weeks = ((offset + count) / 7).ceil();
    return SizedBox(
      height: monthTileHeight * 4 + 30,
      child: SurfaceCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: weeks * 7,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: constraints.maxHeight / weeks,
                  ),
                  itemBuilder: (context, index) {
                    if (index < offset || index >= offset + count) {
                      return const SizedBox.shrink();
                    }
                    final day = index - offset + 1;
                    final sum = summary.byDay[day] ?? 0;
                    return Semantics(
                      label:
                          '$day ${DateFormat('MMMM yyyy').format(date)}, ${context.money(sum)}',
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => _open(
                          AnalysisPeriod.day,
                          DateTime(date.year, date.month, day),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: sum > 0 ? green.withValues(alpha: .1) : null,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sum > 0
                                      ? green
                                      : context.appColors.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                child: Text(
                                  context.currency.formatCalendar(sum),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: sum > 0
                                        ? green
                                        : context.appColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the dashboard transaction viewport fixed while its calendar collapses.
class _SubscriptionOverview extends SliverPersistentHeaderDelegate {
  final CollapsingExpenseOverview chart;
  final Widget calendar;
  final double calendarHeight;
  final String title;
  _SubscriptionOverview({
    required this.chart,
    required this.calendar,
    required this.calendarHeight,
    required this.title,
  });

  @override
  double get minExtent => chart.minExtent + 48;
  @override
  double get maxExtent => chart.maxExtent + calendarHeight + 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final chartTravel = chart.maxExtent - chart.minExtent;
    final chartHeight = (chart.maxExtent - shrinkOffset).clamp(
      chart.minExtent,
      chart.maxExtent,
    );
    final calendarTravel = (shrinkOffset - chartTravel).clamp(
      0.0,
      calendarHeight,
    );
    return ColoredBox(
      color: context.appColors.background,
      child: Column(
        children: [
          SizedBox(
            height: chartHeight,
            child: chart.build(
              context,
              shrinkOffset.clamp(0.0, chartTravel),
              overlapsContent,
            ),
          ),
          Expanded(
            child: ClipRect(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) =>
                    LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        calendarTravel > 0 ? Colors.transparent : Colors.white,
                        Colors.white,
                      ],
                      stops: [0, (18 / (bounds.height + 12)).clamp(0.0, 1.0)],
                    ).createShader(
                      // Anchor the fade at the dropdown edge. Most of its travel
                      // sits under the control, rather than forming a strip below it.
                      Rect.fromLTWH(0, -12, bounds.width, bounds.height + 12),
                    ),
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: calendarHeight,
                  maxHeight: calendarHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: calendar,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SubscriptionOverview oldDelegate) => true;
}
