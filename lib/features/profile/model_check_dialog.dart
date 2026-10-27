import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/ai/model_manager.dart';
import '../../services/ai/model_validator.dart';

/// Keeps navigation blocked until inference and model cleanup have completed.
class ModelCheckDialog extends StatefulWidget {
  final OfflineModelKind kind;
  final Future<OfflineModels> Function() loadModels;
  final int processingMode;
  final String speechLanguage;

  const ModelCheckDialog({
    super.key,
    required this.kind,
    required this.loadModels,
    required this.processingMode,
    required this.speechLanguage,
  });

  @override
  State<ModelCheckDialog> createState() => _ModelCheckDialogState();
}

class _ModelCheckDialogState extends State<ModelCheckDialog> {
  String progress = 'Preparing bundled models…';
  ModelCheckResult? result;
  String? error;

  bool get finished => result != null || error != null;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final models = await widget.loadModels();
      final checkResult = await ModelValidator().check(
        widget.kind,
        models,
        (value) {
          if (mounted) setState(() => progress = value);
        },
        processingMode: widget.processingMode,
        speechLanguage: widget.speechLanguage,
      );
      if (mounted) {
        setState(() => result = checkResult);
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final check = result;
    final isWhisper = widget.kind == OfflineModelKind.whisper;
    final statusColor = error != null
        ? Theme.of(context).colorScheme.error
        : green;
    return PopScope(
      canPop: finished,
      child: AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                !finished
                    ? (isWhisper
                          ? Icons.graphic_eq
                          : Icons.auto_awesome_outlined)
                    : error != null
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: statusColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWhisper ? 'Whisper check' : 'Qwen check',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    !finished
                        ? 'Checking model…'
                        : error != null
                        ? 'Check failed'
                        : 'Check passed',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!finished) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(progress, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    'The first check can take longer while GPU kernels prepare.',
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
                if (error != null) ...[
                  const Text('The model could not complete the sample check.'),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Error details',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      SelectableText(
                        error!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (check != null) ...[
                  Text(
                    check.summary,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  _panel(
                    context,
                    Column(
                      children: [
                        _detail(context, 'Model', check.model),
                        const SizedBox(height: 10),
                        _detail(context, 'Ran on', check.backend),
                        const SizedBox(height: 10),
                        _detail(
                          context,
                          'Total check time',
                          '${(check.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} s',
                        ),
                      ],
                    ),
                  ),
                  if (check.usedFallback) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.noticeBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: colors.noticeForeground,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'NPU unavailable for this check. Used ${check.backend} instead.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: colors.noticeForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    isWhisper ? 'SAMPLE TRANSCRIPT' : 'SAMPLE EXPENSES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _panel(
                    context,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        check.output,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Model memory released · No expenses saved',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: colors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: finished ? () => Navigator.of(context).pop() : null,
              child: Text(finished ? 'Done' : 'Checking…'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.appColors.field,
      border: Border.all(color: context.appColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  Widget _detail(BuildContext context, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: context.appColors.muted),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
