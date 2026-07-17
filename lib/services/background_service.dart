import 'dart:io';
import 'package:flutter/services.dart';

/// Dart bridge to the native Android background + accessibility services.
///
/// - `com.kangue/background`  → foreground listening service (notification)
/// - `com.kangue/accessibility` → reads other apps' on-screen text
/// - `com.kangue/commands`    → voice commands pushed back from native
///
/// All methods degrade gracefully (no-op / false / empty) on non-Android
/// platforms so the rest of the app keeps working.
class BackgroundService {
  BackgroundService._();
  static final BackgroundService _instance = BackgroundService._();
  factory BackgroundService() => _instance;

  static const MethodChannel _bg = MethodChannel('com.kangue/background');
  static const MethodChannel _a11y = MethodChannel('com.kangue/accessibility');
  static const EventChannel _commands = EventChannel('com.kangue/commands');
  static const EventChannel _screen = EventChannel('com.kangue/screen');

  bool get _supported => Platform.isAndroid;

  /// Stores the API key native-side (used by the background service).
  Future<void> init(String apiKey) async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<bool>('init', {'apiKey': apiKey});
    } catch (_) {}
  }

  /// Whether the foreground listening service is currently running.
  Future<bool> isRunning() async {
    if (!_supported) return false;
    try {
      return await _bg.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts the foreground listening service. Returns true on success.
  Future<bool> start() async {
    if (!_supported) return false;
    try {
      return await _bg.invokeMethod<bool>('startService') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops the foreground listening service.
  Future<void> stop() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('stopService');
    } catch (_) {}
  }

  /// Triggers a single listening session from the native service.
  Future<void> triggerListen() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('triggerListen');
    } catch (_) {}
  }

  /// Whether the always-on hands-free listening loop is currently armed.
  Future<bool> isHandsFree() async {
    if (!_supported) return false;
    try {
      return await _bg.invokeMethod<bool>('isHandsFree') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Arms the continuous, wake-word-gated hands-free listening loop.
  /// Starts the foreground service first if needed.
  Future<void> startContinuous() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('startContinuous');
    } catch (_) {}
  }

  /// Disarms the hands-free listening loop (mic stops).
  Future<void> stopContinuous() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('stopContinuous');
    } catch (_) {}
  }

  /// Pauses the mic — MUST be called before speaking so the recogniser does not
  /// hear Kangue's own text-to-speech and loop on it.
  Future<void> pauseListening() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('pauseListening');
    } catch (_) {}
  }

  /// Resumes the hands-free loop after Kangue has finished speaking.
  Future<void> resumeListening() async {
    if (!_supported) return;
    try {
      await _bg.invokeMethod<void>('resumeListening');
    } catch (_) {}
  }

  // ── Accessibility ─────────────────────────────────────────────────────────

  /// Whether the Kangue accessibility service is enabled in system settings.
  Future<bool> isAccessibilityEnabled() async {
    if (!_supported) return false;
    try {
      return await _a11y.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system accessibility settings screen.
  Future<void> openAccessibilitySettings() async {
    if (!_supported) return;
    try {
      await _a11y.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  /// Returns the text last captured from the foreground app's screen.
  Future<String> getScreenText() async {
    if (!_supported) return '';
    try {
      return await _a11y.invokeMethod<String>('getScreenText') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Package name of the app currently in the foreground.
  Future<String> getCurrentPackage() async {
    if (!_supported) return '';
    try {
      return await _a11y.invokeMethod<String>('getCurrentPackage') ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Command stream ────────────────────────────────────────────────────────

  Stream<String>? _cachedStream;

  /// Voice commands emitted by the native background service.
  Stream<String> get commandStream {
    if (!_supported) return const Stream<String>.empty();
    return _cachedStream ??= _commands
        .receiveBroadcastStream()
        .map((event) => event?.toString() ?? '')
        .where((cmd) => cmd.isNotEmpty);
  }

  Stream<String>? _cachedScreenStream;

  /// Human-readable name of a newly-opened app, emitted by the accessibility
  /// service when the user switches apps (for spoken announcements).
  Stream<String> get screenChangeStream {
    if (!_supported) return const Stream<String>.empty();
    return _cachedScreenStream ??= _screen
        .receiveBroadcastStream()
        .map((event) => event?.toString() ?? '')
        .where((label) => label.isNotEmpty);
  }
}
