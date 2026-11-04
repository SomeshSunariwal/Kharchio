import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/services/ai/live_transcriber.dart';

class _Socket extends Stream<dynamic> implements WebSocket {
  final events = StreamController<dynamic>();
  final audio = BytesBuilder();
  int ends = 0, samples = 0;
  bool closed = false;
  bool reply = true;
  bool roundedOffsets = false, transcribe = true;
  void emit(Map<String, Object?> event) => events.add(jsonEncode(event));
  @override
  Duration? pingInterval;
  @override
  int? get closeCode => null;
  @override
  void add(dynamic data) {
    final message = jsonDecode(data as String) as Map;
    if (message.containsKey('setup')) emit({'setupComplete': {}});
    final input = message['realtimeInput'];
    if (input is! Map) return;
    if (input.containsKey('activityStart')) {
      emit({
        'voiceActivity': {'type': 'ACTIVITY_START'},
      });
    }
    if (input['audio'] is Map) {
      final bytes = base64Decode(input['audio']['data'] as String);
      audio.add(bytes);
      samples += bytes.length ~/ 2;
    }
    if (input.containsKey('activityEnd')) {
      ends++;
      if (reply) completeSegment();
    }
  }

  void completeSegment() {
    // Reproduce Gemini's observed wire behavior: no interim updates, no
    // finished flag, and no assistant turnComplete for transcription-only use.
    if (transcribe) {
      emit({
        'serverContent': {
          'inputTranscription': {'text': ends == 1 ? 'Milk 100.' : 'Bus 40.'},
        },
      });
    }
    emit({
      'voiceActivity': {
        'type': 'ACTIVITY_END',
        'audioOffset':
            '${roundedOffsets ? (samples / 16).floor() / 1000 : samples / 16000}s',
      },
    });
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List _speech(int samples) {
  final result = Uint8List(samples * 2);
  final data = ByteData.sublistView(result);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? 2000 : -2000, Endian.little);
  }
  return result;
}

class _OpenAiSocket extends _Socket {
  @override
  void add(dynamic data) {
    final message = jsonDecode(data as String) as Map;
    if (message['type'] == 'session.update') emit({'type': 'session.updated'});
    if (message['type'] == 'input_audio_buffer.append') {
      audio.add(base64Decode(message['audio'] as String));
    }
    if (message['type'] == 'input_audio_buffer.commit') {
      ends++;
      emit({
        'type': 'input_audio_buffer.committed',
        'item_id': 'item$ends',
        if (ends > 1) 'previous_item_id': 'item${ends - 1}',
      });
      if (reply) completeSegment();
    }
  }

  @override
  void completeSegment() => emit({
    'type': 'conversation.item.input_audio_transcription.completed',
    'item_id': 'item$ends',
    'transcript': ends == 1 ? 'Milk 100.' : 'Bus 40.',
  });
}

