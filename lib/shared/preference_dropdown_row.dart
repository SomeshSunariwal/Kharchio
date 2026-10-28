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
  final String? description;
  final bool descriptionError;
  const PreferenceDropdownRow({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.matchModelRows = false,
    this.description,
    this.descriptionError = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Offline rows have 2 px less padding on each side than Preferences.
      final referenceWidth = constraints.maxWidth - (matchModelRows ? 4 : 0);
      final standardWidth = (referenceWidth * .56).clamp(120.0, 200.0);
      final controlWidth = matchModelRows ? standardWidth * .75 : standardWidth;
      return Opacity(
        opacity: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: matchModelRows ? 74 : 54),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: enabled
                            ? context.appColors.ink
                            : context.appColors.muted,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: descriptionError
                              ? red
                              : context.appColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: controlWidth,
                child: Semantics(
                  label: label,
                  child: Opacity(
                    opacity: enabled ? 1 : .45,
                    child: AppDropdown<T>(
                      enabled: enabled,
                      value: value,
                      label: label,
                      compact: true,

                      options: options,
                      onChanged: onChanged,
                    ),
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
