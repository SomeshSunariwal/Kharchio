import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/app_notification.dart';
import '../../services/data_share/data_share_controller.dart';

class DeviceNameDialog extends StatefulWidget {
  final String initialName;
  final Future<void> Function(String) onSave;
  const DeviceNameDialog({
    super.key,
    required this.initialName,
    required this.onSave,
  });

  @override
  State<DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<DeviceNameDialog> {
  late final name = TextEditingController(text: widget.initialName);
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(name.text);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = DataShareController.errorMessage(failure);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Dialog(
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
              const Text(
                'Device Name',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'This name is shown to nearby and paired devices.',
                style: TextStyle(fontSize: 12, color: context.appColors.muted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: name,
                autofocus: true,
                enabled: !saving,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => save(),
                decoration: const InputDecoration(labelText: 'Device name'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                AppNotificationCard(message: error!, isError: true),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: saving ? null : save,
                      child: Text(saving ? 'Saving...' : 'Save'),
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
