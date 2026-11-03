import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../services/ai/online_ai_settings.dart';
import '../../services/ai/online_ai_client.dart';

class OnlineApiKeyDialog extends ConsumerStatefulWidget {
  final OnlineAiProvider provider;
  const OnlineApiKeyDialog({super.key, required this.provider});

  @override
  ConsumerState<OnlineApiKeyDialog> createState() => _OnlineApiKeyDialogState();
}

class _OnlineApiKeyDialogState extends ConsumerState<OnlineApiKeyDialog> {
  final controller = TextEditingController();
  bool loading = true, busy = false, visible = false, saved = false;
  bool success = false, loadFailed = false;
  String? message;
  OnlineAiModels? selectedModels;
  OnlineAiClient? testClient;
  String? testProgress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final key = await ref.read(onlineAiKeysProvider).read(widget.provider);
      final models = await ref
          .read(onlineAiKeysProvider)
          .models(widget.provider);
      if (!mounted) return;
      controller.text = key ?? '';
      setState(() {
        saved = key?.isNotEmpty == true;
        selectedModels = models;
        success = models != null;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
          message =
              'Could not read secure storage. Close this dialog and try again.';
        });
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      busy = true;
      message = null;
      success = false;
    });
    try {
      await ref.read(onlineAiKeysProvider).clearValidation(widget.provider);
      ref.invalidate(onlineAiReadyProvider(widget.provider));
      testClient = ref.read(onlineAiClientFactoryProvider)(
        widget.provider,
        controller.text,
      );
      final models = await testClient!.checkConnection(
        onProgress: (value) {
          if (mounted) setState(() => testProgress = value);
        },
      );
      await ref
          .read(onlineAiKeysProvider)
          .save(
            widget.provider,
            controller.text,
            validated: true,
            models: models,
          );
      ref.invalidate(onlineAiHasKeyProvider(widget.provider));
      ref.invalidate(onlineAiReadyProvider(widget.provider));
      if (mounted) {
        setState(() {
          success = true;
          saved = true;
          selectedModels = models;
          message = widget.provider == OnlineAiProvider.claude
              ? 'Success! Claude expense extraction is ready. Speech uses on-device Whisper.'
              : 'Success! Live speech and expense models are tested and locked. Your key has been saved.';
        });
      }
    } on OnlineAiConnectionException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not test the connection. Please try again.',
        );
      }
    } finally {
      testClient?.close();
      testClient = null;
      if (mounted) {
        setState(() {
          busy = false;
          testProgress = null;
        });
      }
    }
  }

  Future<void> _save({bool remove = false}) async {
    final validated = success;
    setState(() {
      busy = true;
      message = null;
      success = false;
    });
    try {
      final keys = ref.read(onlineAiKeysProvider);
      if (remove) {
        await keys.remove(widget.provider);
      } else {
        await keys.save(
          widget.provider,
          controller.text,
          validated: validated,
          models: selectedModels,
        );
      }
      ref.invalidate(onlineAiHasKeyProvider(widget.provider));
      ref.invalidate(onlineAiReadyProvider(widget.provider));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not update secure storage. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    testClient?.close();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && !busy && !loadFailed;
    final hasKey = controller.text.trim().isNotEmpty;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: context.appColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.appColors.tint,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.key_outlined,
                        size: 23,
                        color: green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.provider.label} API Key',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Add your own key. It is stored securely on this device.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.muted,
                  ),
                ),
                const SizedBox(height: 14),
                if (loading)
                  const LinearProgressIndicator()
                else
                  TextField(
                    controller: controller,
                    enabled: enabled,
                    obscureText: !visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'Paste your ${widget.provider.label} API key',
                      suffixIcon: IconButton(
                        tooltip: visible ? 'Hide key' : 'Show key',
                        onPressed: enabled
                            ? () => setState(() => visible = !visible)
                            : null,
                        icon: Icon(
                          visible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {
                      message = null;
                      success = false;
                    }),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    side: BorderSide(color: context.appColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: enabled && hasKey ? _test : null,
                  child: Text(busy ? 'Please wait…' : 'Test Connection'),
                ),
                if (saved) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: enabled ? () => _save(remove: true) : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Remove Key'),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  widget.provider == OnlineAiProvider.claude
                      ? 'Tests sample transactions with Claude. Speech uses on-device Whisper. Your provider may charge for the test.'
                      : 'Automatically selects models and tests a built-in speech sample and sample transactions. Your provider may charge for the test.',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.muted,
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      message!,
                      semanticsLabel: message,
                      style: TextStyle(
                        fontSize: 12,
                        color: success ? green : red,
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (busy && testProgress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      testProgress!,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: BorderSide(color: context.appColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: enabled && hasKey ? () => _save() : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Save',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
