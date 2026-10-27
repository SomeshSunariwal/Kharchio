import 'dart:async';

/// Serializes previews and coalesces requests into the latest audio snapshot.
/// A pause flush must survive a preview that was already running.
class LiveTranscriptionQueue {
  LiveTranscriptionQueue(this.transcribe);

  final Future<void> Function(bool flush) transcribe;
  Future<void>? _work;
  bool _pending = false;
  bool _flush = false;

  Future<void>? get work => _work;

  Future<void> request({bool flush = false}) {
    _pending = true;
    _flush |= flush;
    if (_work case final work?) return work;
    final completion = Completer<void>();
    _work = completion.future;
    unawaited(_drain(completion));
    return completion.future;
  }

  void cancelPending() {
    _pending = false;
    _flush = false;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      while (_pending) {
        final flush = _flush;
        _pending = false;
        _flush = false;
        await transcribe(flush);
      }
      completion.complete();
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _work = null;
    }
  }
}
