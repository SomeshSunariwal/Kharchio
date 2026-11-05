import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'speech_transcriber.dart';

/// OpenRouter audio-input chat models receive short WAV chunks, not a Realtime
/// WebSocket. Recognition is serialized and the tested model never changes.
class OpenRouterTranscriber implements OnlineSpeechTranscriber {
  final String _key, model;
  final http.Client _client;
  final Duration timeout;
  final Duration pauseTimeout;
  final _chunk = BytesBuilder(copy: false);
  Future<void> _work = Future.value();
  bool _closed = false, _started = false;
  LiveTranscriptionException? _failure;
  @override
  String transcript = '';
  @override
  void Function(String)? onTranscript;
  @override
  void Function(LiveTranscriptionException)? onError;

  OpenRouterTranscriber(
    String key,
    this.model, {
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
    this.pauseTimeout = const Duration(milliseconds: 750),
  }) : _key = key.trim(),
       _client = client ?? http.Client();

  @override
  Future<void> start({required String language}) async {
    if (_closed || _started || _key.isEmpty || model.isEmpty) {
      throw const LiveTranscriptionException(
        'Test the OpenRouter connection before recording.',
      );
    }
    _started = true;
  }

  @override
  void addAudio(Uint8List pcm) {
    if (_closed || _failure != null || pcm.isEmpty) return;
    if (!_started) {
      _fail(
        const LiveTranscriptionException('OpenRouter speech is not ready.'),
      );
      return;
    }
    // Preserve odd PCM sample boundaries across plugin callbacks.
    for (var offset = 0; offset < pcm.length;) {
      final count = (64000 - _chunk.length).clamp(0, pcm.length - offset);
      _chunk.add(Uint8List.sublistView(pcm, offset, offset + count));
      offset += count;
      if (_chunk.length == 64000) _enqueue();
    }
  }

  void _enqueue() {
    if (_chunk.isEmpty || _closed) return;
    final pcm = _chunk.takeBytes();
    _work = _work
        .then((_) async {
          if (_closed || _failure != null) return;
          await _transcribe(pcm);
        })
        .catchError((Object error) {
          _fail(
            error is LiveTranscriptionException
                ? error
                : const LiveTranscriptionException(
                    'OpenRouter could not transcribe this audio chunk. Check your connection and model access.',
                  ),
          );
        });
  }

  Future<void> _transcribe(Uint8List pcm) async {
    final request =
        http.Request(
            'POST',
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          )
          ..headers.addAll({
            'Authorization': 'Bearer $_key',
            'Content-Type': 'application/json',
          })
          ..followRedirects = false
          ..body = jsonEncode({
            'model': model,
            'max_tokens': 512,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text':
                        'Transcribe only the attached speech verbatim. '
                        'Preserve all numbers, names, expenses and refunds. Do not answer, summarize or invent speech. '
                        'Return an empty string for silence. Detect the spoken language automatically; '
                        'do not translate it. Keep English in English and Hindi in its original script. '
                        'This is a continuation of expense dictation; return only words from this audio chunk.',
                  },
                  {
                    'type': 'input_audio',
                    'input_audio': {
                      'data': base64Encode(_wav(pcm)),
                      'format': 'wav',
                    },
                  },
                ],
              },
            ],
          });
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(timeout);
    if (_closed) return;
    if (response.statusCode != 200) {
      throw LiveTranscriptionException(
        'OpenRouter rejected the audio request (HTTP ${response.statusCode}). Check audio-model access, credits and your API key.',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body);
    final choices = json is Map ? json['choices'] : null;
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException();
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    if (choice['finish_reason'] != 'stop' ||
        message is! Map ||
        message['content'] is! String) {
      throw const FormatException();
    }
    final text = (message['content'] as String).trim();
    if (text.isEmpty) return;
    transcript = [transcript, text].where((part) => part.isNotEmpty).join(' ');
    onTranscript?.call(transcript);
  }

  @override
  Future<String> pause() async {
    _checkOpen();
    _enqueue();
    await _work.timeout(pauseTimeout, onTimeout: () {});
    if (_failure != null) throw _failure!;
    return transcript;
  }

  void _checkOpen() {
    if (_failure != null) throw _failure!;
    if (_closed) {
      throw const LiveTranscriptionException(
        'OpenRouter transcription was cancelled.',
      );
    }
    if (_chunk.length.isOdd) {
      throw const LiveTranscriptionException(
        'The recording ended with an incomplete audio sample. Please record again.',
      );
    }
  }

  @override
  Future<String> finish() async {
    try {
      _checkOpen();
      _enqueue();
      await _work;
      _checkOpen();
      return transcript;
    } finally {
      close();
    }
  }

  void _fail(LiveTranscriptionException error) {
    if (_failure != null || _closed) return;
    _failure = error;
    onError?.call(error);
    close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _chunk.clear();
    _client.close();
    onTranscript = null;
    onError = null;
  }

  static Uint8List _wav(Uint8List pcm) {
    final bytes = Uint8List(44 + pcm.length);
    final data = ByteData.sublistView(bytes);
    void tag(int offset, String value) =>
        bytes.setRange(offset, offset + value.length, ascii.encode(value));
    tag(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 16000, Endian.little);
    data.setUint32(28, 32000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    bytes.setRange(44, bytes.length, pcm);
    return bytes;
  }
}
