import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../database/local_store.dart';
import '../../services/data_share/data_share_controller.dart';
import '../../services/data_share/expense_transfer_repository.dart';
import '../../services/data_share/local_share_platform.dart';
import '../../shared/app_notification.dart';
import '../../shared/widgets.dart';
import 'pairing_pin_dialog.dart';
import 'device_name_dialog.dart';

final localSharePlatformProvider = Provider<LocalSharePlatform>(
  (ref) => AndroidLocalSharePlatform(),
);

class DataShareScreen extends ConsumerStatefulWidget {
  const DataShareScreen({super.key});
  @override
  ConsumerState<DataShareScreen> createState() => _DataShareScreenState();
}

class _DataShareScreenState extends ConsumerState<DataShareScreen> {
  late final controller = DataShareController(
    ExpenseTransferRepository(ref.read(localStoreProvider)),
    ref.read(localSharePlatformProvider),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> editDeviceName() => showDialog<void>(
    context: context,
    builder: (_) => DeviceNameDialog(
      initialName: controller.deviceName,
      onSave: controller.setDeviceName,
    ),
  );

  Future<void> confirmTransfer() async {
    if (!controller.canTransfer) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Transfer expenses?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Your expenses will be added to the paired device without replacing or deleting their existing data.\n\n'
            'Expenses already shared will be skipped. Your data on this device will stay unchanged.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && controller.canTransfer) {
      await controller.transfer();
    }
  }

  Future<void> pair(ShareNetwork network) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PairingPinDialog(
      networkName: network.name,
      onConnect: (pin) => controller.join(network, pin),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller;
      final muted = context.appColors.muted;
      return PopScope(
        canPop: !state.transferring,
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              'Data Share',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share expenses with a nearby device',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.appColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Create a network on the sending phone, then join using its PIN. Keep this screen open on both devices.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.phone_android_rounded,
                                    color: green,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Device Name',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          state.loadingDeviceName
                                              ? 'Loading...'
                                              : state.deviceName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Set your device name before starting a session',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        state.loadingDeviceName ||
                                            state.busy ||
                                            state.role != 'none'
                                        ? null
                                        : editDeviceName,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    color: green,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: state.busy || state.connected
                                        ? null
                                        : () => state.start(host: true),
                                    icon: const Icon(
                                      Icons.wifi_tethering_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Create Network',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: state.busy || state.connected
                                        ? null
                                        : () => state.start(host: false),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 52),
                                    ),
                                    icon: const Icon(
                                      Icons.wifi_find_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Join Network',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (state.role == 'host' &&
                                state.pin.length == 6) ...[
                              const SizedBox(height: 16),
                              SurfaceCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.networkName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Pairing PIN',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: muted,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        for (var i = 0; i < 6; i++) ...[
                                          if (i > 0) const SizedBox(width: 6),
                                          Expanded(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: context.appColors.field,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: context.appColors.line,
                                                ),
                                              ),
                                              child: Text(
                                                state.pin[i],
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 23,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Available Networks',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (state.status == 'searching' ||
                                    state.status == 'creating')
                                  const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child:
                                  state.role == 'host' &&
                                      state.networkName.isNotEmpty
                                  ? ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                      leading: const Icon(
                                        Icons.wifi_tethering,
                                        color: green,
                                      ),
                                      title: Text(
                                        state.networkName,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        state.connected
                                            ? 'Paired device connected'
                                            : state.status == 'creating'
                                            ? 'Creating...'
                                            : 'Waiting for a device',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: state.connected
                                              ? green
                                              : muted,
                                        ),
                                      ),
                                      trailing: Icon(
                                        state.connected
                                            ? Icons.link
                                            : Icons.sensors,
                                        size: 20,
                                        color: state.connected ? green : muted,
                                      ),
                                    )
                                  : state.networks.isEmpty
                                  ? SizedBox(
                                      height: 150,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Text(
                                            state.status == 'searching'
                                                ? 'Searching for nearby Kharchio networks...'
                                                : 'Tap Join Network to find a nearby host.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 300,
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: state.networks.length,
                                        separatorBuilder: (_, _) => Divider(
                                          height: 1,
                                          color: context.appColors.line,
                                        ),
                                        itemBuilder: (context, index) {
                                          final network = state.networks[index];
                                          final connected =
                                              state.connectedId == network.id &&
                                              state.connected;
                                          return ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            leading: Icon(
                                              Icons.wifi,
                                              color: connected ? green : muted,
                                            ),
                                            title: Text(
                                              network.name,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            subtitle: Text(
                                              connected
                                                  ? 'Connected'
                                                  : state.connectingId ==
                                                        network.id
                                                  ? 'Connecting...'
                                                  : 'Available',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: connected
                                                    ? green
                                                    : muted,
                                              ),
                                            ),
                                            trailing: Icon(
                                              connected
                                                  ? Icons.check_circle_outline
                                                  : Icons.chevron_right,
                                              color: connected ? green : muted,
                                              size: 20,
                                            ),
                                            onTap: state.busy || state.connected
                                                ? null
                                                : () => pair(network),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                            if (state.message.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              if (state.hasError || state.completed)
                                AppNotificationCard(
                                  message: state.message,
                                  isError: state.hasError,
                                )
                              else
                                Text(
                                  state.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: state.connected ? green : muted,
                                  ),
                                ),
                            ],
                            const SizedBox(height: 18),
                            if (state.role != 'none' && !state.transferring)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: state.busy ? null : state.stop,
                                  child: Text(
                                    state.role == 'host'
                                        ? 'End Session'
                                        : 'Leave Network',
                                  ),
                                ),
                              ),
                            Text(
                              'Share your expenses with the paired device. Their existing data stays safe, and expenses already shared are skipped.',
                              style: TextStyle(
                                fontSize: 11,
                                color: muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      decoration: BoxDecoration(
                        color: context.appColors.surface,
                        border: Border(
                          top: BorderSide(color: context.appColors.line),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.transferring ||
                              state.completed ||
                              state.processed > 0) ...[
                            SurfaceCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          state.sending
                                              ? 'Sending expenses'
                                              : 'Receiving expenses',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${(state.progress * 100).floor()}%',
                                        style: const TextStyle(
                                          color: green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: state.progress,
                                      color: green,
                                      minHeight: 6,
                                      backgroundColor: green.withValues(
                                        alpha: .12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    '${state.processed} / ${state.total} expenses · ${state.added} added · ${state.skipped} skipped',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: state.canTransfer
                                  ? confirmTransfer
                                  : null,
                              icon: const Icon(Icons.send_outlined, size: 19),
                              label: Text(
                                state.transferring
                                    ? 'Transfer in progress...'
                                    : 'Transfer Data to Paired Device',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
