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
  final bool enabled;
  final bool matchModelRows;
  const PreferenceDropdownRow({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.matchModelRows = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final standardWidth = (constraints.maxWidth * .56).clamp(120.0, 200.0);
      final controlWidth = matchModelRows ? standardWidth / 2 : standardWidth;
      return Opacity(
        opacity: enabled ? 1 : 0.45,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            children: [
              Icon(
                icon,
                size: matchModelRows ? 20 : 16,
                color: enabled && matchModelRows
                    ? green
                    : context.appColors.muted,
              ),
              SizedBox(width: matchModelRows ? 10 : 8),
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
                    enabled: enabled,
                    value: value,
                    label: label,
                    compact: true,
                    fitMenuToContent: matchModelRows,
                    options: options,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
