import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import 'openrouter_transcriber.dart';
import 'speech_transcriber.dart';
export 'speech_transcriber.dart';

typedef LiveSocketConnector = Future<WebSocket> Function(
  Uri uri,
  Map<String, dynamic> headers,
);
typedef OnlineLiveFactory = OnlineSpeechTranscriber Function(
  OnlineAiProvider provider,
  String key,
  String model,
);
final onlineLiveFactoryProvider = Provider<OnlineLiveFactory>(
  (ref) => createOnlineSpeechTranscriber,
);

OnlineSpeechTranscriber createOnlineSpeechTranscriber(
  OnlineAiProvider provider,
  String key,
  String model,
) => provider == OnlineAiProvider.openrouter
    ? OpenRouterTranscriber(key, model)
    : OnlineLiveTranscriber(provider, key, model);

/// A recording owns one socket. Each PCM16 sample is sent once in 100 ms frames.
/// No recording files, API-key logging, model discovery, or model fallback.
class OnlineLiveTranscriber implements OnlineSpeechTranscriber {
  final OnlineAiProvider provider;
  final String _key;
  final String model;
  final LiveSocketConnector _connect;
  final Duration connectTimeout, finishTimeout, pauseTimeout;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  final _setup = Completer<void>();
  final _pending = BytesBuilder(copy: false);
  final _queuedAfterPause = BytesBuilder(copy: false);
  Future<String>? _pauseWork;
  Timer? _frameTimer, _displayTimer, _settleTimer;
  Completer<void>? _finalized;
  bool _closed = false, _ready = false, _activityOpen = false;
  bool _transcriptionFinished = false, _turnComplete = false;
  bool _geminiVoiceEnded = false;
  bool _geminiSegmentOpen = false, _geminiSeparateText = false;
  bool _geminiWaiting = false;
  Timer? _geminiNextSegmentTimer;
  double? _geminiEndedAt;
  LiveTranscriptionException? _failure;
  String _committed = '', _turnText = '', _interim = '';
  int sentBytes = 0;
  void Function(String)? onTranscript;
  void Function(LiveTranscriptionException)? onError;
  final _resampler = Pcm16To24k();
  final _openAiItems = <String, String>{};
  final _openAiOrder = <String>[];
  final _openAiDone = <String>{};
  int _openAiCommits = 0, _openAiAcks = 0, _openAiBytes = 0;

  OnlineLiveTranscriber(
    this.provider,
    String key,
    this.model, {
    LiveSocketConnector? connector,
    this.connectTimeout = const Duration(seconds: 12),
    this.finishTimeout = const Duration(seconds: 30),
    this.pauseTimeout = const Duration(milliseconds: 750),
  }) : _key = key.trim(),
       _connect =
           connector ??
           ((uri, headers) => WebSocket.connect(
             uri.toString(),
             headers: headers,
             compression: CompressionOptions.compressionOff,
           )) {
    _setup.future.ignore();
  }

  static String _join(String left, String right) {
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    return '${left.trimRight()} ${right.trimLeft()}';
  }

  @override
  String get transcript {
    if (provider == OnlineAiProvider.openai) {
      return _openAiOrder
          .map((id) => _openAiItems[id] ?? '')
          .where((text) => text.trim().isNotEmpty)
          .join(' ')
          .trim();
    }
    final provisional =
        _interim.startsWith(_turnText.trimLeft()) && _interim.isNotEmpty
        ? _interim
        : _join(_turnText, _interim);
    return _join(_committed, provisional).trim();
  }

