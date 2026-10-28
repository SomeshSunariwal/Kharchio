import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

enum ModelGroup { speechGpu, speechNpu, qwen }

class DownloadModelFile {
  final String id, path, filename, sha256;
  final Uri url;
  final int bytes;
  final ModelGroup group;

  const DownloadModelFile({
    required this.id,
    required this.path,
    required this.filename,
    required this.sha256,
    required this.url,
    required this.bytes,
    required this.group,
  });

  factory DownloadModelFile.fromJson(Map<String, dynamic> json) =>
      DownloadModelFile(
        id: json['id'] as String,
        path: json['path'] as String,
        filename: json['filename'] as String,
        sha256: json['sha256'] as String,
        url: Uri.parse(json['url'] as String),
        bytes: json['bytes'] as int,
        group: ModelGroup.values.byName(json['group'] as String),
      );
}

class ModelInventory {
  final Set<String> ready;
  final Set<String> present;
  ModelInventory(Iterable<String> ready, {Iterable<String>? present})
    : ready = Set.unmodifiable(ready),
      present = Set.unmodifiable(present ?? ready);

  static const _genericSpeechFiles = ['genericEncoder', 'genericDecoder'];
  static const _s23SpeechFiles = ['s23Encoder', 's23Decoder'];
  static const _filesByGroup = {
    ModelGroup.speechGpu: ['whisper'],
    ModelGroup.speechNpu: [..._genericSpeechFiles, ..._s23SpeechFiles],
    ModelGroup.qwen: ['qwen'],
  };

  bool hasData(ModelGroup group) => _filesByGroup[group]!.any(present.contains);
  bool groupReady(ModelGroup group) =>
      _filesByGroup[group]!.every(ready.contains);
  bool get speechReady =>
      groupReady(ModelGroup.speechGpu) ||
      _genericSpeechFiles.every(ready.contains) ||
      _s23SpeechFiles.every(ready.contains);
  bool get anyReady => speechReady || groupReady(ModelGroup.qwen);

  String? speechIssue(int mode) {
    if (mode == 2 && !_genericSpeechFiles.every(ready.contains)) {
      return 'Download the Speech Model for NPU first.';
    }
    if (mode == 3 && !_s23SpeechFiles.every(ready.contains)) {
      return 'Download the Speech Model for NPU first (SM8550).';
    }
    if ((mode == 0 || mode == 1) && !ready.contains('whisper')) {
      return 'Download the Speech Model for GPU first.';
    }
    return null;
  }

  String? get expenseIssue =>
      ready.contains('qwen') ? null : 'Download the Qwen Model for NPU first.';
}

class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
  @override
  String toString() => 'Download paused. Tap Resume to continue.';
}

/// Streams to app-private storage. A file becomes usable only after verification.
class ModelDownloadStore {
  final Directory directory;
  final List<DownloadModelFile> files;
  HttpClient? _client;
  bool _cancelled = false;

  ModelDownloadStore(this.directory, this.files);

  File target(DownloadModelFile model) =>
      File('${directory.path}/${model.path}');
  File _stamp(DownloadModelFile model) => File('${target(model).path}.sha256');

  List<DownloadModelFile> groupFiles(ModelGroup group) =>
      files.where((f) => f.group == group).toList();

  Future<bool> verified(DownloadModelFile model) async {
    final file = target(model);
    if (!await file.exists() || await file.length() != model.bytes) {
      return false;
    }
    final stamp = _stamp(model);
    // Size and mtime invalidate the cached hash if an installed file changes.
    final marker =
        '${model.sha256}:${(await file.stat()).modified.microsecondsSinceEpoch}';
    if (await stamp.exists() && await stamp.readAsString() == marker) {
      return true;
    }
    if (await _digest(file.path) != model.sha256) return false;
    await stamp.writeAsString(marker, flush: true);
    return true;
  }

