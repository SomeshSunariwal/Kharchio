import '../../core/categories.dart';
import '../../core/expense_summary.dart';
import '../../core/expense_summary_provider.dart';
import '../../shared/category_donut.dart';
import '../../shared/collapsing_expense_overview.dart';
import '../../shared/app_dropdown.dart';
import '../../core/preferences.dart';
import '../../core/monthly_budgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/preview_data.dart';
import '../../shared/category_pie_chart.dart';
import '../../shared/widgets.dart';

enum AnalysisPeriod { year, month, day }

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});
  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisState();
}

class _AnalysisState extends ConsumerState<AnalysisScreen> {
  late DateTime date;
  AnalysisPeriod period = AnalysisPeriod.year;
  String? selectedCategory;
  bool movingForward = true;

  @override
  void initState() {
    super.initState();
    date = DateTime(DateTime.now().year.clamp(2026, 2046));
  }

  void _open(AnalysisPeriod next, DateTime value) {
    setState(() {
      if (next != period) movingForward = next.index > period.index;
      period = next;
      date = value;
    });
  }

  void _selectYear(int year) {
    if (year < 2026 || year > 2046) return;
    final lastDay = DateTime(year, date.month + 1, 0).day;
    _open(period, DateTime(year, date.month, date.day.clamp(1, lastDay)));
  }

  @override
  Widget build(BuildContext context) {
    final currencyCode = context.currency.code;
    final years = [for (var year = 2026; year <= 2046; year++) year];
    final selectedSummary = ref.watch(
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
    final categoryFilter = context.categoryNames.contains(selectedCategory)
        ? selectedCategory
        : null;
    final selectedIndex = categoryFilter == null
        ? null
        : context.categoryNames.indexOf(categoryFilter);
    List<Expense> filtered(List<Expense> values) => categoryFilter == null
        ? values
        : values.where((e) => e.category == categoryFilter).toList();
    final visible = filtered(selected);
    final totals = [
      for (final name in context.categoryNames)
        selectedSummary.categoryTotal(name),
    ];
    final total = selectedSummary.total;
    final budget = period == AnalysisPeriod.year
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
        ? total
        : remainingMonthlyBudget(budget, monthlySpent);
    void selectCategory(int index) => setState(() {
      final name = context.categoryNames[index];
      selectedCategory = selectedCategory == name ? null : name;
    });
    final title = Row(
      children: [
        const Expanded(
          child: Text(
            'Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 122,
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
                  AnalysisPeriod.month => 'Your Days at a glance',
                  AnalysisPeriod.day => 'Expenses',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (categoryFilter != null)
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Clear category filter',
                  onPressed: () => setState(() => selectedCategory = null),
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
        const SizedBox(height: 12),
      ],
    );
    final scale = MediaQuery.textScalerOf(context);
    final chartHeader = CollapsingExpenseOverview(
      summary: CategorySpendingSummary(
        total: displayedTotal,
        label: budget == null
            ? 'Total Spent'
            : displayedTotal < 0
            ? 'Overspending'
            : 'Saving',
        budget: budget,
        overBudget: budget != null && displayedTotal < 0,
      ),
      summaryHeight: scale.scale(11) * 1.5 + 2 + scale.scale(24) * 1.5 + 16,
      footer: resultsHeading,
      footerHeight: 56 + (scale.scale(17) - 17).clamp(0, 40),
      expanded: total > 0
          ? CategoryDonut(
              totals: totals,
              selectedIndex: selectedIndex,
              onCategorySelected: selectCategory,
            )
          : Center(
              child: Text(
                'No expenses in this period',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ),
      expandedHeight: total <= 0
          ? 120
          : CategoryDonut.heightFor(
              (MediaQuery.sizeOf(context).width.clamp(0.0, 700.0) - 54).clamp(
                0.0,
                double.infinity,
              ),
              totals,
              scale,
            ),
      totals: totals,
      colors: context.categoryColors,
      names: context.categoryNames,
      selectedIndex: selectedIndex,
      onCategorySelected: selectCategory,
    );
    final results = switch (period) {
      AnalysisPeriod.year => ListView(
        padding: const EdgeInsets.only(bottom: 72),
        children: [_months(filtered(selected))],
      ),
      AnalysisPeriod.month => ListView(
        padding: const EdgeInsets.only(bottom: 72),
        children: [_days(filtered(selected))],
      ),
      AnalysisPeriod.day => ConnectedListCard(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 72),
          itemCount: visible.isEmpty ? 1 : visible.length,
          separatorBuilder: (context, index) =>
              Divider(height: 1, color: context.appColors.line),
          itemBuilder: (context, index) => visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    categoryFilter == null
                        ? 'No expenses for this day'
                        : 'No expenses in $categoryFilter for this day',
                    style: TextStyle(color: context.appColors.muted),
                  ),
                )
              : ExpenseTile(
                  visible[index],
                  onTap: () => context.push('/add', extra: visible[index]),
                ),
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
                    delegate: chartHeader,
                  ),
                ),
              ],
              body: Padding(
                padding: EdgeInsets.fromLTRB(14, chartHeader.minExtent, 14, 0),
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => AnimatedBuilder(
                      animation: animation,
                      child: FadeTransition(opacity: animation, child: child),
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
                    child: KeyedSubtree(key: ValueKey(period), child: results),
                  ),
                ),
              ),
            ),
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

  double get monthTileHeight =>
      75 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 30) * 3;

  Widget _months(List<Expense> annual) {
    final summary = ExpenseSummary(annual);
    final total = summary.total;
    return GridView.builder(
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
                    value: total == 0 ? 0 : sum / total,
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
