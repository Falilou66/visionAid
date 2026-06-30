import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  final SpeechToText _stt = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;

  Future<bool> init() async {
    _isAvailable = await _stt.initialize(
      onError: (error) => _isListening = false,
    );
    return _isAvailable;
  }

  Future<void> listen({
    required Function(String text) onResult,
    Function()? onListenStart,
    String localeId = 'fr_FR',
  }) async {
    if (!_isAvailable || _isListening) return;

    _isListening = true;
    onListenStart?.call();

    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
      onResult: (result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
        }
      },
    );
  }

  Future<void> stop() async {
    await _stt.stop();
    _isListening = false;
  }

  Future<List<LocaleName>> getLocales() async {
    return await _stt.locales();
  }
}
