import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<DateTime?> showExpenseDatePicker(
  BuildContext context,
  DateTime initialDate,
) async {
  var selected = DateUtils.dateOnly(initialDate);
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: context.appColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 312,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CalendarDatePicker(
                  initialDate: selected,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onDateChanged: (value) => selected = value,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, selected),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
