import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

/// Shared transaction date dialog, including month/year navigation.
class ModernDatePicker extends StatefulWidget {
  final DateTime initialDate;
  const ModernDatePicker({super.key, required this.initialDate});
  @override
  State<ModernDatePicker> createState() => _ModernDatePickerState();
}

class _ModernDatePickerState extends State<ModernDatePicker> {
  static final firstDate = DateTime(2000);
  static final lastDate = DateTime(2100);
  late DateTime selected;
  late DateTime month;
  bool choosingYear = false;

  DateTime bounded(DateTime value) => value.isBefore(firstDate)
      ? firstDate
      : value.isAfter(lastDate)
      ? lastDate
      : value;

  @override
  void initState() {
    super.initState();
    selected = bounded(DateUtils.dateOnly(widget.initialDate));
    month = DateTime(selected.year, selected.month);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select date',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close date picker',
                      onPressed: () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat('EEE, d MMM yyyy').format(selected),
                      key: const ValueKey('selected-date-heading'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.line),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => choosingYear = !choosingYear),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.ink,
                            backgroundColor: colors.field,
                            side: BorderSide(color: colors.line),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  choosingYear
                                      ? 'Select year'
                                      : DateFormat('MMMM yyyy').format(month),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                choosingYear
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (choosingYear)
                      IconButton(
                        tooltip: 'Back to calendar',
                        onPressed: () => setState(() => choosingYear = false),
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                      )
                    else ...[
                      _arrow('Previous month', Icons.chevron_left, -1),
                      const SizedBox(width: 6),
                      _arrow('Next month', Icons.chevron_right, 1),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (choosingYear)
                  SizedBox(
                    height: 240,
                    child: YearPicker(
                      firstDate: firstDate,
                      lastDate: lastDate,
                      selectedDate: month,
                      onChanged: (value) => setState(() {
                        month = DateTime(
                          value.year,
                          value.year == lastDate.year ? 1 : month.month,
                        );
                        choosingYear = false;
                      }),
                    ),
                  )
                else
                  _calendar(),
                const SizedBox(height: 10),
                Divider(height: 1, color: colors.line),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        selected = bounded(DateUtils.dateOnly(DateTime.now()));
                        month = DateTime(selected.year, selected.month);
                        choosingYear = false;
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: green,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text(
                        'Today',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.muted,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrow(String label, IconData icon, int offset) {
    final next = DateTime(month.year, month.month + offset);
    final available = !next.isBefore(firstDate) && !next.isAfter(lastDate);
    return IconButton(
      tooltip: label,
      onPressed: available ? () => setState(() => month = next) : null,
      style: IconButton.styleFrom(
        backgroundColor: context.appColors.field,
        foregroundColor: context.appColors.ink,
        side: BorderSide(color: context.appColors.line),
        minimumSize: const Size(34, 34),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 19),
    );
  }

  Widget _calendar() {
    final locale = MaterialLocalizations.of(context);
    final colors = context.appColors;
    final offset = (month.weekday % 7 - locale.firstDayOfWeekIndex + 7) % 7;
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = ((offset + count) / 7).ceil() * 7;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: Center(
                    child: Text(
                      locale.narrowWeekdays[(locale.firstDayOfWeekIndex + i) %
                          7],
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: cells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 40,
          ),
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > count) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, day);
            final enabled =
                !date.isBefore(firstDate) && !date.isAfter(lastDate);
            final active = DateUtils.isSameDay(date, selected);
            return Padding(
              padding: const EdgeInsets.all(2),
              child: Semantics(
                label: locale.formatFullDate(date),
                selected: active,
                button: true,
                enabled: enabled,
                excludeSemantics: true,
                child: Material(
                  color: active ? green : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: ValueKey('calendar-${date.year}-${date.month}-$day'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: enabled
                        ? () => setState(() => selected = date)
                        : null,
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: active
                              ? Colors.white
                              : enabled
                              ? colors.ink
                              : colors.muted.withValues(alpha: .4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
