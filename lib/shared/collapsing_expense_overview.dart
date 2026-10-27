import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'category_percentage_bar.dart';
import 'widgets.dart';

/// One card surface; only the chart changes as the outer scroll collapses.
class CollapsingExpenseOverview extends SliverPersistentHeaderDelegate {
  final Widget summary, footer, expanded;
  final double footerHeight, summaryHeight, expandedHeight;
  final List<double> totals;
  final List<Color> colors;
  final List<String> names;
  final int? selectedIndex;
  final ValueChanged<int>? onCategorySelected;
  CollapsingExpenseOverview({
    required this.summary,
    required this.footer,
    required this.footerHeight,
    required this.summaryHeight,
    required this.expanded,
    required this.expandedHeight,
    required this.totals,
    required this.colors,
    required this.names,
    this.selectedIndex,
    this.onCategorySelected,
  });

  static const _padding = 12.0;
  static const _chartGap = 7.0;
  static const _borderSpace = 2.0;
  static const _barHeight = 28.0;
  bool get _hasChart => totals.any((amount) => amount > 0);
  double get _fixedHeight =>
      summaryHeight +
      _padding * 2 +
      (_hasChart ? _chartGap : 0) +
      _borderSpace +
      footerHeight;
  @override
  double get minExtent => _fixedHeight + (_hasChart ? _barHeight : 0);
  @override
  double get maxExtent =>
      _fixedHeight + (_hasChart ? math.max(_barHeight, expandedHeight) : 0);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final progress = range > 0 ? (shrinkOffset / range).clamp(0.0, 1.0) : 1.0;
    final compact = progress > .5;
    final fade = MediaQuery.disableAnimationsOf(context)
        ? (compact ? 1.0 : 0.0)
        : Curves.easeInOut.transform(progress);
    Widget chartLayer(Widget child, {required bool isCompact}) => IgnorePointer(
      ignoring: compact != isCompact,
      child: ExcludeSemantics(
        excluding: compact != isCompact,
        child: Opacity(opacity: isCompact ? fade : 1 - fade, child: child),
      ),
    );
    return ColoredBox(
      color: context.appColors.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: [
            Expanded(
              child: SurfaceCard(
                color: context.appColors.dark
                    ? context.appColors.surface
                    : context.appColors.tint,
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      Positioned(
                        top: _padding,
                        left: _padding,
                        right: _padding,
                        height: summaryHeight,
                        child: RepaintBoundary(child: summary),
                      ),
                      if (_hasChart)
                        Positioned(
                          top: summaryHeight + _padding + _chartGap,
                          left: _padding,
                          right: _padding,
                          bottom: _padding,
                          child: ClipRect(
                            child: Stack(
                              children: [
                                if (fade < 1)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: expandedHeight,
                                    child: chartLayer(
                                      expanded,
                                      isCompact: false,
                                    ),
                                  ),
                                if (fade > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: _barHeight,
                                    child: chartLayer(
                                      CategoryPercentageBar(
                                        totals: totals,
                                        colors: colors,
                                        names: names,
                                        selectedIndex: selectedIndex,
                                        onCategorySelected: onCategorySelected,
                                      ),
                                      isCompact: true,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: footerHeight, child: footer),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CollapsingExpenseOverview old) =>
      old.summary != summary ||
      old.footer != footer ||
      old.expanded != expanded ||
      old.footerHeight != footerHeight ||
      old.summaryHeight != summaryHeight ||
      old.expandedHeight != expandedHeight ||
      old.selectedIndex != selectedIndex ||
      old.onCategorySelected != onCategorySelected ||
      !listEquals(old.totals, totals) ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.names, names);
}
