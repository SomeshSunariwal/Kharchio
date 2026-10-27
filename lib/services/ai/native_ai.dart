import 'dart:ffi';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

typedef _TranscribeC = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Float>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Int32>,
);
typedef _Transcribe = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Float>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Int32>,
);
typedef _ExtractC = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Int32,
  Pointer<Int32>,
);
typedef _Extract = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
  Pointer<Int32>,
);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);
typedef _PrepareC = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Int32>);
typedef _Prepare = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Int32>);
typedef _ReleaseC = Void Function();
typedef _Release = void Function();
typedef _SetProcessingC = Void Function(Int32);
typedef _SetProcessing = void Function(int);
typedef _BackendC = Pointer<Utf8> Function();
typedef _Backend = Pointer<Utf8> Function();

DynamicLibrary _library() => Platform.isAndroid
    ? DynamicLibrary.open('libkharchio_ai.so')
    : DynamicLibrary.process();

/// Only the cancellation flag crosses isolates. Its owner frees it after work ends.
class NativeAiJob {
  final Pointer<Int32> _cancel = calloc<Int32>();
  bool _disposed = false;
  void cancel() {
    if (!_disposed) _cancel.value = 1;
  }

  void dispose() {
    if (!_disposed) {
      _disposed = true;
      calloc.free(_cancel);
    }
  }

  Future<String> transcribe(String model, Uint8List audio, String language) {
    final address = _cancel.address;
    final data = TransferableTypedData.fromList([audio]);
    return _runWithDeadline(
      () => Isolate.run(() => _transcribe(model, data, language, address)),
      const Duration(seconds: 120),
      'Transcription took too long. Please record a shorter expense.',
    );
  }

  Future<String> extract(String model, String prompt, String grammar) {
    final address = _cancel.address;
    return _runWithDeadline(
      () => Isolate.run(() => _extract(model, prompt, grammar, address)),
      const Duration(seconds: 120),
      'Expense extraction took too long. Please try a shorter recording.',
    );
  }

  Future<void> prepareWhisper(String model) => _prepareModel(model, true);
  Future<void> prepareQwen(String model) => _prepareModel(model, false);

  Future<void> _prepareModel(String model, bool whisper) async {
    final address = _cancel.address;
    await _runWithDeadline(
      () => Isolate.run(() => _prepare(model, whisper, address)),
      const Duration(seconds: 120),
      'Loading the offline model took too long. Please try again.',
    );
  }

  static Future<void> releaseModels() => Isolate.run(() {
    final lib = _library();
    lib.lookupFunction<_ReleaseC, _Release>('kharchio_release_models')();
  });

  static Future<void> setProcessing({required int mode}) => Isolate.run(() {
    _library().lookupFunction<_SetProcessingC, _SetProcessing>(
      'kharchio_set_processing',
    )(mode);
  });

  static Future<String> lastBackend() => Isolate.run(() {
    final lib = _library();
    return _readResult(
      lib,
      lib.lookupFunction<_BackendC, _Backend>('kharchio_last_backend')(),
    );
  });

