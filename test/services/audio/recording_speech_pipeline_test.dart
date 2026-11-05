import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/services/ai/speech_transcriber.dart';
import 'package:kharchio/services/audio/recording_speech_pipeline.dart';

class _ProviderClient implements OnlineSpeechTranscriber {
  final pending = BytesBuilder();
  final chunks = <Uint8List>[];
  bool closed = false, finished = false;
  @override
  String transcript = '';
  @override
  void Function(String)? onTranscript;
  @override
  void Function(LiveTranscriptionException)? onError;
  @override
  Future<void> start({required String language}) async {}
  @override
  void addAudio(Uint8List pcm) => pending.add(pcm);
  @override
  Future<String> pause() async {
    if (pending.isNotEmpty) {
      chunks.add(pending.takeBytes());
      transcript = 'speech ${chunks.length}';
      onTranscript?.call(transcript);
    }
    return transcript;
  }

  @override
  Future<String> finish() async {
    finished = true;
    return pause();
  }

  @override
  void close() {
    closed = true;
  }
}

Uint8List _voice(int samples, {int amplitude = 2000}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return bytes;
}

void main() {
  for (final provider in [
    'Gemini',
    'OpenAI',
    'OpenRouter',
    'future provider',
  ]) {
    test(
      '$provider receives no silence-only recording and no fabricated startup text',
      () async {
        final client = _ProviderClient();
        final pipeline = RecordingSpeechPipeline(client);
        final updates = <String>[];
        pipeline.onTranscript = updates.add;
        await pipeline.start(language: 'auto');
        client.transcript = '¿Qué?';
        client.onTranscript?.call(client.transcript);
        pipeline.addAudio(Uint8List(16000 * 2 * 5));
        final offset = Uint8List(32000);
        final data = ByteData.sublistView(offset);
        for (var i = 0; i < offset.length; i += 2) {
          data.setInt16(i, 2000, Endian.little);
        }
        pipeline.addAudio(offset);
        expect(pipeline.transcript, '');
        expect(await pipeline.finish(), '');
        expect(client.chunks, isEmpty);
        expect(client.pending.length, 0);
        expect(client.finished, isFalse);
        expect(client.closed, isTrue);
        expect(updates, isEmpty);
      },
    );
  }

  test('all clients get bounded lead-in, soft speech and preserved odd callback boundaries', () async {
    final client = _ProviderClient();
    final pipeline = RecordingSpeechPipeline(client);
    await pipeline.start(language: 'hinglish');
    final voice = _voice(1600, amplitude: 200);
    final input = Uint8List.fromList([...Uint8List(32000), ...voice]);
    pipeline.addAudio(Uint8List.sublistView(input, 0, 3001));
    pipeline.addAudio(Uint8List.sublistView(input, 3001, input.length - 1));
    pipeline.addAudio(Uint8List.sublistView(input, input.length - 1));
    expect(await pipeline.finish(), 'speech 1');
    expect(client.chunks.single, [...Uint8List(6400), ...voice]);
  });

  test('short speech flushes before Stop and long quiet gaps create no extra request', () async {
    final client = _ProviderClient();
    final pipeline = RecordingSpeechPipeline(client);
    await pipeline.start(language: 'auto');
    final first = _voice(1600);
    pipeline.addAudio(first);
    pipeline.addAudio(Uint8List(16000 * 2 * 5));
    await Future<void>.delayed(Duration.zero);
    expect(client.chunks.length, 1);
    expect(client.chunks.first, [...first, ...Uint8List(5120 * 2)]);
    expect(pipeline.transcript, 'speech 1');
    pipeline.addAudio(_voice(1600));
    expect(await pipeline.finish(), 'speech 2');
    expect(client.chunks.length, 2);
  });

  test('a live chunk boundary followed by silence never creates a silence-only next chunk', () async {
    final client = _ProviderClient();
    final pipeline = RecordingSpeechPipeline(client);
    await pipeline.start(language: 'auto');
    final voice = _voice(24000);
    pipeline.addAudio(voice);
    pipeline.addAudio(Uint8List(16000 * 2 * 5));
    await Future<void>.delayed(Duration.zero);
    expect(client.chunks.length, 1);
    expect(client.chunks.single, voice);
    expect(await pipeline.finish(), 'speech 1');
    expect(client.chunks.length, 1);
  });

  test('Stop retains the final partial frame and pause/resume keeps transcript order', () async {
    final client = _ProviderClient();
    final pipeline = RecordingSpeechPipeline(client);
    await pipeline.start(language: 'en');
    final first = _voice(200);
    pipeline.addAudio(first);
    expect(await pipeline.pause(), 'speech 1');
    final second = _voice(100);
    pipeline.addAudio(second);
    expect(await pipeline.finish(), 'speech 2');
    expect(client.chunks, [first, second]);
  });

  test(
    'incomplete PCM is rejected instead of dropping or inventing a sample',
    () async {
      final client = _ProviderClient();
      final pipeline = RecordingSpeechPipeline(client);
      await pipeline.start(language: 'auto');
      pipeline.addAudio(Uint8List.fromList([..._voice(100), 1]));
      await expectLater(
        pipeline.finish(),
        throwsA(isA<LiveTranscriptionException>()),
      );
      expect(client.chunks, isEmpty);
      expect(client.closed, isTrue);
    },
  );
}
