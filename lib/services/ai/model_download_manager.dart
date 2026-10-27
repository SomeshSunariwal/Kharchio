import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import 'model_download_store.dart';

final modelDirectoryProvider = FutureProvider<Directory>((ref) async {
  late final Directory directory;
  if (Platform.isAndroid) {
    final path = await const MethodChannel('com.expense.kharchio/models')
        .invokeMethod<String>('modelDirectory');
    if (path == null) throw StateError('Cannot open model storage.');
    directory = Directory(path);
  } else {
    directory = Directory(
      '${(await getApplicationSupportDirectory()).path}/offline_models',
    );
  }
  await directory.create(recursive: true);
  final metadata = await rootBundle.load(
    'models/whisper/whisper-small-metadata.dat',
  );
  final bytes = metadata.buffer.asUint8List(
    metadata.offsetInBytes,
    metadata.lengthInBytes,
  );
  final file = File('${directory.path}/whisper-small-metadata.dat');
  if (!await file.exists() ||
      await file.length() != bytes.length ||
      sha256.convert(await file.readAsBytes()).toString() !=
          sha256.convert(bytes).toString()) {
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  }
  return directory;
});

class ModelDownloadState {
  final ModelInventory inventory;
  final ModelGroup? active, errorGroup;
  final int received, total;
  final String phase;
  final String? error;
  final bool paused;
  final double bytesPerSecond;

  const ModelDownloadState({
    required this.inventory,
    this.active,
    this.errorGroup,
    this.received = 0,
    this.total = 0,
    this.phase = '',
    this.error,
    this.paused = false,
    this.bytesPerSecond = 0,
  });
}

final modelDownloadsProvider =
    AsyncNotifierProvider<ModelDownloads, ModelDownloadState>(
      ModelDownloads.new,
    );

class ModelDownloads extends AsyncNotifier<ModelDownloadState> {
  late ModelDownloadStore _store;

  @override
  Future<ModelDownloadState> build() async {
    final json = jsonDecode(
      await rootBundle.loadString('models/manifest.json'),
    ) as Map<String, dynamic>;
    final files = (json['files'] as List)
        .map((e) => DownloadModelFile.fromJson(e as Map<String, dynamic>))
        .toList();
    _store = ModelDownloadStore(
      await ref.watch(modelDirectoryProvider.future),
      files,
    );
    ref.onDispose(_store.cancel);
    return ModelDownloadState(inventory: await _store.inspect());
  }

  Future<void> download(ModelGroup group) async {
    final current = state.value;
    if (current == null || current.active != null) return;
    state = AsyncData(
      ModelDownloadState(
        inventory: current.inventory,
        active: group,
        phase: 'Preparing',
      ),
    );
    try {
      var previousPercent = -1;
      var previousPhase = '';
      final clock = Stopwatch()..start();
      var sampleTime = 0;
      var sampleBytes = 0;
      var speed = 0.0;
      await _store.download(group, (received, total, phase, networkBytes) {
        final elapsed = clock.elapsedMilliseconds;
        final sampleDue = elapsed - sampleTime >= 500;
        if (phase != previousPhase) {
          sampleTime = elapsed;
          sampleBytes = networkBytes;
          speed = 0;
        } else if (sampleDue && phase == 'Downloading') {
          speed = (networkBytes - sampleBytes) * 1000 / (elapsed - sampleTime);
          sampleTime = elapsed;
          sampleBytes = networkBytes;
        }
        final percent = total == 0 ? 0 : received * 100 ~/ total;
        if (!ref.mounted ||
            (percent == previousPercent &&
                phase == previousPhase &&
                !sampleDue)) {
          return;
        }
        previousPercent = percent;
        previousPhase = phase;
        state = AsyncData(
          ModelDownloadState(
            inventory: current.inventory,
            active: group,
            received: received,
            total: total,
            phase: phase,
            bytesPerSecond: speed,
          ),
        );
      });
      final inventory = await _store.inspect();
      if (ref.mounted) {
        state = AsyncData(ModelDownloadState(inventory: inventory));
      }
    } catch (error) {
      if (!ref.mounted) return;
      final inventory = await _inventoryAfterFailure();
      if (!ref.mounted) return;
      state = AsyncData(
        ModelDownloadState(
          inventory: inventory,
          errorGroup: group,
          paused: error is ModelDownloadCancelled,
          error: _message(error),
        ),
      );
    }
  }

  void pause() => _store.cancel();

  Future<void> delete(ModelGroup group) async {
    final current = state.value;
    if (current == null || current.active != null) return;
    state = AsyncData(
      ModelDownloadState(
        inventory: current.inventory,
        active: group,
        phase: 'Deleting',
      ),
    );
    try {
      await _store.delete(group);
      final inventory = await _store.inspect();
      if (ref.mounted) {
        state = AsyncData(ModelDownloadState(inventory: inventory));
      }
    } catch (error) {
      final inventory = await _inventoryAfterFailure();
      if (ref.mounted) {
        state = AsyncData(
          ModelDownloadState(
            inventory: inventory,
            errorGroup: group,
            error: _message(error),
          ),
        );
      }
    }
  }

  String _message(Object error) {
    if (error is SocketException) {
      return 'Cannot reach the download server. Check your connection and retry.';
    }
    if (error is FileSystemException) {
      return 'Could not save model files. Check free storage and retry.';
    }
    if (error is FormatException) return error.message;
    return error.toString();
  }

  Future<ModelInventory> _inventoryAfterFailure() async {
    try {
      return await _store.inspect();
    } catch (_) {
      return ModelInventory(const []);
    }
  }
}
