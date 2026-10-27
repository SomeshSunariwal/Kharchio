import '../../shared/collapsing_expense_overview.dart';
import '../../shared/category_donut.dart';
import '../../core/preferences.dart';
import '../../core/categories.dart';
import '../../core/expense_summary_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/preview_data.dart';
import '../../shared/widgets.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  bool searching = false;
  String query = '';
  String? selectedCategory;

  void selectCategory(int index) {
    final name = context.categoryNames[index];
    setState(() => selectedCategory = selectedCategory == name ? null : name);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(selectedMonthProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final monthName = DateFormat('MMM').format(month);
    final dateRange =
        '1st $monthName – $lastDay${lastDay == 31 ? 'st' : 'th'} $monthName';
    final currencyCode = context.currency.code;
    final currentSummary = ref.watch(
      expenseSummaryProvider((
        year: month.year,
        month: month.month,
        day: null,
        currencyCode: currencyCode,
      )),
    );
    final categoryFilter = context.categoryNames.contains(selectedCategory)
        ? selectedCategory
        : null;
    final selectedIndex = categoryFilter == null
        ? null
        : context.categoryNames.indexOf(categoryFilter);
    final expenses = currentSummary.expenses;
    final total = currentSummary.total;
    final previous = DateTime(month.year, month.month - 1);
    final previousTotal = ref
        .watch(
          expenseSummaryProvider((
            year: previous.year,
            month: previous.month,
            day: null,
            currencyCode: currencyCode,
          )),
        )
        .total;
    final normalizedQuery = query.toLowerCase();
    final visible = expenses
        .where(
          (e) =>
              (categoryFilter == null || e.category == categoryFilter) &&
              '${e.title} ${e.description} ${e.category}'
                  .toLowerCase()
                  .contains(normalizedQuery),
        )
        .toList();
    final totals = context.categoryNames
        .map(currentSummary.categoryTotal)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final summary = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Spent',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      context.money(total),
                      style: TextStyle(
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (previousTotal > 0) ...[
                          Icon(
                            total >= previousTotal
                                ? Icons.north_east_rounded
                                : Icons.south_east_rounded,
                            size: 13,
                            color: green,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          previousTotal == 0
                              ? 'No expenses in the previous month'
                              : '${((total - previousTotal).abs() / previousTotal * 100).toStringAsFixed(0)}% ${total >= previousTotal ? 'more' : 'less'} than last month',
                          style: const TextStyle(
                            color: green,
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => context.push('/add'),
              icon: Icon(Icons.add, size: 19),
              label: Text('Add Expense', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, 38),
                padding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        );
        final recentHeading = Column(
          children: [
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    categoryFilter ?? 'Recent Transactions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (categoryFilter != null)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      tooltip: 'Clear category filter',
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => selectedCategory = null),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 4),
          ],
        );
        final overview = SurfaceCard(
          color: context.appColors.dark
              ? context.appColors.surface
              : context.appColors.tint,
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summary,
              SizedBox(height: 7),
              if (total > 0)
                CategoryDonut(
                  totals: totals,
                  selectedIndex: selectedIndex,
                  onCategorySelected: selectCategory,
                )
              else
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'No spending yet. Add your first expense.',
                      style: TextStyle(color: context.appColors.muted),
                    ),
                  ),
                ),
            ],
          ),
        );
        final chartHeight = CategoryDonut.heightFor(
          (constraints.maxWidth - 54).clamp(0.0, double.infinity),
          totals,
          MediaQuery.textScalerOf(context),
        );
        final scale = MediaQuery.textScalerOf(context);
        final summaryHeight =
            scale.scale(12) * 1.5 + 2 + scale.scale(26) + scale.scale(13) + 4;
        final collapsible = expenses.length > 6 && total > 0;
        final chartHeader = CollapsingExpenseOverview(
          summary: summary,
          footer: recentHeading,
          footerHeight:
              42 +
              (MediaQuery.textScalerOf(context).scale(17) - 17).clamp(0, 40),
          summaryHeight: summaryHeight,
          expanded: CategoryDonut(
            totals: totals,
            selectedIndex: selectedIndex,
            onCategorySelected: selectCategory,
          ),
          selectedIndex: selectedIndex,
          onCategorySelected: selectCategory,
          expandedHeight: chartHeight,
          totals: totals,
          colors: context.categoryColors,
          names: context.categoryNames,
        );
        final monthHeader = Column(
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 25),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(month),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        dateRange,
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Search expenses',
                  onPressed: () => setState(() => searching = !searching),
                  icon: Icon(Icons.search),
                ),
              ],
            ),
            SizedBox(height: 8),
            if (searching)
              Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: TextField(
                  autofocus: true,
                  style: TextStyle(fontSize: 13),
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: context.appColors.field,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: context.appColors.muted,
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    hintText: 'Search transactions',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: context.appColors.muted,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: context.appColors.line,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: green, width: 1),
                    ),
                  ),
                ),
              ),
          ],
        );
        return SafeArea(
          child: FixedHeaderPage(
            header: monthHeader,
            headerPadding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: NestedScrollView(
              headerSliverBuilder: (nestedContext, innerBoxIsScrolled) => [
                if (collapsible)
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      nestedContext,
                    ),
                    sliver: SliverPersistentHeader(
                      pinned: true,
                      delegate: chartHeader,
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(children: [overview, recentHeading]),
                    ),
                  ),
              ],
              // Absorb the pinned header's obstruction, then reserve that space
              // OUTSIDE the inner list. Its rounded card can never scroll beneath
              // the header. NestedScrollView consumes header travel before rows.
              body: Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  collapsible ? chartHeader.minExtent : 0,
                  14,
                  0,
                ),
                child: ConnectedListCard(
                  child: visible.isEmpty
                      ? const Center(child: Text('No transactions found'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: context.appColors.line),
                          itemBuilder: (context, index) => ExpenseTile(
                            visible[index],
                            onTap: () =>
                                context.push('/add', extra: visible[index]),
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