void main() {
  test('OpenAI pause also tolerates delayed completions and preserves resumed chunks', () async {
    final socket = _OpenAiSocket()..reply = false;
    final failures = <LiveTranscriptionException>[];
    final live = OnlineLiveTranscriber(
      OnlineAiProvider.openai,
      'fake',
      'gpt-live-transcribe',
      connector: (_, _) async => socket,
      pauseTimeout: const Duration(milliseconds: 20),
    )..onError = failures.add;
    await live.start(language: 'en');
    live.addAudio(_speech(1600));
    expect(await live.pause(), '');
    expect(socket.closed, isFalse);
    live.addAudio(_speech(1600));
    expect(socket.ends, 1);
    socket.completeSegment();
    socket.reply = true;
    expect(await live.finish(), 'Milk 100. Bus 40.');
    expect(socket.ends, 2);
    expect(failures, isEmpty);
  });

  test('Stop keeps a strict deadline instead of accepting an incomplete paused transcript', () async {
    final socket = _Socket()..reply = false;
    final live = OnlineLiveTranscriber(
      OnlineAiProvider.gemini,
      'fake',
      'gemini-live',
      connector: (_, _) async => socket,
      pauseTimeout: const Duration(milliseconds: 10),
      finishTimeout: const Duration(milliseconds: 60),
    );
    await live.start(language: 'en');
    live.addAudio(_speech(1600));
    expect(await live.pause(), '');
    await expectLater(
      live.finish(),
      throwsA(isA<LiveTranscriptionException>()),
    );
    expect(socket.closed, isTrue);
  });
  test(
    'late pause responses keep the session open and retain resumed audio',
    () async {
      final socket = _Socket()..reply = false;
      final failures = <LiveTranscriptionException>[];
      final live = OnlineLiveTranscriber(
        OnlineAiProvider.gemini,
        'fake',
        'gemini-live',
        connector: (_, _) async => socket,
        pauseTimeout: const Duration(milliseconds: 20),
        finishTimeout: const Duration(seconds: 2),
      )..onError = failures.add;
      await live.start(language: 'en');
      final first = _speech(1600), second = _speech(1600);
      live.addAudio(first);
      expect(await live.pause(), '');
      expect(await live.pause(), '');
      expect(socket.ends, 1);
      expect(socket.closed, isFalse);
      expect(failures, isEmpty);
      live.addAudio(second);
      expect(socket.audio.length, first.length);
      socket.completeSegment();
      socket.reply = true;
      expect(await live.finish(), 'Milk 100. Bus 40.');
      expect(socket.audio.toBytes(), [...first, ...second]);
      expect(failures, isEmpty);
    },
  );

  test(
    'millisecond-rounded Gemini offsets finalize a partial microphone frame',
    () async {
      final socket = _Socket()..roundedOffsets = true;
      final live = OnlineLiveTranscriber(
        OnlineAiProvider.gemini,
        'fake',
        'gemini-live',
        connector: (_, _) async => socket,
        finishTimeout: const Duration(seconds: 1),
      );
      await live.start(language: 'en');
      live.addAudio(_speech(1607));
      expect(await live.finish(), 'Milk 100.');
    },
  );

  test(
    'silent pause acknowledgement does not require invented transcript text',
    () async {
      final socket = _Socket()..transcribe = false;
      final live = OnlineLiveTranscriber(
        OnlineAiProvider.gemini,
        'fake',
        'gemini-live',
        connector: (_, _) async => socket,
        finishTimeout: const Duration(seconds: 1),
      );
      await live.start(language: 'en');
      live.addAudio(Uint8List(3200));
      expect(await live.pause(), '');
      expect(socket.closed, isFalse);
      expect(await live.finish(), '');
    },
  );

  test('Gemini waits for each acknowledgement and preserves queued PCM sample order', () async {
    final socket = _Socket()..reply = false;
    final live = OnlineLiveTranscriber(
      OnlineAiProvider.gemini,
      'test-key',
      'gemini-3.8-live',
      connector: (_, _) async => socket,
    );
    await live.start(language: 'en');
    final pcm = _speech(80000);
    live.addAudio(Uint8List.sublistView(pcm, 0, pcm.length - 1));
    live.addAudio(Uint8List.sublistView(pcm, pcm.length - 1));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(socket.ends, 1);
    expect(socket.audio.length, 64000);
    socket.reply = true;
    socket.completeSegment();
    await live.finish();
    expect(socket.ends, 3);
    expect(socket.audio.toBytes(), pcm);
  });

  test(
    'Gemini publishes chunk transcripts before Stop without resending audio',
    () async {
      final socket = _Socket();
      final updates = <String>[];
      final live = OnlineLiveTranscriber(
        OnlineAiProvider.gemini,
        'test-key',
        'gemini-3.8-live',
        connector: (_, _) async => socket,
      )..onTranscript = updates.add;
      await live.start(language: 'en');
      final first = _speech(32000), tail = _speech(8000);
      live.addAudio(first);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(updates.last, 'Milk 100.');
      expect(socket.closed, isFalse);
      expect(socket.ends, 1);
      live.addAudio(tail);
      expect(await live.finish(), 'Milk 100. Bus 40.');
      expect(socket.audio.toBytes(), [...first, ...tail]);
      expect(socket.ends, 2);
      expect(socket.closed, isTrue);
    },
  );

  test('an earlier Gemini chunk cannot finalize audio still awaiting transcription', () async {
    final socket = _Socket();
    final live = OnlineLiveTranscriber(
      OnlineAiProvider.gemini,
      'test-key',
      'gemini-3.8-live',
      connector: (_, _) async => socket,
    );
    await live.start(language: 'en');
    live.addAudio(_speech(32000));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    socket.reply = false;
    live.addAudio(_speech(8000));
    var completed = false;
    final stopping = live.finish().then((text) {
      completed = true;
      return text;
    });
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(completed, isFalse);
    socket.completeSegment();
    expect(await stopping, 'Milk 100. Bus 40.');
  });
}
