import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppDropdownOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const AppDropdownOption(this.value, this.label, {this.icon});
}

/// Shared animated select control for every application dropdown.
class AppDropdown<T> extends StatefulWidget {
  final T value;
  final String label;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool compact;
  final IconData? leadingIcon;
  const AppDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.compact = false,
    this.leadingIcon,
  });

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool open = false;

  void setOpen(bool value) {
    if (mounted) setState(() => open = value);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = context.appColors;
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      final selection = widget.options
          .where((option) => option.value == widget.value)
          .firstOrNull;
      final maxMenuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
        1.0,
        300.0,
      );
      final menuWidth = constraints.maxWidth.clamp(
        maxMenuWidth < 180 ? maxMenuWidth : 180.0,
        maxMenuWidth,
      );
      return PopupMenuButton<T>(
        tooltip: widget.label,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        padding: EdgeInsets.zero,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.line),
        ),
        constraints: BoxConstraints(
          minWidth: menuWidth,
          maxWidth: menuWidth,
          maxHeight: 300,
        ),
        popUpAnimationStyle: reducedMotion
            ? AnimationStyle.noAnimation
            : AnimationStyle(
                duration: const Duration(milliseconds: 200),
                reverseDuration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
        onOpened: () => setOpen(true),
        onCanceled: () => setOpen(false),
        onSelected: (value) {
          setOpen(false);
          widget.onChanged(value);
        },
        itemBuilder: (context) => [
          _ScrollableDropdownEntry<T>(
            options: widget.options,
            value: widget.value,
            width: menuWidth,
          ),
        ],
        child: Semantics(
          label: widget.label,
          value: selection?.label,
          button: true,
          child: InputDecorator(
            isFocused: open,
            decoration: InputDecoration(
              labelText: widget.compact ? null : widget.label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelStyle: TextStyle(fontSize: 12, color: colors.muted),
              isDense: true,
              isCollapsed: widget.compact,
              filled: true,
              fillColor: colors.field,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: widget.compact ? 8 : 10,
              ),
              constraints: widget.compact
                  ? BoxConstraints.tightFor(
                      height:
                          36 +
                          (MediaQuery.textScalerOf(context).scale(12) - 12)
                                  .clamp(0, 20) *
                              2,
                    )
                  : const BoxConstraints(minHeight: 42),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: green, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (widget.leadingIcon != null) ...[
                  Icon(widget.leadingIcon, size: 17, color: colors.muted),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    selection?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.compact ? 12 : 13,
                      color: colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: open ? .5 : 0,
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: open ? green : colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Owns the popup's scroll controller, including during its closing animation.
class _ScrollableDropdownEntry<T> extends PopupMenuEntry<T> {
  final List<AppDropdownOption<T>> options;
  final T value;
  final double width;
  const _ScrollableDropdownEntry({
    required this.options,
    required this.value,
    required this.width,
  });

  @override
  double get height => (options.length * 42.0).clamp(0.0, 284.0);
  @override
  bool represents(T? value) => options.any((option) => option.value == value);
  @override
  State<_ScrollableDropdownEntry<T>> createState() =>
      _ScrollableDropdownEntryState<T>();
}

class _ScrollableDropdownEntryState<T>
    extends State<_ScrollableDropdownEntry<T>> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 3,
        radius: const Radius.circular(3),
        child: ListView.builder(
          controller: controller,
          primary: false,
          padding: const EdgeInsets.only(left: 8, right: 12),
          itemExtent: 42,
          itemCount: widget.options.length,
          itemBuilder: (context, index) {
            final option = widget.options[index];
            final selected = option.value == widget.value;
            return Semantics(
              selected: selected,
              button: true,
              child: Material(
                color: selected
                    ? green.withValues(alpha: .09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, option.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        if (option.icon != null) ...[
                          Icon(
                            option.icon,
                            size: 18,
                            color: selected ? green : colors.muted,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(fontSize: 13, color: colors.ink),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: green,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