  @override
  Future<void> start({required String language}) async {
    if (_closed || _socket != null) {
      throw const LiveTranscriptionException(
        'The live session is already closed or started.',
      );
    }
    if (_key.isEmpty || model.isEmpty) {
      throw const LiveTranscriptionException(
        'Test the online connection before recording.',
      );
    }
    // The official Live protocol authenticates its WebSocket handshake by key.
    // Never expose this URI or raw socket exceptions to UI, logs, or analytics.
    final uri = provider == OnlineAiProvider.openai
        ? Uri.parse('wss://api.openai.com/v1/realtime?intent=transcription')
        : Uri.https(
            'generativelanguage.googleapis.com',
            '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
            {'key': _key},
          ).replace(scheme: 'wss');
    try {
      final connecting = _connect(
        uri,
        provider == OnlineAiProvider.openai
            ? {'Authorization': 'Bearer $_key'}
            : {},
      );
      unawaited(
        connecting.then((socket) {
          if (_closed) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await connecting.timeout(connectTimeout);
      if (_closed) {
        throw const LiveTranscriptionException(
          'Live transcription was cancelled.',
        );
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 20);
      _subscription = socket.listen(
        _receive,
        onError: (Object _) => _fail(
          const LiveTranscriptionException(
            'The live speech connection was interrupted. Please record again.',
          ),
        ),
        onDone: () {
          if (!_closed) {
            final code = socket.closeCode;
            _fail(
              LiveTranscriptionException(
                code == 1008
                    ? 'The provider rejected the live session. Test Connection again or select another speech model.'
                    : 'The provider ended the live connection. Please record again.',
                statusCode: code == 1008 ? 403 : 503,
              ),
            );
          }
        },
      );
      if (provider == OnlineAiProvider.openai) {
        _send({
          'type': 'session.update',
          'session': {
            'type': 'transcription',
            'audio': {
              'input': {
                'format': {'type': 'audio/pcm', 'rate': 24000},
                'transcription': {
                  'model': model,
                  if (model == 'gpt-realtime-whisper') 'delay': 'minimal',
                  if (model != 'gpt-realtime-whisper') 'prompt': 'Expense and refund dictation. Detect the spoken language automatically. Preserve the original language, script, names and amounts.',
                },
                'turn_detection': null,
                'noise_reduction': {'type': 'near_field'},
              },
            },
          },
        });
      } else {
        _send({
          'setup': {
            'model': 'models/$model',
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'maxOutputTokens': 32,
            },
            'inputAudioTranscription': {},
            'realtimeInputConfig': {
              'automaticActivityDetection': {'disabled': true},
              'interimTranscriptTimestampEnabled': true,
            },
            'systemInstruction': {
              'parts': [
                {
                  'text':
                      'Listen to expense and refund dictation. Do not speak, answer, or invent any words. '
                      'Input transcription is displayed by the app. Detect the spoken language automatically and preserve its script, amounts and names exactly. '
                      'Silence and background noise contain no words. Never invent text for them.',
                },
              ],
            },
          },
        });
      }
      await _setup.future.timeout(connectTimeout);
      if (_failure != null) throw _failure!;
      _ready = true;
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _sendAudio(),
      );
    } on LiveTranscriptionException {
      close();
      rethrow;
    } on WebSocketException catch (error) {
      close();
      throw LiveTranscriptionException(
        'Could not open the live speech connection. Check model access and test the connection again.',
        statusCode: error.httpStatusCode,
      );
    } on TimeoutException {
      close();
      throw const LiveTranscriptionException(
        'The live speech connection timed out. Check your connection and try again.',
      );
    } catch (_) {
      close();
      throw const LiveTranscriptionException(
        'Could not connect to live speech. Check your internet connection and model access.',
      );
    }
  }

  @override
  void addAudio(Uint8List pcm) {
    if (_closed || _failure != null || pcm.isEmpty) return;
    if (_pauseWork != null) {
      _queuedAfterPause.add(pcm);
      return;
    }
    if (!_ready) {
      _fail(
        const LiveTranscriptionException(
          'The live speech model is not ready. Please record again.',
        ),
      );
      return;
    }
    _openActivity();
    _pending.add(pcm);
    // Never queue an entire recording waiting for a timer tick.
    if (_pending.length >= 3200) _sendAudio();
  }

  void _openActivity() {
    if (!_activityOpen) {
      _committed = _join(_committed, _turnText);
      _turnText = '';
      _interim = '';
      _transcriptionFinished = false;
      _turnComplete = false;
      _geminiVoiceEnded = false;
      _activityOpen = true;
    }
  }

  void _sendAudio() {
    if (_closed || _failure != null || _pending.isEmpty) return;
    if (provider == OnlineAiProvider.gemini && _geminiWaiting) return;
    final bytes = _pending.takeBytes();
    final length = bytes.length & ~1;
    for (var offset = 0; offset < length; offset += 3200) {
      if (provider == OnlineAiProvider.gemini && _geminiWaiting) {
        _pending.add(Uint8List.sublistView(bytes, offset));
        return;
      }
      final end = (offset + 3200).clamp(0, length);
      final frame = Uint8List.sublistView(bytes, offset, end);
      if (provider == OnlineAiProvider.openai) {
        final converted = _resampler.convert(frame);
        _openAiBytes += converted.length;
        _send({
          'type': 'input_audio_buffer.append',
          'audio': base64Encode(converted),
        });
      } else {
        if (!_geminiSegmentOpen) {
          _send({
            'realtimeInput': {'activityStart': {}},
          });
          _geminiSegmentOpen = true;
          _transcriptionFinished = false;
          _turnComplete = false;
          _geminiVoiceEnded = false;
          _settleTimer?.cancel();
        }
        _sendGeminiFrame(frame);
      }
      sentBytes += end - offset;
    }
    if (bytes.length.isOdd) {
      _pending.add(Uint8List.sublistView(bytes, bytes.length - 1));
    }
  }

  void _sendGeminiFrame(Uint8List frame) => _send({
    'realtimeInput': {
      'audio': {
        'mimeType': 'audio/pcm;rate=16000',
        'data': base64Encode(frame),
      },
    },
  });

  void _endGeminiSegment() {
    if (!_geminiSegmentOpen) return;
    _geminiWaiting = true;
    _send({
      'realtimeInput': {'activityEnd': {}},
    });
    _geminiSegmentOpen = false;
  }

  @override
  Future<String> pause() => _beginPause().timeout(
    pauseTimeout,
    // Pause stops the microphone, not the provider session. Late acknowledgements
    // and transcripts remain attached to the same work and can still complete.
    onTimeout: () => transcript,
  );

  Future<String> _beginPause() {
    if (_pauseWork case final work?) return work;
    final work = _flushPausedAudio();
    _pauseWork = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_pauseWork, work)) _pauseWork = null;
          if (!_closed && _queuedAfterPause.isNotEmpty) {
            addAudio(_queuedAfterPause.takeBytes());
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_pauseWork, work)) _pauseWork = null;
        },
      ),
    );
    return work;
  }

  Future<String> _flushPausedAudio() async {
    if (_failure != null) throw _failure!;
    if (_closed) {
      throw const LiveTranscriptionException(
        'Live transcription was cancelled.',
      );
    }
    if (_finalized case final pending?) {
      await pending.future;
      return transcript;
    }
    if (!_activityOpen) return transcript;
    if (provider == OnlineAiProvider.gemini) {
      while (_pending.length >= 2) {
        if (_failure != null) throw _failure!;
        if (_closed) {
          throw const LiveTranscriptionException(
            'Live transcription was cancelled.',
          );
        }
        _sendAudio();
        if (_pending.length >= 2) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    } else {
      _sendAudio();
    }
    if (_pending.isNotEmpty) {
      throw const LiveTranscriptionException(
        'The recording ended with an incomplete audio sample. Please record again.',
      );
    }
    final done = Completer<void>();
    _finalized = done;
    if (provider == OnlineAiProvider.openai) {
      _commitOpenAi();
      _completeOpenAi();
    } else {
      _endGeminiSegment();
      _settleGemini();
    }
    _activityOpen = false;
    try {
      await done.future;
      if (_failure != null) throw _failure!;
      _notify(immediate: true);
      return transcript;
    } finally {
      _settleTimer?.cancel();
      if (identical(_finalized, done)) _finalized = null;
    }
  }

  @override
  Future<String> finish() async {
    try {
      if (_failure != null) throw _failure!;
      if (_closed) {
        throw const LiveTranscriptionException(
          'Live transcription was cancelled.',
        );
      }
      return await (() async {
        while (_activityOpen || _pauseWork != null || _pending.isNotEmpty) {
          await _beginPause();
        }
        if (_failure != null) throw _failure!;
        return transcript;
      })().timeout(
        finishTimeout,
        onTimeout: () {
          throw const LiveTranscriptionException(
            'The speech model did not finalize the transcript in time. Please record again.',
          );
        },
      );
    } finally {
      close();
    }
  }

  void _commitOpenAi() {
    if (_openAiBytes == 0 || _closed) return;
    // Realtime commits require at least 100 ms of audio. Pad only a very short
    // final fragment; all captured samples still go over the wire exactly once.
    if (_openAiBytes < 4800) {
      _send({
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(Uint8List(4800 - _openAiBytes)),
      });
    }
    _openAiCommits++;
    _send({
      'type': 'input_audio_buffer.commit',
      'event_id': 'commit_$_openAiCommits',
    });
    _openAiBytes = 0;
  }

  void _completeOpenAi() {
    if (_finalized case final pending? when !pending.isCompleted) {
      if (_openAiAcks >= _openAiCommits &&
          _openAiOrder.every(_openAiDone.contains)) {
        pending.complete();
      }
    }
  }

  void _receiveOpenAi(Map json) {
    final type = json['type'];
    if (type == 'session.updated' || type == 'transcription_session.updated') {
      if (!_setup.isCompleted) _setup.complete();
    } else if (type == 'input_audio_buffer.committed') {
      final id = json['item_id'];
      if (id is! String) throw const FormatException();
      if (!_openAiOrder.contains(id)) {
        final previous = json['previous_item_id'];
        final after = previous is String ? _openAiOrder.indexOf(previous) : -1;
        if (after >= 0 && after < _openAiOrder.length - 1) {
          _openAiOrder.insert(after + 1, id);
        } else {
          _openAiOrder.add(id);
        }
      }
      _openAiAcks++;
      _completeOpenAi();
    } else if (type == 'conversation.item.input_audio_transcription.delta' ||
        type == 'conversation.item.input_audio_transcription.completed') {
      if (sentBytes == 0) return;
      final id = json['item_id'];
      if (id is! String) throw const FormatException();
      if (!_openAiOrder.contains(id)) _openAiOrder.add(id);
      if (type == 'conversation.item.input_audio_transcription.completed') {
        if (json['transcript'] is! String) throw const FormatException();
        _openAiItems[id] = json['transcript'] as String;
        _openAiDone.add(id);
      } else if (!_openAiDone.contains(id) && json['delta'] is String) {
        _openAiItems[id] = '${_openAiItems[id] ?? ''}${json['delta']}';
      }
      _notify();
      _completeOpenAi();
    } else if (type == 'error' ||
        type == 'conversation.item.input_audio_transcription.failed') {
      final error = json['error'];
      final code = error is Map ? error['code'] : null;
      final status = switch (code) {
        'invalid_api_key' => 401,
        'insufficient_quota' || 'rate_limit_exceeded' => 429,
        'model_not_found' => 404,
        _ => null,
      };
      _fail(
        LiveTranscriptionException(
          'OpenAI could not continue live transcription. Check model access, billing and your connection.',
          statusCode: status,
        ),
      );
    }
  }

  void _send(Map<String, Object?> message) {
    if (_closed || _socket == null) return;
    try {
      _socket!.add(jsonEncode(message));
    } catch (_) {
      _fail(
        const LiveTranscriptionException(
          'The live speech connection was interrupted. Please record again.',
        ),
      );
    }
  }

  void _receive(dynamic frame) {
    if (_closed) return;
    try {
      final json = jsonDecode(
        frame is String ? frame : utf8.decode(frame as List<int>),
      );
      if (json is! Map) throw const FormatException();
      if (provider == OnlineAiProvider.openai) {
        _receiveOpenAi(json);
        return;
      }
      if (json['error'] is Map) {
        final status = (json['error'] as Map)['code'];
        _fail(
          LiveTranscriptionException(
            'Gemini could not start or continue live transcription. Test Connection again.',
            statusCode: status is int ? status : null,
          ),
        );
        return;
      }
      if (json.containsKey('setupComplete') && !_setup.isCompleted) {
        _setup.complete();
      }
      if (json.containsKey('goAway')) {
        _fail(
          const LiveTranscriptionException(
            'The Gemini live session is ending. Please record again.',
          ),
        );
        return;
      }
      final content = json['serverContent'];
      final voice = json['voiceActivity'];
      if (voice is Map) {
        // The wire protocol uses `type`; the SDK exposes voiceActivityType.
        final type = voice['type'] ?? voice['voiceActivityType'];
        if (type == 'ACTIVITY_START') {
          _geminiVoiceEnded = false;
          _transcriptionFinished = false;
          _settleTimer?.cancel();
        } else if (type == 'ACTIVITY_END') {
          _geminiVoiceEnded = true;
          _geminiSeparateText = true;
          final offset = voice['audioOffset'];
          if (offset is String && offset.endsWith('s')) {
            _geminiEndedAt = double.tryParse(
              offset.substring(0, offset.length - 1),
            );
          }
          _settleGemini();
          _resumeGeminiAudio();
        }
      }
      if (content is! Map) return;
      final finalPart = content['inputTranscription'];
      if (finalPart is Map && sentBytes > 0) {
        final delta = finalPart['text'];
        if (delta is String && delta.isNotEmpty) {
          _turnText = _geminiSeparateText
              ? _join(_turnText, delta)
              : _turnText + delta;
          _geminiSeparateText = false;
        }
        _interim = '';
        if (finalPart['finished'] == true) {
          _transcriptionFinished = true;
          _geminiSeparateText = true;
          _resumeGeminiAudio();
        }
        _notify();
      }
      final interim = content['interimInputTranscription'];
      if (interim is Map && interim['text'] is String && sentBytes > 0) {
        _interim = interim['text'] as String;
        _notify();
      }
      if (content['turnComplete'] == true) {
        _turnComplete = true;
        _geminiSeparateText = true;
        _resumeGeminiAudio();
      }
      // Transcription is independent of generated replies. Prefer its finished
      // signal, while retaining compatibility with older Live model responses.
      _settleGemini();
    } catch (_) {
      _fail(
        const LiveTranscriptionException(
          'The speech model returned an invalid live transcription message. Please record again.',
        ),
      );
    }
  }

  void _resumeGeminiAudio() {
    if (!_geminiWaiting) return;
    _geminiNextSegmentTimer?.cancel();
    _geminiNextSegmentTimer = Timer(const Duration(milliseconds: 200), () {
      _geminiWaiting = false;
      if (!_closed) _sendAudio();
    });
  }

  void _settleGemini() {
    // An earlier chunk's completion must not finalize later, unprocessed audio.
    if (_geminiEndedAt case final endedAt?
        // Gemini reports offsets rounded to milliseconds (up to 16 samples).
        when endedAt * 16000 + 16 < sentBytes ~/ 2) {
      return;
    }
    if (_finalized == null ||
        !(_transcriptionFinished || _turnComplete || _geminiVoiceEnded)) {
      return;
    }
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 500), () {
      if (_finalized case final pending? when !pending.isCompleted) {
        pending.complete();
      }
    });
  }

  void _notify({bool immediate = false}) {
    if (immediate) {
      _displayTimer?.cancel();
      _displayTimer = null;
      onTranscript?.call(transcript);
    } else {
      _displayTimer ??= Timer(const Duration(milliseconds: 50), () {
        _displayTimer = null;
        if (!_closed) onTranscript?.call(transcript);
      });
    }
  }

  void _fail(LiveTranscriptionException error) {
    if (_failure != null || _closed) return;
    _failure = error;
    if (!_setup.isCompleted) _setup.completeError(error);
    if (_finalized case final pending? when !pending.isCompleted) {
      pending.completeError(error);
    }
    onError?.call(error);
    close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _frameTimer?.cancel();
    _displayTimer?.cancel();
    _settleTimer?.cancel();
    _geminiNextSegmentTimer?.cancel();
    _pending.clear();
    _queuedAfterPause.clear();
    if (_finalized case final pending? when !pending.isCompleted) {
      pending.completeError(
        _failure ??
            const LiveTranscriptionException(
              'Live transcription was cancelled.',
            ),
      );
    }
    if (!_setup.isCompleted) {
      _setup.completeError(
        const LiveTranscriptionException('Live transcription was cancelled.'),
      );
    }
    unawaited(_subscription?.cancel());
    unawaited(_socket?.close());
    onTranscript = null;
    onError = null;
  }
}

