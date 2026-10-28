import 'dart:math' as math;

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
  final bool enabled;
  final bool scrollIntoViewOnOpen;
  final IconData? leadingIcon;
  const AppDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
    this.scrollIntoViewOnOpen = false,
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
      final menuWidth = constraints.maxWidth.clamp(1.0, maxMenuWidth);
      return InkWell(
        onTap: !widget.enabled
            ? null
            : () async {
                if (open) return;
                setOpen(true);
                if (widget.scrollIntoViewOnOpen) {
                  await Scrollable.ensureVisible(
                    context,
                    alignment: .25,
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                  );
                  if (!context.mounted) return;
                }
                final box = context.findRenderObject()! as RenderBox;
                final anchor = box.localToGlobal(Offset.zero) & box.size;
                final value = await Navigator.of(context).push<T>(
                  _DropdownRoute<T>(
                    anchor: anchor,
                    width: menuWidth,
                    reducedMotion: reducedMotion,
                    barrierText: MaterialLocalizations.of(context)
                        .modalBarrierDismissLabel,
                    content: InheritedTheme.captureAll(
                      context,
                      _ScrollableDropdownEntry<T>(
                        options: widget.options,
                        value: widget.value,
                        width: menuWidth,
                      ),
                    ),
                    color: colors.surface,
                    border: colors.line,
                  ),
                );
                if (!mounted) return;
                setOpen(false);
                if (value != null) widget.onChanged(value);
              },
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          enabled: widget.enabled,
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
  ScrollController? controller;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = math.min(widget.height, constraints.maxHeight);
        final selectedIndex = widget.options.indexWhere(
          (option) => option.value == widget.value,
        );
        final maxOffset = math.max(
          0.0,
          widget.options.length * 42.0 - viewportHeight,
        );
        final scroll = controller ??= ScrollController(
          initialScrollOffset: (math.max(0, selectedIndex) * 42.0).clamp(
            0.0,
            maxOffset,
          ),
        );
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: SizedBox(
            width: widget.width,
            height: viewportHeight,
            child: Scrollbar(
              controller: scroll,
              interactive: true,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 3,
              radius: const Radius.circular(3),
              child: ListView.builder(
                controller: scroll,
                primary: false,
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.ink,
                                  ),
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
          ),
        );
      },
    );
  }
}

/// Reveals every menu vertically from its top edge, without horizontal scaling.
class _DropdownRoute<T> extends PopupRoute<T> {
  final Rect anchor;
  final double width;
  final bool reducedMotion;
  final String barrierText;
  final Widget content;
  final Color color;
  final Color border;
  _DropdownRoute({
    required this.anchor,
    required this.width,
    required this.reducedMotion,
    required this.barrierText,
    required this.content,
    required this.color,
    required this.border,
  });
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => barrierText;
  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 200);
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 150);
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final bottom =
        media.size.height - media.padding.bottom - media.viewInsets.bottom - 8;
    final top = (anchor.bottom + 4)
        .clamp(media.padding.top + 8, bottom - 48)
        .toDouble();
    final left = (anchor.right - width)
        .clamp(8.0, media.size.width - width - 8)
        .toDouble();
    return Stack(
      children: [
        Positioned(
          // Leave room around the reveal so its clip does not cut the shadow.
          top: top - 12,
          left: left - 12,
          width: width + 24,
          child: SizeTransition(
            sizeFactor: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                key: const ValueKey('dropdown-menu-surface'),
                color: color,
                surfaceTintColor: Colors.transparent,
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: .2),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: border),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bottom - top),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
