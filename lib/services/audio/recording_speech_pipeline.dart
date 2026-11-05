import 'dart:async';
import 'dart:typed_data';

import '../ai/speech_transcriber.dart';
import 'live_transcription_queue.dart';
import 'speech_audio_filter.dart';

/// Recording owns framing, silence filtering and speech-boundary flushes.
/// All current and future online speech clients receive audio through this class.
/// Clients own only their encoding, transport and protocol-specific batching.
class RecordingSpeechPipeline implements OnlineSpeechTranscriber {
  RecordingSpeechPipeline(
    this._client, {
    this.pauseTimeout = const Duration(milliseconds: 750),
    this.finishTimeout = const Duration(seconds: 30),
  }) {
    _audio = SpeechAudioFilter(
      onAudio: (pcm) {
        _hasPendingAudio = true;
        _client.addAudio(pcm);
      },
      onSpeechEnd: () {
        unawaited(
          _flushes.request().catchError((Object error) => _fail(error)),
        );
      },
    );
    _client.onTranscript = (text) {
      if (!_closed && _audio.hasSpeech) onTranscript?.call(text);
    };
    _client.onError = _fail;
  }

  final OnlineSpeechTranscriber _client;
  final Duration pauseTimeout, finishTimeout;
  late final SpeechAudioFilter _audio;
  late final _flushes = LiveTranscriptionQueue((_) async {
    if (_closed || !_hasPendingAudio) return;
    _hasPendingAudio = false;
    await _client.pause();
  });
  bool _started = false, _ready = false, _closed = false;
  bool _hasPendingAudio = false;
  LiveTranscriptionException? _failure;
  @override
  void Function(String)? onTranscript;
  @override
  void Function(LiveTranscriptionException)? onError;
  @override
  String get transcript => _audio.hasSpeech ? _client.transcript : '';

  @override
  Future<void> start({required String language}) async {
    if (_closed || _started) {
      throw const LiveTranscriptionException(
        'This recording session cannot be restarted.',
      );
    }
    _started = true;
    try {
      await _client.start(language: language);
      _checkOpen();
      _ready = true;
    } catch (_) {
      close();
      rethrow;
    }
  }

  @override
  void addAudio(Uint8List pcm) {
    if (_closed || _failure != null || pcm.isEmpty) return;
    if (!_ready) {
      _fail(
        const LiveTranscriptionException(
          'The speech model is not ready. Please record again.',
        ),
      );
      return;
    }
    _audio.add(pcm);
  }

  void _flushAudio() {
    _checkOpen();
    try {
      _audio.flush();
    } on FormatException catch (error) {
      final failure = LiveTranscriptionException(error.message);
      _fail(failure);
      throw failure;
    }
  }

  Future<String> _pause() async {
    _flushAudio();
    await _flushes.request();
    _checkOpen();
    return transcript;
  }

  @override
  Future<String> pause() =>
      _pause().timeout(pauseTimeout, onTimeout: () => transcript);

  @override
  Future<String> finish() async {
    try {
      return await (() async {
        _flushAudio();
        await _flushes.request();
        _checkOpen();
        if (!_audio.hasSpeech) return '';
        return await _client.finish();
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

  void _checkOpen() {
    if (_failure != null) throw _failure!;
    if (_closed) {
      throw const LiveTranscriptionException(
        'Live transcription was cancelled.',
      );
    }
  }

  void _fail(Object error) {
    if (_closed || _failure != null) return;
    _failure = error is LiveTranscriptionException
        ? error
        : const LiveTranscriptionException(
            'Live transcription failed. Please record again.',
          );
    onError?.call(_failure!);
    close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _audio.close();
    _flushes.cancelPending();
    _client.close();
    onTranscript = null;
    onError = null;
  }
}