/// Stateful linear interpolation preserves sample continuity across mic chunks.
/// Realtime transcription expects mono PCM16 at 24 kHz; capture stays at 16 kHz.
class Pcm16To24k {
  int? _previous;
  int _inputSamples = 0, _nextOutputThirds = 0;

  Uint8List convert(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final output = <int>[];
    void write(int value) {
      output.add(value & 255);
      output.add((value >> 8) & 255);
    }

    for (var offset = 0; offset + 1 < pcm.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final index = _inputSamples++;
      if (_previous == null) {
        write(sample);
        _nextOutputThirds = 2;
      } else {
        while (_nextOutputThirds <= index * 3) {
          final fraction = (_nextOutputThirds - (index - 1) * 3) / 3;
          write(
            (_previous! + (sample - _previous!) * fraction).round().clamp(
              -32768,
              32767,
            ),
          );
          _nextOutputThirds += 2;
        }
      }
      _previous = sample;
    }
    return Uint8List.fromList(output);
  }
}

Uint8List wavToPcm(Uint8List wav) {
  if (wav.length < 44 ||
      ascii.decode(wav.sublist(0, 4)) != 'RIFF' ||
      ascii.decode(wav.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Invalid diagnostic audio.');
  }
  final view = ByteData.sublistView(wav);
  var pcm16 = false;
  for (var offset = 12; offset + 8 <= wav.length;) {
    final size = view.getUint32(offset + 4, Endian.little);
    final begin = offset + 8, end = begin + size;
    if (end > wav.length) {
      throw const FormatException('Invalid diagnostic audio.');
    }
    final tag = ascii.decode(wav.sublist(offset, offset + 4));
    if (tag == 'fmt ' && size >= 16) {
      pcm16 =
          view.getUint16(begin, Endian.little) == 1 &&
          view.getUint16(begin + 2, Endian.little) == 1 &&
          view.getUint32(begin + 4, Endian.little) == 16000 &&
          view.getUint16(begin + 14, Endian.little) == 16;
    } else if (tag == 'data' && pcm16) {
      return Uint8List.sublistView(wav, begin, end);
    }
    offset = end + (size & 1);
  }
  throw const FormatException('Expected 16 kHz mono PCM diagnostic audio.');
}
