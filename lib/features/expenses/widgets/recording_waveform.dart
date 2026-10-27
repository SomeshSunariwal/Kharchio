import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Owns animation and repaints independently from the recording workflow.
class RecordingWaveform extends StatefulWidget {
  const RecordingWaveform({
    super.key,
    required this.active,
    required this.level,
  });
  final bool active;
  final ValueListenable<double> level;

  @override
  State<RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<RecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  void _updateAnimation() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!phase.isAnimating) phase.repeat();
    } else {
      phase.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant RecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(double.infinity, 46),
      painter: _WavePainter(phase, widget.active, widget.level),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.phase, this.active, this.level)
    : super(repaint: Listenable.merge([phase, level]));

  final Animation<double> phase;
  final bool active;
  final ValueListenable<double> level;
  static const count = 35;
  static final envelopes = List.generate(
    count,
    (i) => math.sin(math.pi * i / (count - 1)),
  );
  static final paints = List.generate(
    count,
    (i) => Paint()
      ..color = red.withValues(alpha: .35 + .65 * envelopes[i])
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count; i++) {
      final h = active
          ? 5 +
                level.value *
                    envelopes[i] *
                    (9 +
                        24 *
                            (.5 +
                                .5 *
                                    math.sin(
                                      i * 1.7 + phase.value * 2 * math.pi,
                                    )))
          : 5.0;
      final x = (i + .5) * size.width / count;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paints[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.phase != phase || old.active != active || old.level != level;
}
