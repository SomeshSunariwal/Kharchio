import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'expense_transfer_repository.dart';
import 'local_share_platform.dart';

class ShareNetwork {
  final String id, name;
  const ShareNetwork(this.id, this.name);
}

class DataShareController extends ChangeNotifier {
  final ExpenseTransferRepository repository;
  final LocalSharePlatform platform;
  late final StreamSubscription<Map<String, dynamic>> subscription;
  Future<void> _incoming = Future.value();
  bool _alive = true;
  int _session = 0;
  String role = 'none',
      status = 'idle',
      pin = '',
      networkName = '',
      message = '';
  String deviceName = '';
  bool loadingDeviceName = true;
  String? connectingId, connectedId;
  List<ShareNetwork> networks = [];
  bool sending = false;
  bool starting = false,
      transferring = false,
      completed = false,
      hasError = false;
  int total = 0, processed = 0, added = 0, skipped = 0;

  DataShareController(this.repository, this.platform) {
    unawaited(loadDeviceName());
    subscription = platform.events.listen(
      (event) {
        final session = _session;
        _incoming = _incoming
            .then((_) async {
              if (_alive && session == _session) await _event(event);
            })
            .catchError((Object error) {
              if (_alive) _error(error);
            });
      },
      onError: (Object error) {
        if (_alive) _error(error);
      },
    );
  }
  Future<void> loadDeviceName() async {
    try {
      deviceName = await platform.invoke('getDeviceName') as String? ?? '';
    } catch (error) {
      if (_alive) _error(error);
    } finally {
      loadingDeviceName = false;
      _notify();
    }
  }

