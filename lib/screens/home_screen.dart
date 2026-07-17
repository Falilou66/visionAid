import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/app_launcher_service.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../widgets/accessible_button.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _tts = TtsService();
  final _stt = SttService();
  final _gemini = GeminiService();
  final _launcher = AppLauncherService();
  final _bgService = BackgroundService();

  bool _isListening = false;
  bool _isProcessing = false;
  String _statusText = 'Appuyez sur le micro pour parler';
  String _lastCommand = '';
  String _lastResponse = '';

  // Android background service state
  bool _serviceRunning = false;
  bool _a11yEnabled = false;
  bool _handsFree = false;
  StreamSubscription<String>? _cmdSub;
  StreamSubscription<String>? _screenSub;

  // ─── Init ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  /// Boots sequentially so the always-on mic is armed **after** the greeting has
  /// finished speaking. Arming it during the greeting made the mic hear Kangue's
  /// own voice, mistake it for a wake word, and spiral into a TTS↔recogniser loop.
  Future<void> _boot() async {
    await _initServices();
    if (Platform.isAndroid) await _initAndroid();
  }

  Future<void> _initServices() async {
    await _stt.init();
    await Future.delayed(const Duration(milliseconds: 500));
    await _tts.speak(
      'Bonjour ! Je suis Kangue, votre assistant. '
      'Vous n\'avez pas besoin de toucher l\'écran : '
      'dites simplement « Jarvis » suivi de votre demande.',
    );
  }

  Future<void> _initAndroid() async {
    _a11yEnabled = await _bgService.isAccessibilityEnabled();

    // Auto-start the background listening service so the mic is always available
    // without the user having to find and tap a chip.
    _serviceRunning = await _bgService.isRunning();
    if (!_serviceRunning) {
      // Android 13+ requires runtime permission for the service notification.
      await NotificationService().requestPermission();
      _serviceRunning = await _bgService.start();
    }

    // Arm the always-on, wake-word-gated hands-free loop.
    await _bgService.startContinuous();
    _handsFree = await _bgService.isHandsFree();
    if (mounted) setState(() {});

    // Voice commands captured natively (wake word « Jarvis » already stripped).
    _cmdSub = _bgService.commandStream.listen(_onVoiceCommand);

    // Spoken announcement each time the user opens a different app.
    _screenSub = _bgService.screenChangeStream.listen(_announceScreen);
  }

  /// Routes a native voice command, handling the bare wake word specially and
  /// letting [_processCommand] guard the mic while Kangue speaks.
  Future<void> _onVoiceCommand(String command) async {
    if (!mounted || _isProcessing) return;
    if (command == '__wake__') {
      await _bgService.pauseListening();
      await _tts.speak('Oui, je vous écoute ?');
      await _bgService.resumeListening();
      return;
    }
    await _processCommand(command);
  }

  /// Speaks the name of a newly-opened app, without interrupting a command.
  Future<void> _announceScreen(String appLabel) async {
    if (!mounted || _isProcessing || _isListening) return;
    await _bgService.pauseListening();
    try {
      await _tts.speak(appLabel);
    } finally {
      await _bgService.resumeListening();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshAndroidState();
    }
  }

  Future<void> _refreshAndroidState() async {
    final running = await _bgService.isRunning();
    final a11y = await _bgService.isAccessibilityEnabled();
    final handsFree = await _bgService.isHandsFree();
    if (mounted) {
      setState(() {
        _serviceRunning = running;
        _a11yEnabled = a11y;
        _handsFree = handsFree;
      });
    }
  }

  // ─── Voice recognition ────────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
      return;
    }
    if (_isProcessing) return;

    setState(() {
      _isListening = true;
      _statusText = 'Je vous écoute...';
      _lastCommand = '';
    });

    // Yield the mic: the always-on native loop must not compete with the
    // in-app recogniser for the microphone.
    await _bgService.pauseListening();

    await _stt.listen(
      localeId: 'fr_FR',
      onListenStart: () => setState(() => _isListening = true),
      onResult: (text) async {
        if (text.isEmpty) {
          setState(() { _isListening = false; _statusText = 'Rien entendu. Réessayez.'; });
          await _bgService.resumeListening();
          return;
        }
        await _processCommand(text);
      },
    );
  }

  Future<void> _processCommand(String command) async {
    setState(() {
      _isListening = false;
      _isProcessing = true;
      _lastCommand = command;
      _statusText = 'Traitement...';
    });

    // Keep the always-on mic muted for the whole turn so it never captures
    // Kangue's own spoken answer (which would loop back as a fake command).
    await _bgService.pauseListening();

    String response = '';
    try {
      final intent = await _gemini.parseVoiceCommand(command);
      await _executeIntent(intent);
      response = intent.response;
    } finally {
      setState(() {
        _isProcessing = false;
        _lastResponse = response;
        _statusText = _handsFree
            ? 'Dites « Jarvis » pour me parler'
            : 'Appuyez sur le micro pour parler';
      });
      // Resume hands-free listening now that Kangue has finished speaking.
      await _bgService.resumeListening();
    }
  }

  // ─── Intent execution ─────────────────────────────────────────────────────

  Future<void> _executeIntent(CommandIntent intent) async {
    switch (intent.action) {
      case 'open_app':
        await _tts.speak(intent.response);
        final appName = intent.app ?? intent.target ?? '';
        if (appName.isNotEmpty) {
          final ok = await _launcher.launchByName(appName);
          if (!ok) await _tts.speak('Je n\'ai pas trouvé l\'application $appName.');
        }

      case 'send_message':
        await _tts.speak(intent.response);
        if (intent.app != null && intent.message != null) {
          final ok = await _launcher.sendMessage(
            app: intent.app!, recipientName: intent.target, message: intent.message!,
          );
          if (!ok) {
            await _tts.speak(intent.target != null
                ? 'Je n\'ai pas trouvé ${intent.target} dans vos contacts.'
                : 'Impossible d\'ouvrir l\'application de messagerie.');
          }
        }

      case 'make_call':
        await _tts.speak(intent.response);
        if (intent.target != null) {
          final ok = await _launcher.makeCall(intent.target!);
          if (!ok) await _tts.speak('Je n\'ai pas trouvé ${intent.target} dans vos contacts.');
        }

      case 'get_time':
        final now = DateTime.now();
        final h = now.hour;
        final m = now.minute.toString().padLeft(2, '0');
        final timeStr = 'Il est $h heure${h > 1 ? 's' : ''} $m.';
        await _tts.speak(timeStr);
        _updateResponse(timeStr);

      case 'get_weather':
        await _tts.speak('Je vérifie la météo...');
        final weather = await _gemini.getWeather();
        await _tts.speak(weather);
        _updateResponse(weather);

      case 'answer_question':
        final q = intent.query ?? _lastCommand;
        await _tts.speak('Je cherche...');
        final answer = await _gemini.answerQuestion(q);
        await _tts.speak(answer);
        _updateResponse(answer);

      case 'calculate':
        final calc = intent.query ?? _lastCommand;
        await _tts.speak('Je calcule...');
        final result = await _gemini.answerQuestion(calc);
        await _tts.speak(result);
        _updateResponse(result);

      case 'translate':
        final text = intent.query;
        final lang = intent.lang ?? 'anglais';
        if (text != null) {
          await _tts.speak('Je traduis...');
          final translated = await _gemini.translate(text, lang);
          await _tts.speak(translated);
          _updateResponse(translated);
        }

      case 'describe_surroundings':
        await _tts.speak('J\'ouvre la caméra pour décrire ce qui est devant vous.');
        if (mounted) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScannerScreen(autoCapture: true)));
        }

      case 'scan_document':
        await _tts.speak(
          'J\'ouvre le scanner. Placez le document devant la caméra, '
          'je vais le lire.',
        );
        if (mounted) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScannerScreen(autoCapture: true)));
        }

      case 'read_screen':
        await _readScreenContent();

      case 'set_reminder':
        await _tts.speak(intent.response);
        final q = intent.query ?? intent.target ?? '';
        if (q.isNotEmpty) await _launcher.openReminder(q);

      case 'help':
        const helpText =
            'Je peux vous aider à : ouvrir une application comme TikTok, WhatsApp ou Messenger, '
            'appeler quelqu\'un, envoyer un message, '
            'donner l\'heure, la météo, répondre à vos questions, '
            'faire des calculs, traduire, décrire ce qui est devant vous, '
            'scanner un document, ou lire l\'écran de votre téléphone. '
            'Parlez-moi naturellement.';
        await _tts.speak(helpText);
        _updateResponse(helpText);

      default:
        if (intent.response.isNotEmpty && intent.response != 'Commande reçue.') {
          await _tts.speak(intent.response);
          _updateResponse(intent.response);
        } else {
          final answer = await _gemini.answerQuestion(_lastCommand);
          await _tts.speak(answer);
          _updateResponse(answer);
        }
    }
  }

  // ─── Read screen content (Android/AccessibilityService) ───────────────────

  Future<void> _readScreenContent() async {
    if (!Platform.isAndroid) {
      await _tts.speak('La lecture d\'écran n\'est disponible que sur Android.');
      return;
    }

    if (!_a11yEnabled) {
      await _tts.speak(
        'Le service d\'accessibilité n\'est pas activé. '
        'Je vais ouvrir les paramètres. Activez Kangue dans la liste.',
      );
      await _bgService.openAccessibilitySettings();
      return;
    }

    await _tts.speak('Je lis l\'écran, un instant...');

    final screenText = await _bgService.getScreenText();
    if (screenText.isEmpty) {
      await _tts.speak(
        'Aucun texte détecté sur l\'écran. '
        'Revenez dans l\'application que vous souhaitez lire, puis redemandez.',
      );
      return;
    }

    final summary = await _gemini.answerQuestion(
      'Lis et résume ce contenu d\'écran de façon claire en 3 phrases maximum. '
      'Pas de markdown : $screenText',
    );
    await _tts.speak(summary);
    _updateResponse(summary);
  }

  // ─── Android service controls ─────────────────────────────────────────────

  Future<void> _toggleHandsFree() async {
    if (_handsFree) {
      await _bgService.stopContinuous();
      setState(() => _handsFree = false);
      await _tts.speak('Écoute mains libres désactivée.');
    } else {
      await _bgService.startContinuous();
      final on = await _bgService.isHandsFree();
      setState(() { _handsFree = on; _serviceRunning = true; });
      if (on) {
        await _tts.speak(
          'Écoute mains libres activée. Dites « Jarvis » suivi de votre demande, '
          'sans toucher l\'écran.',
        );
      }
    }
  }

  Future<void> _showA11yDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text(
          'Service d\'accessibilité',
          style: TextStyle(color: kTextColor, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Pour que Kangue puisse lire le contenu des autres applications '
          '(articles, messages, e-mails…), vous devez activer le service '
          'd\'accessibilité Kangue.\n\n'
          '1. Appuyez sur « Ouvrir les paramètres »\n'
          '2. Trouvez « Kangue » dans la liste\n'
          '3. Activez-le\n\n'
          'Dites ensuite « lis-moi cet article » pendant que vous lisez dans Chrome.',
          style: TextStyle(color: Colors.white70, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccentColor),
            onPressed: () async {
              Navigator.pop(ctx);
              await _bgService.openAccessibilitySettings();
            },
            child: const Text('Ouvrir les paramètres', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    await _refreshAndroidState();
  }

  void _updateResponse(String text) => setState(() => _lastResponse = text);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatusCard(),
            const SizedBox(height: 24),

            // Android background service banner
            if (Platform.isAndroid) _buildAndroidBanner(),

            const SizedBox(height: 16),
            _buildMicButton(),
            const SizedBox(height: 12),
            Text(
              _isListening ? 'Parlez maintenant...' : 'Parler',
              style: TextStyle(
                color: _isListening ? Colors.red.shade300 : Colors.white54,
                fontSize: kFontSizeSmall,
              ),
            ),
            const SizedBox(height: 28),
            _buildGrid(),
            const Spacer(),
            if (_isProcessing) _buildProcessingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Kangue',
            style: TextStyle(
              color: kTextColor, fontSize: 28,
              fontWeight: FontWeight.bold, letterSpacing: 1.5,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: kTextColor, size: 30),
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Paramètres',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isListening
                ? Colors.red.shade400
                : _isProcessing
                    ? kAccentColor
                    : kPrimaryColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusText,
                style: const TextStyle(color: Colors.white70, fontSize: kFontSizeMedium)),
            if (_lastCommand.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Vous : $_lastCommand',
                  style: const TextStyle(color: kAccentColor, fontSize: kFontSizeSmall)),
            ],
            if (_lastResponse.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Kangue : $_lastResponse',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: kFontSizeSmall)),
            ],
          ],
        ),
      ),
    );
  }

  /// Android-only: shows background service status + toggle
  Widget _buildAndroidBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Hands-free (always-on wake-word listening) toggle
          Expanded(
            child: _AndroidChip(
              icon: _handsFree ? Icons.record_voice_over : Icons.voice_over_off,
              label: _handsFree ? 'Mains libres ON' : 'Mains libres OFF',
              active: _handsFree,
              onTap: _toggleHandsFree,
            ),
          ),
          const SizedBox(width: 8),
          // Accessibility toggle
          Expanded(
            child: _AndroidChip(
              icon: _a11yEnabled ? Icons.accessibility_new : Icons.accessibility,
              label: _a11yEnabled ? 'Accessibilité ON' : 'Accessibilité OFF',
              active: _a11yEnabled,
              onTap: _showA11yDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    return Semantics(
      label: _isListening ? 'Arrêter l\'écoute' : 'Appuyer pour parler à Kangue',
      child: MicButton(isListening: _isListening, onTap: _toggleListening),
    );
  }

  Widget _buildGrid() {
    final androidExtra = Platform.isAndroid
        ? [
            AccessibleButton(
              icon: Icons.screen_search_desktop_rounded,
              label: 'Lire\nl\'écran',
              semanticLabel: 'Lire le contenu de l\'écran actuel',
              color: const Color(0xFF00695C),
              onTap: _readScreenContent,
            ),
          ]
        : <Widget>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          AccessibleButton(
            icon: Icons.document_scanner_rounded,
            label: 'Scanner\ndoc',
            semanticLabel: 'Scanner un document',
            color: const Color(0xFF2E7D32),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ScannerScreen()),
            ),
          ),
          ...androidExtra,
          AccessibleButton(
            icon: Icons.volume_up_rounded,
            label: 'Relire',
            semanticLabel: 'Relire la dernière réponse',
            color: const Color(0xFF1565C0),
            onTap: () => _tts.speak(_lastResponse.isNotEmpty
                ? _lastResponse
                : 'Aucune réponse à relire.'),
          ),
          AccessibleButton(
            icon: Icons.stop_circle_outlined,
            label: 'Arrêter\nvoix',
            semanticLabel: 'Arrêter la lecture vocale',
            color: const Color(0xFFC62828),
            onTap: () => _tts.stop(),
          ),
          AccessibleButton(
            icon: Icons.help_outline_rounded,
            label: 'Aide',
            semanticLabel: 'Obtenir de l\'aide',
            color: const Color(0xFF6A1B9A),
            onTap: () => _tts.speak(
              'Je suis Kangue, votre assistant vocal. Appuyez sur le grand bouton orange '
              'et parlez-moi. Par exemple : ouvre WhatsApp, quelle heure est-il, '
              'quel temps fait-il, ou lis-moi cet article.',
            ),
          ),
          AccessibleButton(
            icon: Icons.settings_rounded,
            label: 'Paramètres',
            semanticLabel: 'Ouvrir les paramètres',
            color: const Color(0xFF4E342E),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: kAccentColor),
          ),
          SizedBox(width: 10),
          Text('Kangue réfléchit...', style: TextStyle(color: kAccentColor, fontSize: 14)),
        ],
      ),
    );
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cmdSub?.cancel();
    _screenSub?.cancel();
    _tts.stop();
    _stt.stop();
    super.dispose();
  }
}

// ─── Small chip widget for Android status indicators ─────────────────────────

class _AndroidChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _AndroidChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? kAccentColor.withValues(alpha: 0.18)
              : kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? kAccentColor : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? kAccentColor : Colors.white38),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: active ? kAccentColor : Colors.white38,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
