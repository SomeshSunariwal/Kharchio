import 'package:flutter/material.dart';

import 'modern_date_picker.dart';

Future<DateTime?> showExpenseDatePicker(
  BuildContext context,
  DateTime initialDate,
) async {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => ModernDatePicker(initialDate: initialDate),
  );
}
