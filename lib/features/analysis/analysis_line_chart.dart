import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/categories.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import 'analysis_timeline.dart';

class AnalysisLineChart extends StatelessWidget {
  final AnalysisTimeline timeline;
  final int? selectedIndex;
  final bool active;
  final double? budget;
  const AnalysisLineChart({
    super.key,
    required this.timeline,
    this.selectedIndex,
    this.active = true,
    this.budget,
  });

  String _bucketLabel(int index, {bool full = false}) =>
      switch (timeline.period) {
        AnalysisPeriod.year => DateFormat(
          full ? 'MMMM' : 'MMM',
        ).format(DateTime(timeline.date.year, index + 1)),
        AnalysisPeriod.month =>
          full
              ? DateFormat('d MMM').format(
                  DateTime(timeline.date.year, timeline.date.month, index + 1),
                )
              : '${index + 1}',
        AnalysisPeriod.day => '${index.toString().padLeft(2, '0')}:00',
      };

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey((timeline.period, timeline.date, selectedIndex)),
    tween: Tween(begin: 0, end: active ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (context, progress, _) => _chart(context, progress),
  );

  Widget _chart(BuildContext context, double progress) {
    const blue = Color(0xFF365CFF);
    final categories = context.expenseCategories;
    final selected = selectedIndex == null
        ? null
        : categories[selectedIndex!].name;
    final sources = selected == null
        ? timeline.byCategory.values
        : [
            timeline.byCategory[selected] ??
                List<double>.filled(timeline.bucketCount, 0),
          ];
    final values = List<double>.generate(
      timeline.bucketCount,
      (bucket) =>
          sources.fold<int>(
            0,
            (sum, source) => sum + (source[bucket] * 100).round(),
          ) /
          100,
    );
    final peak = values.reduce(math.max);
    final rawStep = peak > 0 ? peak / 4 : 1.0;
    final magnitude = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final normalized = rawStep / magnitude;
    final step =
        (normalized <= 1
            ? 1
            : normalized <= 2
            ? 2
            : normalized <= 5
            ? 5
            : 10) *
        magnitude;
    final maxY = peak > 0 ? (peak / step).ceil() * step : 4.0;
    final colors = context.appColors;
    final tickStyle = TextStyle(fontSize: 9, color: colors.muted);
    final ticks = switch (timeline.period) {
      AnalysisPeriod.year => <int>{0, 2, 4, 6, 8, 11},
      AnalysisPeriod.month => <int>{
        0,
        4,
        9,
        14,
        19,
        24,
        timeline.bucketCount - 1,
      },
      AnalysisPeriod.day => <int>{0, 4, 8, 12, 16, 20, 23},
    };
    final line = LineChartBarData(
      spots: [
        for (var bucket = 0; bucket < values.length; bucket++)
          FlSpot(bucket.toDouble(), values[bucket] * progress),
      ],
      color: blue,
      barWidth: 2.5,
      isCurved: false,
      isStrokeCapRound: true,
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            blue.withValues(alpha: colors.dark ? .35 : .23),
            blue.withValues(alpha: .015),
          ],
        ),
      ),
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.y > 0,
        getDotPainter: (spot, percent, bar, index) =>
            FlDotCirclePainter(radius: 2.5, color: blue, strokeWidth: 0),
      ),
    );
    return Semantics(
      label:
          'Spending by ${switch (timeline.period) {
            AnalysisPeriod.year => 'month',
            AnalysisPeriod.month => 'day',
            AnalysisPeriod.day => 'hour',
          }}. Amounts in ${context.currency.code}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount (${context.currency.symbol})',
            style: TextStyle(fontSize: 10, color: colors.muted),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (timeline.bucketCount - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [line],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      // Preserve the spending scale. A distant budget should not
                      // flatten the graph; show its marker once the level is in view.
                      if (budget != null && budget! > 0 && budget! <= maxY)
                        HorizontalLine(
                          y: budget!,
                          color: green.withValues(alpha: .5),
                          strokeWidth: 2,
                          dashArray: [6, 4],
                        ),
                    ],
                  ),
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(
                        color: colors.muted.withValues(alpha: .45),
                        width: 1,
                      ),
                      bottom: BorderSide(
                        color: colors.muted.withValues(alpha: .45),
                        width: 1,
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: step,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.line, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: step,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            context.currency.formatChartNumber(value),
                            style: tickStyle,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) =>
                            ticks.contains(value.round()) &&
                                (value - value.round()).abs() < .01
                            ? SideTitleWidget(
                                meta: meta,
                                space: 6,
                                fitInside: SideTitleFitInsideData.fromTitleMeta(
                                  meta,
                                  distanceFromEdge: 0,
                                ),
                                child: Text(
                                  _bucketLabel(value.round()),
                                  style: tickStyle,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator: (bar, indexes) => [
                      for (final _ in indexes)
                        TouchedSpotIndicatorData(
                          FlLine(
                            color: blue.withValues(alpha: .7),
                            strokeWidth: 1,
                            dashArray: [4, 4],
                          ),
                          FlDotData(
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                                  radius: 3,
                                  color: blue,
                                  strokeWidth: 0,
                                ),
                          ),
                        ),
                    ],
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      maxContentWidth: 170,
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipColor: (_) => colors.surface,
                      tooltipBorder: BorderSide(color: colors.line),
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          progress < 1
                              ? null
                              : LineTooltipItem(
                                  '${_bucketLabel(spot.x.round(), full: true)} · ${selected ?? 'Total spending'}\n${context.money(spot.y)}',
                                  TextStyle(
                                    fontSize: 11,
                                    color: colors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ),
                // The tween above controls the rise; avoid a second chart tween.
                duration: Duration.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
