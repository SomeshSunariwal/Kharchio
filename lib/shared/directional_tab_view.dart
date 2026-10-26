import 'package:flutter/material.dart';

/// Moves both pages in the direction of travel while retaining each tab's state.
class DirectionalTabView extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const DirectionalTabView({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<DirectionalTabView> createState() => _DirectionalTabViewState();
}

class _DirectionalTabViewState extends State<DirectionalTabView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<double> _from;
  late List<double> _to;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    _from = List.generate(
      widget.children.length,
      (i) => i == widget.index
          ? 0.0
          : i < widget.index
          ? -1.0
          : 1.0,
    );
    _to = List.of(_from);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant DirectionalTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;

    final progress = Curves.easeOutCubic.transform(_controller.value);
    final direction = widget.index > oldWidget.index ? 1.0 : -1.0;
    // Start from the current visual positions if another tab is tapped mid-slide.
    _from = List.generate(widget.children.length, (i) {
      final current = _from[i] + (_to[i] - _from[i]) * progress;
      if (current.abs() < .999) return current;
      if (i == widget.index) return direction;
      return i < widget.index ? -1.0 : 1.0;
    });
    _to = List.generate(
      widget.children.length,
      (i) => i == widget.index
          ? 0.0
          : i < widget.index
          ? -1.0
          : 1.0,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(_controller.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              Offstage(
                offstage:
                    i != widget.index &&
                    (!_controller.isAnimating || _from[i].abs() >= .999),
                child: TickerMode(
                  enabled: i == widget.index,
                  child: IgnorePointer(
                    ignoring: i != widget.index,
                    child: ExcludeSemantics(
                      excluding: i != widget.index,
                      child: FractionalTranslation(
                        translation: Offset(
                          _from[i] + (_to[i] - _from[i]) * progress,
                          0,
                        ),
                        child: RepaintBoundary(child: widget.children[i]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
