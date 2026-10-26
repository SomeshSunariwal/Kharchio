import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Only the selected destination displays its label, beside its existing icon.
class ActiveTextNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const ActiveTextNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const labels = ['Dashboard', 'Analysis', 'Profile'];
  static const icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.person_outline,
  ];
  static const selectedIcons = [
    Icons.home_rounded,
    Icons.calendar_month,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width:
                            constraints.maxWidth *
                            (i == selectedIndex ? .5 : .25),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Semantics(
                          selected: i == selectedIndex,
                          button: true,
                          label: labels[i],
                          excludeSemantics: true,
                          child: Tooltip(
                            message: labels[i],
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: i == selectedIndex
                                    ? green.withValues(
                                        alpha: colors.dark ? .16 : .1,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => onSelected(i),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          i == selectedIndex
                                              ? selectedIcons[i]
                                              : icons[i],
                                          size: 23,
                                          color: i == selectedIndex
                                              ? green
                                              : colors.muted,
                                        ),
                                        if (i == selectedIndex) ...[
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              labels[i],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: green,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
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
            ),
          ),
        ),
      ),
    );
  }
}
