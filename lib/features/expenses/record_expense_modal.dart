import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/preferences.dart';
import '../../core/categories.dart';
import 'add_expense_screen.dart';

enum RecordingStage { recording, paused, processing, failed }

class RecordExpenseModal extends StatefulWidget {
  const RecordExpenseModal({super.key});
  @override
  State<RecordExpenseModal> createState() => _RecordState();
}

class _RecordState extends State<RecordExpenseModal>
    with SingleTickerProviderStateMixin {
  final text = TextEditingController();
  late final AnimationController wave;
  Timer? timer;
  RecordingStage stage = RecordingStage.recording;
  int seconds = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    wave = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 950),
    )..repeat();
    timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (stage == RecordingStage.recording) setState(() => seconds++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      wave.stop();
    } else if (stage == RecordingStage.recording && !wave.isAnimating) {
      wave.repeat();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    wave.dispose();
    text.dispose();
    super.dispose();
  }

  void toggle() {
    setState(
      () => stage = stage == RecordingStage.paused
          ? RecordingStage.recording
          : RecordingStage.paused,
    );
    if (stage == RecordingStage.recording &&
        !MediaQuery.disableAnimationsOf(context)) {
      wave.repeat();
    } else {
      wave.stop();
    }
  }

  Future<void> process() async {
    setState(() {
      stage = RecordingStage.processing;
      error = null;
    });
    wave.stop();
    // UI-only processing preview. This is a deterministic text helper, not AI.
    await Future<void>.delayed(Duration(milliseconds: 1300));
    if (!mounted) return;
    final values = <ExpenseDraft>[];
    for (final part in text.text.split(RegExp(r'[,;\n]'))) {
      final match = RegExp(
        r'(?:(?:₹|\$|rs\.?|usd|inr)\s*)?(\d+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ).firstMatch(part);
      if (match == null) continue;
      final amount = double.tryParse(match.group(1)!);
      final title = part
          .replaceFirst(match.group(0)!, '')
          .replaceAll(
            RegExp(r'rupees|dollars|रुपये|रुपए', caseSensitive: false),
            '',
          )
          .trim();
      if (amount == null || amount <= 0 || title.isEmpty) continue;
      final lower = title.toLowerCase();
      final category = RegExp('milk|bread|grocery|दूध|सब्जी').hasMatch(lower)
          ? 'Groceries'
          : RegExp('lunch|dinner|food|खाना').hasMatch(lower)
          ? 'Food & Dining'
          : RegExp('bus|taxi|petrol|बस').hasMatch(lower)
          ? 'Transport'
          : RegExp('bill|electric|बिजली').hasMatch(lower)
          ? 'Utilities'
          : 'Others';
      values.add(
        ExpenseDraft(
          id: '${DateTime.now().microsecondsSinceEpoch}-${values.length}',
          title: title,
          amount: amount.toString(),
          category: context.categoryNames.contains(category)
              ? category
              : context.expenseCategories[context.categoryIndex('Others')].name,
        ),
      );
    }
    if (values.isEmpty) {
      setState(() {
        stage = RecordingStage.failed;
        error =
            'Enter a title and amount, e.g. Milk ${context.currency.symbol}120, Lunch ${context.currency.symbol}450.';
      });
      return;
    }
    Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) {
    final processing = stage == RecordingStage.processing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 650),
          child: SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appColors.muted.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Record Expense',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close recording',
                        onPressed: processing
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    'Speak or type what you spent on. Review expense details before saving.',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.appColors.noticeBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'UI preview: microphone and offline AI are not connected. Type comma-separated items to preview editable cards.',
                      style: TextStyle(
                        color: context.appColors.noticeForeground,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: text,
                    minLines: 5,
                    maxLines: 7,
                    maxLength: 500,
                    readOnly: processing,
                    decoration: InputDecoration(
                      hintText:
                          'Milk ${context.currency.symbol}120, Lunch ${context.currency.symbol}450, Bus ${context.currency.symbol}30',
                      fillColor: context.appColors.field,
                    ),
                  ),
                  SizedBox(height: 16),
                  AnimatedSize(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: processing
                        ? Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(20),
                            decoration: _box(),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    color: red,
                                    strokeWidth: 3,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Processing preview…',
                                        style: TextStyle(
                                          color: red,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 5),
                                      Text(
                                        'Preparing typed text for editable cards',
                                        style: TextStyle(
                                          color: context.appColors.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            height: 86,
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            decoration: _box(),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    label: 'Recording waveform preview',
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        size: Size(double.infinity, 58),
                                        painter: _WavePainter(
                                          wave,
                                          stage == RecordingStage.recording,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                IconButton.filled(
                                  tooltip: stage == RecordingStage.paused
                                      ? 'Resume recording preview'
                                      : 'Pause recording preview',
                                  onPressed: toggle,
                                  style: IconButton.styleFrom(
                                    backgroundColor: red.withValues(alpha: .12),
                                    foregroundColor: red,
                                  ),
                                  icon: Icon(
                                    stage == RecordingStage.paused
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                  ),
                                ),
                                SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: 'Stop and process typed text',
                                  onPressed: process,
                                  style: IconButton.styleFrom(
                                    backgroundColor: red,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: Icon(Icons.stop_rounded),
                                ),
                              ],
                            ),
                          ),
                  ),
                  SizedBox(height: 12),
                  if (!processing)
                    Center(
                      child: Text(
                        '${stage == RecordingStage.paused
                            ? 'Ⅱ Paused'
                            : stage == RecordingStage.failed
                            ? 'Try again'
                            : '● Recording preview'} · ${_time(seconds)}',
                        style: TextStyle(color: red, fontSize: 13),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: TextStyle(color: red, fontSize: 12),
                      ),
                    ),
                  if (!processing)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: process,
                          icon: Icon(Icons.auto_awesome_outlined, size: 18),
                          label: Text('Create cards from typed text'),
                        ),
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

  String _time(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  BoxDecoration _box() => BoxDecoration(
    color: red.withValues(alpha: .045),
    border: Border.all(color: red.withValues(alpha: .22)),
    borderRadius: BorderRadius.circular(14),
  );
}

class _WavePainter extends CustomPainter {
  final Animation<double> phase;
  final bool active;
  _WavePainter(this.phase, this.active) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    const count = 35;
    for (var i = 0; i < count; i++) {
      final envelope = math.sin(math.pi * i / (count - 1));
      final h = active
          ? 5 +
                envelope *
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
        Paint()
          ..color = red.withValues(alpha: .35 + .65 * envelope)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.phase != phase || old.active != active;
}
