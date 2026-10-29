import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/data_share/data_share_controller.dart';
import '../../shared/app_notification.dart';

class PairingPinDialog extends StatefulWidget {
  final String networkName;
  final Future<void> Function(String) onConnect;
  const PairingPinDialog({
    super.key,
    required this.networkName,
    required this.onConnect,
  });
  @override
  State<PairingPinDialog> createState() => _PairingPinDialogState();
}

class _PairingPinDialogState extends State<PairingPinDialog> {
  final fields = List.generate(6, (_) => TextEditingController());
  final focus = List.generate(6, (_) => FocusNode());
  bool connecting = false;
  String? error;
  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    for (final node in focus) {
      node.dispose();
    }
    super.dispose();
  }

  void changed(int index, String value) {
    if (value.length > 1) {
      for (var i = 0; i < value.length && index + i < 6; i++) {
        fields[index + i].text = value[i];
      }
      focus[(index + value.length).clamp(0, 5)].requestFocus();
    } else if (value.isNotEmpty && index < 5) {
      focus[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      focus[index - 1].requestFocus();
    }
    setState(() => error = null);
  }

  Future<void> connect() async {
    if (connecting) return;
    final pin = fields.map((field) => field.text).join();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => error = 'Enter all six digits.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      await widget.onConnect(pin);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = DataShareController.errorMessage(failure);
          connecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !connecting,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: context.appColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: green,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Enter 6-digit PIN',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Connect to ${widget.networkName}',
                style: TextStyle(fontSize: 12, color: context.appColors.muted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: ValueKey('pairing-pin-$i'),
                        controller: fields[i],
                        focusNode: focus[i],
                        enabled: !connecting,
                        autofocus: i == 0,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          semanticCounterText: 'PIN digit ${i + 1} of 6',
                        ),
                        onChanged: (value) => changed(i, value),
                        onSubmitted: (_) => connect(),
                      ),
                    ),
                  ],
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                AppNotificationCard(message: error!, isError: true),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: connecting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: connecting ? null : connect,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: connecting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_rounded, size: 18),
                      label: Text(
                        connecting ? 'Connecting...' : 'Connect',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
