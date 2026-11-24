import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import 'app_dropdown.dart';
import 'widgets.dart';

/// Shared transaction date dialog, including month/year navigation.
class ModernDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final bool includeTime;
  final DateTime? firstDate;
  const ModernDatePicker({
    super.key,
    required this.initialDate,
    this.includeTime = false,
    this.firstDate,
  });
  @override
  State<ModernDatePicker> createState() => _ModernDatePickerState();
}

class _ModernDatePickerState extends State<ModernDatePicker> {
  double get controlHeight =>
      36 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24);
  DateTime get firstDate =>
      DateUtils.dateOnly(widget.firstDate ?? DateTime(2000));
  static final lastDate = DateTime(2100);
  late DateTime selected;
  late DateTime month;
  late double monthSelectorWidth;
  bool choosingYear = false;
  late int hour = widget.initialDate.hour;
  late int minute = widget.initialDate.minute;

  int get calendarCells {
    final firstWeekday = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final offset = (month.weekday % 7 - firstWeekday + 7) % 7;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return ((offset + days) / 7).ceil() * 7;
  }

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final monthLabel = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widestMonth = 0.0;
    for (var value = 1; value <= 12; value++) {
      monthLabel.text = TextSpan(
        text: DateFormat('MMMM yyyy').format(DateTime(8888, value)),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
      );
      monthLabel.layout();
      if (monthLabel.width > widestMonth) widestMonth = monthLabel.width;
    }
    monthLabel.dispose();
    monthSelectorWidth = widestMonth.ceilToDouble() + 48;
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
                        widget.includeTime
                            ? 'Select date and time'
                            : 'Select date',
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
                          key: const ValueKey('calendar-month-selector'),
                          onPressed: () =>
                              setState(() => choosingYear = !choosingYear),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.ink,
                            backgroundColor: Colors.transparent,
                            side: BorderSide.none,
                            minimumSize: Size(
                              monthSelectorWidth,
                              controlHeight,
                            ),
                            maximumSize: Size(
                              monthSelectorWidth,
                              double.infinity,
                            ),
                            visualDensity: VisualDensity.standard,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
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
                    height: 30 + calendarCells / 7 * 40,
                    child: DividerTheme(
                      data: const DividerThemeData(
                        color: Colors.transparent,
                        space: 0,
                        thickness: 0,
                      ),
                      child: YearPicker(
                        firstDate: firstDate,
                        lastDate: lastDate,
                        selectedDate: month,
                        onChanged: (value) => setState(() {
                          final target = bounded(
                            DateTime(
                              value.year,
                              value.year == lastDate.year ? 1 : month.month,
                            ),
                          );
                          month = DateTime(target.year, target.month);
                          choosingYear = false;
                        }),
                      ),
                    ),
                  )
                else
                  _calendar(),
                if (widget.includeTime) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: colors.line),
                  const SizedBox(height: 16),
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: AppDropdown<int>(
                          label: 'Hour',
                          value: hour % 12 == 0 ? 12 : hour % 12,
                          options: [
                            for (var value = 1; value <= 12; value++)
                              AppDropdownOption(value, '$value'),
                          ],
                          onChanged: (value) => setState(
                            () => hour = value % 12 + (hour >= 12 ? 12 : 0),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AppDropdown<int>(
                          label: 'Minute',
                          value: minute,
                          options: [
                            for (var value = 0; value < 60; value++)
                              AppDropdownOption(
                                value,
                                value.toString().padLeft(2, '0'),
                              ),
                          ],
                          onChanged: (value) => setState(() => minute = value),
                        ),
                      ),
                      Expanded(
                        child: AppDropdown<bool>(
                          label: 'AM / PM',
                          value: hour >= 12,
                          options: const [
                            AppDropdownOption(false, 'AM'),
                            AppDropdownOption(true, 'PM'),
                          ],
                          onChanged: (value) => setState(
                            () => hour = hour % 12 + (value ? 12 : 0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Divider(height: 1, color: colors.line),
                const SizedBox(height: 10),
                if (!widget.includeTime)
                  Row(
                    children: [
                      TextButton(
                        onPressed: _selectToday,
                        style: TextButton.styleFrom(foregroundColor: green),
                        child: const Text(
                          'Today',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.muted,
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
                  )
                else
                  DialogActionRow(
                    onSecondary: () => Navigator.pop(context),
                    onPrimary: () => Navigator.pop(
                      context,
                      DateTime(
                        selected.year,
                        selected.month,
                        selected.day,
                        hour,
                        minute,
                      ),
                    ),
                    primaryLabel: const Text('Apply'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectToday() => setState(() {
    selected = bounded(DateUtils.dateOnly(DateTime.now()));
    month = DateTime(selected.year, selected.month);
    choosingYear = false;
  });

  Widget _arrow(String label, IconData icon, int offset) {
    final next = DateTime(month.year, month.month + offset);
    final monthEnd = DateTime(next.year, next.month + 1, 0);
    final available = !monthEnd.isBefore(firstDate) && !next.isAfter(lastDate);
    return IconButton(
      tooltip: label,
      onPressed: available ? () => setState(() => month = next) : null,
      style: IconButton.styleFrom(
        backgroundColor: context.appColors.field,
        foregroundColor: context.appColors.ink,
        side: BorderSide(color: context.appColors.line),
        fixedSize: Size.square(controlHeight),
        minimumSize: Size.square(controlHeight),
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      icon: Icon(icon, size: 19),
    );
  }

  Widget _calendar() {
    final locale = MaterialLocalizations.of(context);
    final colors = context.appColors;
    final offset = (month.weekday % 7 - locale.firstDayOfWeekIndex + 7) % 7;
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = calendarCells;
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