  Future<String> _runWithDeadline(
    Future<String> Function() run,
    Duration limit,
    String message,
  ) async {
    var timedOut = false;
    final deadline = Timer(limit, () {
      timedOut = true;
      cancel();
    });
    try {
      // Await native cancellation before the caller frees its shared flag.
      final result = await run();
      if (timedOut) throw TimeoutException(message);
      return result;
    } catch (_) {
      if (timedOut) throw TimeoutException(message);
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  static void checkBindings() {
    final lib = _library();
    lib.lookup<NativeFunction<_TranscribeC>>('kharchio_transcribe');
    lib.lookup<NativeFunction<_ExtractC>>('kharchio_extract');
    lib.lookup<NativeFunction<_PrepareC>>('kharchio_prepare_whisper');
    lib.lookup<NativeFunction<_PrepareC>>('kharchio_prepare_qwen');
    lib.lookup<NativeFunction<_ReleaseC>>('kharchio_release_models');
    lib.lookup<NativeFunction<_SetProcessingC>>('kharchio_set_processing');
    lib.lookup<NativeFunction<_BackendC>>('kharchio_last_backend');
  }
}

String _prepare(String model, bool whisper, int cancel) {
  final lib = _library();
  final path = model.toNativeUtf8();
  try {
    final run = lib.lookupFunction<_PrepareC, _Prepare>(
      whisper ? 'kharchio_prepare_whisper' : 'kharchio_prepare_qwen',
    );
    return _readResult(lib, run(path, Pointer<Int32>.fromAddress(cancel)));
  } finally {
    calloc.free(path);
  }
}

String _readResult(DynamicLibrary lib, Pointer<Utf8> value) {
  if (value == nullptr) throw StateError('Native inference ran out of memory.');
  try {
    final text = value.toDartString().trim();
    if (text.startsWith('ERROR:')) throw StateError(text.substring(6));
    return text;
  } finally {
    lib.lookupFunction<_FreeC, _Free>('kharchio_free')(value);
  }
}

String _transcribe(
  String model,
  TransferableTypedData audio,
  String language,
  int cancel,
) {
  final lib = _library();
  final bytes = audio.materialize().asUint8List();
  if (bytes.length < 3200 ||
      bytes.length > 16000 * 2 * 90 ||
      bytes.length.isOdd) {
    throw const FormatException('Record a short sentence, up to 90 seconds.');
  }
  final data = ByteData.sublistView(bytes);
  final allSamples = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < allSamples.length; i++) {
    allSamples[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  // Remove empty microphone lead/tail, preventing silence hallucinations and
  // avoiding repeated decoding of long silent tails during live updates.
  const frameSize = 320;
  final energy = <double>[];
  for (var start = 0; start < allSamples.length; start += frameSize) {
    final end = math.min(start + frameSize, allSamples.length);
    var squared = 0.0;
    for (var i = start; i < end; i++) {
      squared += allSamples[i] * allSamples[i];
    }
    energy.add(math.sqrt(squared / (end - start)));
  }
  final peak = energy.reduce(math.max);
  if (peak < .0005) {
    throw const FormatException('No speech detected. Please record again.');
  }
  final threshold = math.max(.0005, peak * .06);
  final first = energy.indexWhere((rms) => rms >= threshold);
  final last = energy.lastIndexWhere((rms) => rms >= threshold);
  final samples = Float32List.sublistView(
    allSamples,
    math.max(0, first * frameSize - 4000),
    math.min(allSamples.length, (last + 1) * frameSize + 4000),
  );
  final pcm = calloc<Float>(samples.length);
  final modelPath = model.toNativeUtf8();
  final lang = language.toNativeUtf8();
  try {
    pcm.asTypedList(samples.length).setAll(0, samples);
    final run = lib.lookupFunction<_TranscribeC, _Transcribe>(
      'kharchio_transcribe',
    );
    return _readResult(
      lib,
      run(
        modelPath,
        pcm,
        samples.length,
        lang,
        Platform.numberOfProcessors.clamp(1, 4),
        Pointer<Int32>.fromAddress(cancel),
      ),
    );
  } finally {
    calloc.free(pcm);
    calloc.free(modelPath);
    calloc.free(lang);
  }
}

String _extract(String model, String prompt, String grammar, int cancel) {
  final lib = _library();
  final modelPath = model.toNativeUtf8();
  final input = prompt.toNativeUtf8();
  final constraint = grammar.toNativeUtf8();
  try {
    final run = lib.lookupFunction<_ExtractC, _Extract>('kharchio_extract');
    return _readResult(
      lib,
      run(
        modelPath,
        input,
        constraint,
        Platform.numberOfProcessors.clamp(1, 4),
        Pointer<Int32>.fromAddress(cancel),
      ),
    );
  } finally {
    calloc.free(modelPath);
    calloc.free(input);
    calloc.free(constraint);
  }
}
