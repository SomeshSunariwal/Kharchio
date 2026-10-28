import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/preferences.dart';
import '../core/theme.dart';

class CategoryDonut extends StatelessWidget {
  final List<double> totals;
  final int? selectedIndex;
  final ValueChanged<int>? onCategorySelected;
  const CategoryDonut({
    super.key,
    required this.totals,
    this.selectedIndex,
    this.onCategorySelected,
  });

  static double heightFor(
    double width,
    List<double> totals,
    TextScaler scaler,
  ) {
    return _DonutGeometry(totals).height(width, scaler);
  }

  @override
  Widget build(BuildContext context) {
    final total = totals.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return const SizedBox.shrink();
    final geometry = _DonutGeometry(totals);
    final active = geometry.active;
    final angles = geometry.angles;
    final left = geometry.left;
    final right = geometry.right;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final diameter = math.min(width * .5, 180.0);
          final textScale = MediaQuery.textScalerOf(context);
          final labelHeight =
              textScale.scale(9) * 2.4 + textScale.scale(11) * 1.2 + 3;
          final height = geometry.height(width, textScale);
          final labels = <int, _DonutLabel>{};
          for (final side in [left, right]) {
            for (var n = 0; n < side.length; n++) {
              final top = side.length == 1
                  ? (height - labelHeight) / 2
                  : 2 + n * (height - labelHeight - 4) / (side.length - 1);
              labels[side[n]] = _DonutLabel(
                top,
                identical(side, right),
                angles[side[n]]!,
              );
            }
          }
          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ConnectorPainter(
                      labels: labels,
                      colors: [
                        for (var i = 0; i < totals.length; i++)
                          selectedIndex == null || selectedIndex == i
                              ? context.categoryColors[i]
                              : context.categoryColors[i].withValues(
                                  alpha: .35,
                                ),
                      ],
                      diameter: diameter,
                    ),
                  ),
                ),
                SizedBox(
                  width: diameter,
                  height: diameter,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _DonutEntrance(
                        child: PieChart(
                          PieChartData(
                            startDegreeOffset:
                                geometry.startAngle * 180 / math.pi,
                            sectionsSpace: 1,
                            centerSpaceRadius: diameter * .25,
                            pieTouchData: PieTouchData(
                              enabled: onCategorySelected != null,
                              touchCallback: (event, response) {
                                if (event is! FlTapUpEvent) return;
                                final section =
                                    response
                                        ?.touchedSection
                                        ?.touchedSectionIndex ??
                                    -1;
                                if (section >= 0 && section < active.length) {
                                  onCategorySelected?.call(active[section]);
                                }
                              },
                            ),
                            sections: [
                              for (final i in active)
                                PieChartSectionData(
                                  value: totals[i],
                                  color:
                                      selectedIndex == null ||
                                          selectedIndex == i
                                      ? context.categoryColors[i]
                                      : context.categoryColors[i].withValues(
                                          alpha: .35,
                                        ),
                                  borderSide: selectedIndex == i
                                      ? const BorderSide(
                                          color: Colors.white,
                                          width: 2,
                                        )
                                      : BorderSide.none,
                                  radius: diameter * .25,
                                  title:
                                      '${(totals[i] / total * 100).round()}%',
                                  showTitle: totals[i] / total >= .05,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: diameter * .45,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.currency.symbol,
                              style: const TextStyle(fontSize: 12, height: 1.1),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                context.currency.formatChartNumber(total),
                                style: TextStyle(
                                  fontSize: width < 330 ? 13 : 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              'Total',
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final entry in labels.entries)
                  Positioned(
                    left: entry.value.right ? null : 0,
                    right: entry.value.right ? 0 : null,
                    top: entry.value.top,
                    child: SizedBox(
                      width: width * .20,
                      child: Column(
                        crossAxisAlignment: entry.value.right
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: context.categoryColors[entry.key],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  context.categoryNames[entry.key],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            child: Text(
                              context.currency.formatChart(totals[entry.key]),
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DonutGeometry {
  final active = <int>[];
  final angles = <int, double>{};
  late final List<int> left, right;
  double startAngle = -math.pi / 2;

  _DonutGeometry(List<double> totals) {
    final sum = totals.fold<double>(0, (a, b) => a + b);
    var angle = -math.pi / 2;
    if (sum > 0) {
      for (var i = 0; i < totals.length; i++) {
        if (totals[i] <= 0) continue;
        final sweep = totals[i] / sum * 2 * math.pi;
        active.add(i);
        angles[i] = angle + sweep / 2;
        angle += sweep;
      }
    }
    // Rotate only as far as needed to balance label counts. A dominant slice
    // otherwise crowds every small category onto the opposite side.
    double rotation = 0;
    var bestImbalance = active.length;
    final candidates = <double>[0];
    for (final angle in angles.values) {
      for (final boundary in [math.pi / 2, math.pi * 1.5]) {
        for (final offset in [-.02, .02]) {
          final value = boundary - angle + offset;
          candidates.add(math.atan2(math.sin(value), math.cos(value)));
        }
      }
    }
    for (final candidate in candidates) {
      final leftCount = angles.values
          .where((angle) => math.cos(angle + candidate) < 0)
          .length;
      final imbalance = (leftCount * 2 - active.length).abs();
      if (imbalance < bestImbalance ||
          (imbalance == bestImbalance && candidate.abs() < rotation.abs())) {
        bestImbalance = imbalance;
        rotation = candidate;
      }
    }
    startAngle += rotation;
    for (final index in active) {
      angles[index] = angles[index]! + rotation;
    }
    int compare(int a, int b) =>
        math.sin(angles[a]!).compareTo(math.sin(angles[b]!));
    left = active.where((i) => math.cos(angles[i]!) < 0).toList()
      ..sort(compare);
    right = active.where((i) => math.cos(angles[i]!) >= 0).toList()
      ..sort(compare);
  }

  double height(double width, TextScaler scaler) {
    if (active.isEmpty) return 120;
    final labelHeight = scaler.scale(9) * 2.4 + scaler.scale(11) * 1.2 + 3;
    return math.max(
      math.min(width * .5, 180.0) + 8,
      math.max(left.length, right.length) * (labelHeight + 4) + 4,
    );
  }
}

class _DonutLabel {
  final double top, angle;
  final bool right;
  const _DonutLabel(this.top, this.right, this.angle);
  @override
  bool operator ==(Object other) =>
      other is _DonutLabel &&
      other.top == top &&
      other.right == right &&
      other.angle == angle;
  @override
  int get hashCode => Object.hash(top, right, angle);
}

class _ConnectorPainter extends CustomPainter {
  final Map<int, _DonutLabel> labels;
  final List<Color> colors;
  final double diameter;
  _ConnectorPainter({
    required this.labels,
    required this.colors,
    required this.diameter,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final entry in labels.entries) {
      final label = entry.value;
      final side =
          labels.entries.where((e) => e.value.right == label.right).toList()
            ..sort((a, b) => a.value.top.compareTo(b.value.top));
      final rank = side.indexWhere((e) => e.key == entry.key);
      final direction = Offset(math.cos(label.angle), math.sin(label.angle));
      final radius = diameter / 2;
      final edge = center + direction * (radius + .5);
      final outside = center + direction * (radius + 4);
      final y = label.top + 12;
      // Downward leaders use outer tracks first; upward leaders use inner
      // tracks first. Sorted endpoints then never cross another leader.
      final lane = y >= outside.dy ? side.length - rank : rank + 1;
      final gap = math.max(
        2.0,
        (size.width * .30 - radius - 2) / (side.length + 1),
      );
      final railX =
          center.dx + (label.right ? 1 : -1) * (radius + 2 + gap * lane);
      final labelX = label.right ? size.width * .80 : size.width * .20;
      // Move radially out, then horizontally away from the circle before
      // changing Y. Every connector segment stays outside the donut.
      final path = Path()
        ..moveTo(edge.dx, edge.dy)
        ..lineTo(outside.dx, outside.dy)
        ..lineTo(railX, outside.dy)
        ..lineTo(railX, y)
        ..lineTo(labelX, y);
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[entry.key].withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      !mapEquals(old.labels, labels) ||
      !listEquals(old.colors, colors) ||
      old.diameter != diameter;
}

/// Reveals the ring clockwise once when this chart enters the widget tree.
class _DonutEntrance extends StatelessWidget {
  final Widget child;
  const _DonutEntrance({required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, progress, chart) => IgnorePointer(
        ignoring: progress < 1,
        child: ClipPath(clipper: _DonutSweepClipper(progress), child: chart),
      ),
    );
  }
}

class _DonutSweepClipper extends CustomClipper<Path> {
  final double progress;
  const _DonutSweepClipper(this.progress);
  @override
  Path getClip(Size size) {
    if (progress >= 1) return Path()..addRect(Offset.zero & size);
    if (progress <= 0) return Path();
    final center = size.center(Offset.zero);
    final radius =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    return Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
      )
      ..close();
  }

  @override
  bool shouldReclip(_DonutSweepClipper oldClipper) =>
      progress != oldClipper.progress;
}
