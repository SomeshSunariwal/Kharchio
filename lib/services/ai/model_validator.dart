import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'expense_extractor.dart';
import 'model_manager.dart';
import 'native_ai.dart';

enum OfflineModelKind { whisper, qwen }

class ModelCheckResult {
  final String model;
  final String backend;
  final String summary;
  final String output;
  final Duration elapsed;
  final bool usedFallback;

  const ModelCheckResult({
    required this.model,
    required this.backend,
    required this.summary,
    required this.output,
    required this.elapsed,
    required this.usedFallback,
  });
}

/// Runs real inference without recording audio or writing expense data.
class ModelValidator {
  Future<ModelCheckResult> check(
    OfflineModelKind kind,
    OfflineModels models,
    void Function(String) onProgress, {
    required int processingMode,
    required String speechLanguage,
  }) async {
    final job = NativeAiJob();
    final elapsed = Stopwatch()..start();
    try {
      await NativeAiJob.setProcessing(mode: processingMode);
      if (kind == OfflineModelKind.whisper) {
        onProgress('Loading Whisper…');
        await job.prepareWhisper(models.whisper);
        onProgress('Transcribing a bundled speech sample…');
        final suffix = speechLanguage == 'en' ? '' : '_hinglish';
        final wav = await rootBundle.load(
          'assets/diagnostics/model_check$suffix.wav',
        );
        final transcript = await job.transcribe(
          models.whisper,
          _pcm(wav),
          speechLanguage,
        );
        final normalized = transcript.toLowerCase();
        if (!normalized.contains('milk') ||
            !RegExp(r'movie|film').hasMatch(normalized) ||
            !RegExp(r'\b100\b|hundred').hasMatch(normalized) ||
            !RegExp(r'\b150\b|fifty').hasMatch(normalized)) {
          throw StateError(
            'Whisper ran, but the sample transcript did not match the expected purchases. '
            'Recognized: $transcript',
          );
        }
        final backend = await NativeAiJob.lastBackend();
        return ModelCheckResult(
          model: 'Whisper Small',
          backend: backend,
          summary: 'The sample speech was transcribed successfully.',
          output: transcript,
          elapsed: elapsed.elapsed,
          usedFallback: _usedFallback(backend, processingMode),
        );
      }
      onProgress('Loading Qwen…');
      await job.prepareQwen(models.qwen);
      onProgress('Generating and validating expense JSON…');
      final expenses = await ExpenseExtractor().extract(
        job: job,
        model: models.qwen,
        text:
            'I bought milk for 100 rupees and watched a movie for 150 rupees.',
        categories: const ['Groceries', 'Entertainment'],
        currency: 'INR',
      );
      if (expenses.length != 2 ||
          !expenses.any((e) => e.amount == 100 && e.category == 'Groceries') ||
          !expenses.any(
            (e) => e.amount == 150 && e.category == 'Entertainment',
          )) {
        throw StateError(
          'Qwen ran, but its expenses did not match the sample.',
        );
      }
      final backend = await NativeAiJob.lastBackend();
      return ModelCheckResult(
        model: 'Qwen3 · 0.6B',
        backend: backend,
        summary: 'Both sample expenses were extracted and validated.',
        output: 'Milk · ₹100.00 · Groceries\nMovie · ₹150.00 · Entertainment',
        elapsed: elapsed.elapsed,
        usedFallback: _usedFallback(backend, processingMode),
      );
    } finally {
      onProgress('Releasing model memory…');
      try {
        await NativeAiJob.releaseModels();
      } finally {
        job.dispose();
      }
    }
  }

  bool _usedFallback(String backend, int mode) =>
      (mode == 2 || mode == 3) &&
      !backend.startsWith('HTP') &&
      !backend.startsWith('QNN/QAIRT');

  Uint8List _pcm(ByteData wav) {
    String tag(int offset) => String.fromCharCodes(
      wav.buffer.asUint8List(wav.offsetInBytes + offset, 4),
    );
    if (wav.lengthInBytes < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Invalid model check audio.');
    }
    var validFormat = false;
    for (var offset = 12; offset + 8 <= wav.lengthInBytes;) {
      final size = wav.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + size > wav.lengthInBytes) break;
      if (tag(offset) == 'fmt ' && size >= 16) {
        validFormat =
            wav.getUint16(start, Endian.little) == 1 &&
            wav.getUint16(start + 2, Endian.little) == 1 &&
            wav.getUint32(start + 4, Endian.little) == 16000 &&
            wav.getUint16(start + 14, Endian.little) == 16;
      }
      if (tag(offset) == 'data' && validFormat) {
        return Uint8List.sublistView(wav, start, start + size);
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('Model check audio must be mono 16 kHz PCM.');
  }
}
