import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Bounded, in-memory 16 kHz mono PCM. No recording file is created.
class VoiceCapture {
  final AudioRecorder recorder = AudioRecorder();
  final level = ValueNotifier<double>(0);
  StreamSubscription<Amplitude>? _amplitude;
  StreamSubscription<Uint8List>? _stream;
  BytesBuilder _bytes = BytesBuilder(copy: false);
  Completer<void>? _closed;
  bool active = false;
  VoidCallback? onAudio;
  String? streamError;
  static const maxBytes = 16000 * 2 * 90;
  int get length => _bytes.length;
  Uint8List snapshot() => _bytes.toBytes();

  Future<void> start() async {
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required to record expenses.');
    }
    final cache = await getTemporaryDirectory();
    await for (final item in cache.list()) {
      if (item is File &&
          item.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('kharchio_voice_')) {
        await item.delete();
      }
    }
    _bytes = BytesBuilder(copy: false);
    streamError = null;
    _closed = Completer<void>();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _stream = stream.listen(
      (chunk) {
        final available = maxBytes - _bytes.length;
        if (available > 0) {
          _bytes.add(
            chunk.length <= available ? chunk : chunk.sublist(0, available),
          );
          onAudio?.call();
        }
      },
      onError: (Object error) {
        streamError = error.toString();
      },
      onDone: () {
        if (!_closed!.isCompleted) _closed!.complete();
      },
    );
    active = true;
    _amplitude = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((a) => level.value = ((a.current + 55) / 55).clamp(0.0, 1.0));
  }

  Future<void> pause() async {
    await recorder.pause();
    level.value = 0;
  }

  Future<void> resume() => recorder.resume();
  Future<Uint8List> stop() async {
    if (active) {
      await recorder.stop();
      active = false;
      await _closed?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _amplitude?.cancel();
      level.value = 0;
    }
    if (streamError != null) throw StateError(streamError!);
    return snapshot();
  }

  void clearAudio() => _bytes = BytesBuilder(copy: false);
  Future<void> dispose() async {
    onAudio = null;
    await _amplitude?.cancel();
    await _stream?.cancel();
    try {
      if (active) await recorder.cancel();
    } finally {
      await recorder.dispose();
      clearAudio();
      level.dispose();
    }
  }
}
