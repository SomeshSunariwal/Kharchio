import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/category_donut.dart';
import 'analysis_line_chart.dart';
import 'analysis_timeline.dart';

/// Analysis-only chart pages; the dashboard keeps its existing donut.
class AnalysisChartPager extends StatefulWidget {
  final List<double> totals;
  final AnalysisTimeline timeline;
  final int page;
  final double? budget;
  final int? selectedIndex;
  final ValueChanged<int> onPageChanged, onCategorySelected;
  const AnalysisChartPager({
    super.key,
    required this.totals,
    required this.timeline,
    required this.page,
    required this.onPageChanged,
    required this.onCategorySelected,
    this.selectedIndex,
    this.budget,
  });
  @override
  State<AnalysisChartPager> createState() => _AnalysisChartPagerState();
}

class _AnalysisChartPagerState extends State<AnalysisChartPager> {
  late final controller = PageController(initialPage: widget.page);

  double get _progress => controller.hasClients
      ? (controller.page ?? widget.page.toDouble()).clamp(0.0, 1.0)
      : widget.page.toDouble();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _select(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(page);
    } else {
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PageView(
          key: const ValueKey('analysis-chart-pages'),
          controller: controller,
          onPageChanged: widget.onPageChanged,
          children: [
            Center(
              child: CategoryDonut(
                totals: widget.totals,
                selectedIndex: widget.selectedIndex,
                onCategorySelected: widget.onCategorySelected,
              ),
            ),
            AnalysisLineChart(
              timeline: widget.timeline,
              active: widget.page == 1,
              budget: widget.budget,
              selectedIndex: widget.selectedIndex,
            ),
          ],
        ),
      ),
      SizedBox(
        width: 88,
        height: 24,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Container(
                        key: ValueKey('analysis-chart-indicator-$i'),
                        width: 12 + 14 * (i == 0 ? 1 - _progress : _progress),
                        height: 4,
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            context.appColors.muted.withValues(alpha: .35),
                            green,
                            i == 0 ? 1 - _progress : _progress,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Keep generous tap targets independent of the 2 px visual gap.
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: Semantics(
                        label: i == 0 ? 'Pie chart' : 'Line chart',
                        button: true,
                        selected: widget.page == i,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _select(i),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