  Future<void> setDeviceName(String name) async {
    final value = name.trim();
    if (value.isEmpty ||
        value.length > 40 ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value)) {
      throw const FormatException(
        'Enter a device name between 1 and 40 characters.',
      );
    }
    if (role != 'none' || busy) {
      throw const FormatException(
        'End the current session before changing the device name.',
      );
    }
    deviceName =
        await platform.invoke('setDeviceName', {'name': value}) as String;
    _notify();
  }

  bool get connected => status == 'connected';
  bool get busy =>
      starting ||
      status == 'creating' ||
      status == 'connecting' ||
      transferring;
  bool get canTransfer => connected && !busy;
  double get progress => completed
      ? 1
      : total == 0
      ? 0
      : (processed / total).clamp(0.0, 1.0);
  void _notify() {
    if (_alive) notifyListeners();
  }

  static String errorMessage(Object error) => error is PlatformException
      ? error.message ?? 'Local connection failed. Please retry.'
      : error is MissingPluginException
      ? 'Local sharing is available on Android devices.'
      : error is FormatException
      ? error.message
      : 'Could not complete the transfer. Reconnect and retry; existing expenses will be skipped.';
  void _error(Object error) {
    hasError = true;
    message = errorMessage(error);
    starting = false;
    transferring = false;
    completed = false;
    _notify();
  }

  Future<void> start({required bool host}) async {
    if (busy) return;
    _session++;
    starting = true;
    hasError = false;
    completed = false;
    processed = 0;
    total = 0;
    added = 0;
    skipped = 0;
    connectedId = null;
    connectingId = null;
    _notify();
    try {
      await platform.invoke(host ? 'host' : 'discover');
    } catch (error) {
      _error(error);
    } finally {
      starting = false;
      _notify();
    }
  }

  Future<void> join(ShareNetwork network, String code) async {
    if (role != 'joiner' || connected || busy) {
      throw StateError('Search for a network first.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('Enter all six digits.');
    }
    connectingId = network.id;
    hasError = false;
    _notify();
    try {
      await platform.invoke('join', {'id': network.id, 'pin': code});
      connectedId = network.id;
      status = 'connected';
      message = 'Connected to ${network.name}';
    } catch (error) {
      connectedId = null;
      status = 'searching';
      rethrow;
    } finally {
      connectingId = null;
      _notify();
    }
  }

  Future<void> transfer() async {
    if (!canTransfer) {
      throw StateError('Connect to a paired device before transferring data.');
    }
    transferring = true;
    sending = true;
    completed = false;
    hasError = false;
    processed = 0;
    total = 0;
    added = 0;
    skipped = 0;
    message = 'Preparing expenses...';
    _notify();
    try {
      final rows = await repository.exportExpenses();
      if (!_alive || !connected) throw StateError('Disconnected');
      total = rows.length;
      message = 'Transferring expenses...';
      _notify();
      await platform.invoke('beginTransfer', {'total': total});
      for (final batch in _batches(rows)) {
        if (!_alive || !connected) throw StateError('Disconnected');
        final response = Map<String, dynamic>.from(
          await platform.invoke('sendBatch', {
            'payload': jsonEncode({'version': 1, 'expenses': batch}),
          }) as Map,
        );
        final imported = response['added'], ignored = response['skipped'];
        if (imported is! int ||
            ignored is! int ||
            imported < 0 ||
            ignored < 0 ||
            imported + ignored != batch.length) {
          throw const FormatException(
            'The receiver did not confirm this batch. Please retry.',
          );
        }
        added += imported;
        skipped += ignored;
        processed += batch.length;
        _notify();
      }
      await platform.invoke('finishTransfer', {
        'added': added,
        'skipped': skipped,
      });
      transferring = false;
      completed = true;
      message = 'Transfer complete. $added added, $skipped already present.';
      _notify();
    } catch (error) {
      try {
        if (connected) await platform.invoke('abortTransfer');
      } catch (_) {
        /* Connection already closed. */
      }
      if (_alive) _error(error);
    }
  }

  Iterable<List<Map<String, Object>>> _batches(
    List<Map<String, Object>> rows,
  ) sync* {
    var batch = <Map<String, Object>>[];
    var bytes = 0;
    for (final row in rows) {
      final size = utf8.encode(jsonEncode(row)).length;
      if (size > 1024 * 1024) {
        throw const FormatException('An expense is too large to transfer.');
      }
      if (batch.isNotEmpty &&
          (batch.length >= 50 || bytes + size > 256 * 1024)) {
        yield batch;
        batch = [];
        bytes = 0;
      }
      batch.add(row);
      bytes += size;
    }
    if (batch.isNotEmpty) yield batch;
  }

  Future<void> _event(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'state':
        role = event['role'] as String? ?? role;
        status = event['status'] as String? ?? status;
        pin = event['pin'] as String? ?? '';
        networkName = event['name'] as String? ?? '';
        if (!transferring && event['message'] is String) {
          message = event['message'] as String;
        }
        if (!connected && !const ['creating', 'connecting'].contains(status)) {
          transferring = false;
          connectedId = null;
        }
        if (status == 'error') {
          hasError = true;
        }
        _notify();
      case 'networks':
        networks = [
          for (final item in event['items'] as List? ?? [])
            if (item is Map && item['id'] is String && item['name'] is String)
              ShareNetwork(item['id'] as String, item['name'] as String),
        ];
        _notify();
      case 'begin':
        if (!connected || transferring) return;
        final count = event['total'];
        if (count is! int || count < 0) {
          throw const FormatException('Invalid transfer count.');
        }
        sending = false;
        total = count;
        processed = 0;
        added = 0;
        skipped = 0;
        transferring = true;
        completed = false;
        hasError = false;
        message = 'Receiving expenses...';
        _notify();
      case 'batch':
        final id = event['id'];
        try {
          if (sending ||
              !connected ||
              !transferring ||
              id is! String ||
              event['payload'] is! String) {
            throw const FormatException('No active incoming transfer.');
          }
          final packet = jsonDecode(event['payload'] as String);
          if (packet is! Map ||
              packet['expenses'] is! List ||
              processed + (packet['expenses'] as List).length > total) {
            throw const FormatException('Unexpected transfer size.');
          }
          final result = await repository.importBatch(
            event['payload'] as String,
          );
          added += result.added;
          skipped += result.skipped;
          processed += result.added + result.skipped;
          if (processed > total) {
            throw const FormatException('Unexpected transfer size.');
          }
          await platform.invoke('acknowledge', {
            'id': id,
            'added': result.added,
            'skipped': result.skipped,
          });
          _notify();
        } catch (error) {
          try {
            await platform.invoke('acknowledge', {
              'id': id,
              'added': 0,
              'skipped': 0,
              'error': errorMessage(error),
            });
          } catch (_) {
            /* Host will time out and can retry safely. */
          }
          _error(error);
        }
      case 'complete':
        if (sending || processed != total || !transferring) return;
        transferring = false;
        completed = true;
        message =
            'Received successfully. $added added, $skipped already present.';
        _notify();
      case 'abort':
        transferring = false;
        hasError = true;
        message = 'Transfer interrupted. Already received expenses are kept. The sender can retry.';
        _notify();
    }
  }

  Future<void> stop() async {
    if (transferring) return;
    _session++;
    await platform.invoke('stop');
    role = 'none';
    status = 'idle';
    pin = '';
    networkName = '';
    message = '';
    connectingId = null;
    connectedId = null;
    networks = [];
    completed = false;
    hasError = false;
    total = 0;
    processed = 0;
    added = 0;
    skipped = 0;
    _notify();
  }

  @override
  void dispose() {
    _alive = false;
    _session++;
    unawaited(subscription.cancel());
    unawaited(platform.invoke('stop').catchError((Object _) => null));
    super.dispose();
  }
}
