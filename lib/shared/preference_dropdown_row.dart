import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'app_dropdown.dart';

/// Only the control on the right opens the menu; the label stays separate.
class PreferenceDropdownRow<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  const PreferenceDropdownRow({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controlWidth = (constraints.maxWidth * .56).clamp(120.0, 200.0);
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          children: [
            Icon(icon, size: 16, color: context.appColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: controlWidth,
              child: Semantics(
                label: label,
                child: AppDropdown<T>(
                  value: value,
                  label: label,
                  compact: true,
                  options: options,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
