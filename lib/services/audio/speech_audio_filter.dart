import 'dart:collection';
import 'dart:typed_data';

/// Provider-independent, level-based voice activity gate for 16 kHz mono PCM16.
/// Keeps word lead-in and a short trailing pause; drops silence-only stretches.
class SpeechAudioFilter {
  SpeechAudioFilter({required this.onAudio, required this.onSpeechEnd});

  final void Function(Uint8List) onAudio;
  final void Function() onSpeechEnd;
  static const frameBytes =
      640; // 20 ms, including arbitrary plugin boundaries.
  static const leadBytes = 6400; // 200 ms before speech starts.
  static const trailingSamples = 5120; // 320 ms before ending an utterance.
  static const maxSpeechSamples = 24000; // 1.5 s live chunks for every client.
  final _pending = BytesBuilder(copy: false);
  final _lead = ListQueue<Uint8List>();
  int _leadLength = 0, _quietSamples = 0, _segmentSamples = 0;
  bool _speaking = false, _closed = false;
  bool hasSpeech = false;

  void add(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return;
    _pending.add(pcm);
    if (_pending.length < frameBytes) return;
    final bytes = _pending.takeBytes();
    var offset = 0;
    while (offset + frameBytes <= bytes.length) {
      _frame(Uint8List.sublistView(bytes, offset, offset + frameBytes));
      offset += frameBytes;
    }
    if (offset < bytes.length) {
      _pending.add(Uint8List.sublistView(bytes, offset));
    }
  }

  void _frame(Uint8List frame) {
    final count = frame.length ~/ 2;
    if (count == 0) return;
    final values = ByteData.sublistView(frame);
    var sum = 0, squares = 0;
    for (var i = 0; i < frame.length; i += 2) {
      final sample = values.getInt16(i, Endian.little);
      sum += sample;
      squares += sample * sample;
    }
    final mean = sum / count;
    // DC offset is not speech. Keep the same low-volume threshold for all clients.
    final voiced = squares / count - mean * mean >= 180 * 180;
    if (!_speaking && !voiced) {
      _lead.add(Uint8List.fromList(frame));
      _leadLength += frame.length;
      while (_leadLength > leadBytes) {
        _leadLength -= _lead.removeFirst().length;
      }
      return;
    }
    if (!_speaking) {
      hasSpeech = true;
      _speaking = true;
      _segmentSamples = _leadLength ~/ 2;
      while (_lead.isNotEmpty) {
        onAudio(_lead.removeFirst());
      }
      _leadLength = 0;
    }
    onAudio(frame);
    _segmentSamples += count;
    _quietSamples = voiced ? 0 : _quietSamples + count;
    if (_quietSamples >= trailingSamples ||
        _segmentSamples >= maxSpeechSamples) {
      _endSpeech();
    }
  }

  void _endSpeech() {
    _speaking = false;
    _quietSamples = 0;
    _segmentSamples = 0;
    onSpeechEnd();
  }

  void flush() {
    if (_closed) return;
    if (_pending.length.isOdd) {
      throw const FormatException(
        'The recording ended with an incomplete audio sample. Please record again.',
      );
    }
    if (_pending.isNotEmpty) _frame(_pending.takeBytes());
    if (_speaking) _endSpeech();
    _lead.clear();
    _leadLength = 0;
  }

  void close() {
    _closed = true;
    _pending.clear();
    _lead.clear();
    _leadLength = 0;
  }
}