  Future<ModelInventory> inspect() async {
    final ready = <String>{};
    final present = <String>{};
    for (final model in files) {
      if (await target(model).exists() ||
          await File('${target(model).path}.partial').exists()) {
        present.add(model.id);
      }
      if (await verified(model)) ready.add(model.id);
    }
    await _writeRevision(ready);
    return ModelInventory(ready, present: present);
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> download(
    ModelGroup group,
    void Function(int received, int total, String phase, int networkBytes)
    onProgress,
  ) async {
    _cancelled = false;
    final models = groupFiles(group);
    final total = models.fold(0, (sum, f) => sum + f.bytes);
    var completed = 0;
    var networkBytes = 0;
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      for (final model in models) {
        _checkCancelled();
        if (!await verified(model)) {
          await _downloadFile(model, (received, phase, transferred) {
            networkBytes += transferred;
            onProgress(completed + received, total, phase, networkBytes);
          });
        }
        completed += model.bytes;
        onProgress(completed, total, 'Downloading', networkBytes);
      }
      _checkCancelled();
      await inspect();
    } catch (error) {
      if (_cancelled) throw const ModelDownloadCancelled();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<void> _downloadFile(
    DownloadModelFile model,
    void Function(int, String, int) progress,
  ) async {
    final file = target(model);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.partial');
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > model.bytes) {
      await partial.delete();
      offset = 0;
    }
    if (offset < model.bytes) {
      final request = await _client!
          .getUrl(model.url)
          .timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Download unavailable (HTTP ${response.statusCode}). Please retry.',
          uri: model.url,
        );
      }
      if (response.statusCode == HttpStatus.partialContent) {
        final range = response.headers.value(HttpHeaders.contentRangeHeader);
        if (range != 'bytes $offset-${model.bytes - 1}/${model.bytes}') {
          throw const FormatException(
            'Unexpected download range. Please retry.',
          );
        }
      } else {
        offset = 0; // A server may ignore Range; restart rather than append.
      }
      if (response.contentLength >= 0 &&
          response.contentLength != model.bytes - offset) {
        throw const FormatException(
          'Download size does not match the model manifest.',
        );
      }
      var received = offset;
      final sink = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
        )) {
          _checkCancelled();
          received += chunk.length;
          if (received > model.bytes) {
            throw const FormatException(
              'Downloaded file is larger than expected.',
            );
          }
          // Await each write so large downloads do not accumulate in memory.
          sink.add(chunk);
          await sink.flush();
          progress(received, 'Downloading', chunk.length);
        }
      } finally {
        await sink.close();
      }
    }
    _checkCancelled();
    if (await partial.length() != model.bytes) {
      throw const FormatException('Download interrupted. Tap Retry to resume.');
    }
    progress(model.bytes, 'Verifying', 0);
    if (await _digest(partial.path) != model.sha256) {
      await partial.delete();
      throw const FormatException(
        'Model checksum failed. Please download again.',
      );
    }
    _checkCancelled();
    await partial.rename(file.path);
    final marker =
        '${model.sha256}:${(await file.stat()).modified.microsecondsSinceEpoch}';
    await _stamp(model).writeAsString(marker, flush: true);
  }

  Future<void> delete(ModelGroup group) async {
    // Each download group owns its own weights. Small audio metadata is bundled.
    for (final model in groupFiles(group)) {
      for (final file in [
        target(model),
        File('${target(model).path}.partial'),
        _stamp(model),
      ]) {
        if (await file.exists()) await file.delete();
      }
    }
    if (group == ModelGroup.speechNpu) {
      final generic = Directory('${directory.path}/whisper-qnn-generic');
      final cache = Directory('${generic.path}/cache');
      if (await cache.exists()) await cache.delete(recursive: true);
      final revision = File('${generic.path}/revision.txt');
      if (await revision.exists()) await revision.delete();
      final partialRevision = File('${revision.path}.partial');
      if (await partialRevision.exists()) await partialRevision.delete();
    }
  }

  Future<void> _writeRevision(Set<String> ready) async {
    if (!ModelInventory._genericSpeechFiles.every(ready.contains)) {
      return;
    }
    final hashes = ModelInventory._genericSpeechFiles
        .map((id) => files.firstWhere((f) => f.id == id).sha256)
        .join();
    final revision = sha256.convert(utf8.encode(hashes)).toString();
    final path = File('${directory.path}/whisper-qnn-generic/revision.txt');
    if (await path.exists() && await path.readAsString() == revision) return;
    final partial = File('${path.path}.partial');
    await partial.writeAsString(revision, flush: true);
    await partial.rename(path.path);
  }

  void _checkCancelled() {
    if (_cancelled) throw const ModelDownloadCancelled();
  }
}

Future<String> _digest(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
