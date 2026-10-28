import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model_download_manager.dart';
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
    final directory = await ref.watch(modelDirectoryProvider.future);
    return OfflineModels(
      '${directory.path}/${names[0]}',
      '${directory.path}/${names[1]}',
    );
  }

  /// Shared guard for checks and recording, independent of disabled UI controls.
  Future<OfflineModels> requireAvailable({
    int? speechMode,
    bool expense = false,
  }) async {
    final downloads = await ref.read(modelDownloadsProvider.future);
    final issue = speechMode != null
        ? downloads.inventory.speechIssue(speechMode)
        : null;
    final expenseIssue = expense ? downloads.inventory.expenseIssue : null;
    if (issue != null || expenseIssue != null) {
      throw StateError(
        '${issue ?? expenseIssue} Open Profile & Settings → Offline AI.',
      );
    }
    if (downloads.active != null) {
      throw StateError('Wait for the model download or deletion to finish.');
    }
    return future;
  }
}
