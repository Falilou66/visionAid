import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String _currentLanguage = 'fr-FR';

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    if (Platform.isIOS) {
      // Jouer via le haut-parleur même si le téléphone est en mode silencieux
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    // Make `await speak(...)` block until the utterance actually finishes.
    // The whole hands-free anti-feedback design depends on this: callers pause
    // the mic, speak, then resume — if speak() returned before the audio ended,
    // the mic would reopen while Kangue is still talking and loop on its own TTS.
    await _tts.awaitSpeakCompletion(true);

    await _tts.setLanguage(_currentLanguage);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((_) => _isSpeaking = false);
  }

  Future<void> speak(String text) async {
    if (_isSpeaking) await stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> setLanguage(String langCode) async {
    _currentLanguage = langCode;
    await _tts.setLanguage(langCode);
  }

  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }
}
