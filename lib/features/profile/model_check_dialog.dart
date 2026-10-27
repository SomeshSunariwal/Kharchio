import 'package:flutter/material.dart';

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
  String? result;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final models = await widget.loadModels();
      final message = await ModelValidator().check(
        widget.kind,
        models,
        (value) {
          if (mounted) setState(() => progress = value);
        },
        processingMode: widget.processingMode,
        speechLanguage: widget.speechLanguage,
      );
      if (mounted) {
        setState(
          () =>
              result = '$message\n\nModel weights released. No expenses saved.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          failed = true;
          result = 'Model check failed.\n\n$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: result != null,
    child: AlertDialog(
      title: Text(
        '${widget.kind == OfflineModelKind.whisper ? 'Whisper' : 'Qwen'} check',
      ),
      content: SingleChildScrollView(
        child: result == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(progress),
                  const SizedBox(height: 8),
                  const Text(
                    'The first check can take longer while GPU kernels prepare.',
                  ),
                ],
              )
            : Text('${failed ? '' : 'Check passed\n\n'}$result'),
      ),
      actions: [
        TextButton(
          onPressed: result == null ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
