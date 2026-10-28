import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Read-only percentages with category selection; no amount tooltips.
class CategoryPercentageBar extends StatelessWidget {
  final List<double> totals;
  final List<Color> colors;
  final List<String> names;
  final int? selectedIndex;
  final ValueChanged<int>? onCategorySelected;
  const CategoryPercentageBar({
    super.key,
    required this.totals,
    required this.colors,
    required this.names,
    this.selectedIndex,
    this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final total = totals.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            for (var i = 0; i < totals.length; i++)
              if (totals[i] > 0)
                Expanded(
                  flex: math.max(1, (totals[i] / total * 100000).round()),
                  child: Semantics(
                    label:
                        '${names[i]} ${(totals[i] / total * 100).round()} percent',
                    selected: selectedIndex == i,
                    button: onCategorySelected != null,
                    child: Material(
                      borderRadius: BorderRadius.circular(
                        selectedIndex == i ? 6 : 0,
                      ),
                      clipBehavior: Clip.antiAlias,
                      color: selectedIndex == null || selectedIndex == i
                          ? colors[i]
                          : colors[i].withValues(alpha: .3),
                      child: InkWell(
                        onTap: onCategorySelected == null
                            ? null
                            : () => onCategorySelected!(i),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: selectedIndex == i
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${(totals[i] / total * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: colors[i].computeLuminance() > .45
                                        ? const Color(0xFF15202C)
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
