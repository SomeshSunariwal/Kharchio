import 'dart:typed_data';

abstract interface class OnlineSpeechTranscriber {
  String get transcript;
  set onTranscript(void Function(String)? callback);
  set onError(void Function(LiveTranscriptionException)? callback);
  Future<void> start({required String language});
  void addAudio(Uint8List pcm);
  Future<String> pause();
  Future<String> finish();
  void close();
}

class LiveTranscriptionException implements Exception {
  final String message;
  final int? statusCode;
  const LiveTranscriptionException(this.message, {this.statusCode});
  @override
  String toString() => message;
}
