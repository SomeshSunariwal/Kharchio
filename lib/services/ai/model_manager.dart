import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'native_ai.dart';

class OfflineModels {
  final String whisper, qwen;
  const OfflineModels(this.whisper, this.qwen);
}

final offlineModelsProvider =
    AsyncNotifierProvider<ModelManager, OfflineModels>(ModelManager.new);

class ModelManager extends AsyncNotifier<OfflineModels> {
  static const names = ['ggml-small-q5_1.bin', 'Qwen3-0.6B-Q8_0.gguf'];
  @override
  Future<OfflineModels> build() async {
    NativeAiJob.checkBindings();
    if (Platform.isAndroid) {
      final paths = await const MethodChannel('com.expense.kharchio/models')
          .invokeMapMethod<String, String>('installBundled');
      if (paths == null || paths['whisper'] == null || paths['qwen'] == null) {
        throw StateError('Bundled offline models could not be installed.');
      }
      await _validate(paths['whisper']!, gguf: false);
      await _validate(paths['qwen']!, gguf: true);
      return OfflineModels(paths['whisper']!, paths['qwen']!);
    }
    final folder = Directory(
      '${(await getApplicationSupportDirectory()).path}/offline_models',
    );
    await folder.create(recursive: true);
    for (final name in ['ggml-base.bin', 'ggml-base.bin.partial']) {
      final obsolete = File('${folder.path}/$name');
      if (await obsolete.exists()) await obsolete.delete();
    }
    for (final name in names) {
      final file = File('${folder.path}/$name');
      if (!await file.exists()) {
        final bytes = await rootBundle.load('assets/models/$name');
        final temporary = File('${file.path}.partial');
        await temporary.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        await temporary.rename(file.path);
      }
    }
    final models = OfflineModels(
      '${folder.path}/${names[0]}',
      '${folder.path}/${names[1]}',
    );
    await _validate(models.whisper, gguf: false);
    await _validate(models.qwen, gguf: true);
    return models;
  }

  Future<void> _validate(String path, {required bool gguf}) async {
    final file = File(path);
    if (await file.length() < 10000000) {
      throw StateError('Model file is incomplete.');
    }
    final handle = await file.open();
    try {
      final header = await handle.read(4);
      final expected = gguf ? [71, 71, 85, 70] : [108, 109, 103, 103];
      if (header.length != 4 ||
          !List.generate(4, (i) => header[i] == expected[i]).every((v) => v)) {
        throw StateError('Invalid offline model format.');
      }
    } finally {
      await handle.close();
    }
  }
}
