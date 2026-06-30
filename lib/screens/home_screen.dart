import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/app_launcher_service.dart';
import '../utils/constants.dart';
import '../widgets/accessible_button.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tts = TtsService();
  final _stt = SttService();
  final _gemini = GeminiService();
  final _launcher = AppLauncherService();

  bool _isListening = false;
  bool _isProcessing = false;
  String _statusText = 'Appuyez sur le micro pour parler';
  String _lastCommand = '';
  String _lastResponse = '';

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _stt.init();
    await Future.delayed(const Duration(milliseconds: 500));
    await _tts.speak(
      'Bonjour ! Je suis Kangue, votre assistant. '
      'Appuyez sur le grand bouton orange pour me parler.',
    );
  }

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

    await _stt.listen(
      localeId: 'fr_FR',
      onListenStart: () {
        setState(() => _isListening = true);
      },
      onResult: (text) async {
        if (text.isEmpty) {
          setState(() {
            _isListening = false;
            _statusText = 'Rien entendu. Réessayez.';
          });
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

    final intent = await _gemini.parseVoiceCommand(command);

    await _executeIntent(intent);

    setState(() {
      _isProcessing = false;
      _lastResponse = intent.response;
      _statusText = 'Appuyez sur le micro pour parler';
    });
  }

  Future<void> _executeIntent(CommandIntent intent) async {
    switch (intent.action) {
      case 'open_app':
        await _tts.speak(intent.response);
        if (intent.target != null) {
          final success = await _launcher.launchByName(intent.target!);
          if (!success) {
            await _tts.speak(
              'Je n\'ai pas trouvé l\'application ${intent.target}.',
            );
          }
        }

      case 'get_time':
        final now = DateTime.now();
        final timeStr =
            'Il est ${now.hour}h${now.minute.toString().padLeft(2, '0')}.';
        await _tts.speak(timeStr);
        setState(() => _lastResponse = timeStr);

      case 'make_call':
        await _tts.speak(intent.response);

      case 'help':
        const helpText =
            'Vous pouvez me dire : ouvre WhatsApp, quelle heure est-il, '
            'scanner un document, ou me poser n\'importe quelle question.';
        await _tts.speak(helpText);
        setState(() => _lastResponse = helpText);

      default:
        await _tts.speak(intent.response);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kangue',
                    style: TextStyle(
                      color: kTextColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: kTextColor, size: 30),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                    tooltip: 'Paramètres',
                  ),
                ],
              ),
            ),

            // Status card
            Padding(
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
                    Text(
                      _statusText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: kFontSizeMedium,
                      ),
                    ),
                    if (_lastCommand.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Vous : $_lastCommand',
                        style: const TextStyle(
                          color: kAccentColor,
                          fontSize: kFontSizeSmall,
                        ),
                      ),
                    ],
                    if (_lastResponse.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Kangue : $_lastResponse',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: kFontSizeSmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Bouton micro principal
            Semantics(
              label: _isListening
                  ? 'Arrêter l\'écoute'
                  : 'Appuyer pour parler à Kangue',
              child: MicButton(
                isListening: _isListening,
                onTap: _toggleListening,
              ),
            ),

            const SizedBox(height: 12),
            Text(
              _isListening ? 'Parlez maintenant...' : 'Parler',
              style: TextStyle(
                color: _isListening ? Colors.red.shade300 : Colors.white54,
                fontSize: kFontSizeSmall,
              ),
            ),

            const SizedBox(height: 36),

            // Boutons de fonctionnalités
            Padding(
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
                      context,
                      MaterialPageRoute(builder: (_) => const ScannerScreen()),
                    ),
                  ),
                  AccessibleButton(
                    icon: Icons.notifications_active_rounded,
                    label: 'Notif\nactives',
                    semanticLabel: 'Voir les notifications actives',
                    color: const Color(0xFF6A1B9A),
                    onTap: () => _tts.speak(
                      'Fonctionnalité de notifications. '
                      'Activez les permissions de notification dans les paramètres.',
                    ),
                  ),
                  AccessibleButton(
                    icon: Icons.help_outline_rounded,
                    label: 'Aide',
                    semanticLabel: 'Obtenir de l aide',
                    color: const Color(0xFF00695C),
                    onTap: () => _tts.speak(
                      'Je suis Kangue, votre assistant vocal. '
                      'Appuyez sur le grand bouton orange et parlez-moi. '
                      'Par exemple : ouvre WhatsApp, quelle heure est-il, '
                      'ou scanner un document.',
                    ),
                  ),
                  AccessibleButton(
                    icon: Icons.volume_up_rounded,
                    label: 'Lire\nécran',
                    semanticLabel: 'Lire le contenu de l écran',
                    color: const Color(0xFF1565C0),
                    onTap: () => _tts.speak(_lastResponse.isNotEmpty
                        ? _lastResponse
                        : 'Aucun contenu à lire pour le moment.'),
                  ),
                  AccessibleButton(
                    icon: Icons.stop_circle_outlined,
                    label: 'Arrêter\nvoix',
                    semanticLabel: 'Arrêter la lecture vocale',
                    color: const Color(0xFFC62828),
                    onTap: () => _tts.stop(),
                  ),
                  AccessibleButton(
                    icon: Icons.settings_rounded,
                    label: 'Paramètres',
                    semanticLabel: 'Ouvrir les paramètres',
                    color: const Color(0xFF4E342E),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Indicateur de traitement
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAccentColor,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Kangue réfléchit...',
                      style: TextStyle(color: kAccentColor, fontSize: 14),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }
}
