import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../utils/constants.dart';
import '../widgets/accessible_button.dart';

enum _ScanState { idle, loading, success, error }

class ScannerScreen extends StatefulWidget {
  final bool autoCapture;
  const ScannerScreen({super.key, this.autoCapture = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _gemini = GeminiService();
  final _tts = TtsService();
  final _picker = ImagePicker();

  _ScanState _state = _ScanState.idle;
  String _resultText = '';
  String _errorMessage = '';
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    if (widget.autoCapture) {
      // Lancé depuis "décris ce qui est devant moi"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tts.speak('Prenez une photo de ce qui est devant vous.');
        _pickImage(ImageSource.camera);
      });
    } else {
      _tts.speak(
        'Écran scanner. Choisissez de prendre une photo ou d\'utiliser votre galerie.',
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _imageBytes = bytes;
        _state = _ScanState.loading;
        _resultText = '';
        _errorMessage = '';
      });

      await _tts.speak('Image reçue. Analyse en cours, veuillez patienter.');
      await _analyzeImage(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Impossible d\'accéder à la caméra ou à la galerie.';
      });
      await _tts.speak(_errorMessage);
    }
  }

  Future<void> _analyzeImage(Uint8List bytes) async {
    if (!_gemini.isInitialized) {
      _setError('Clé API manquante. Ajoutez votre clé Gemini dans le fichier .env.');
      return;
    }

    if (!_gemini.hasValidKeyFormat) {
      _setError(
        'Clé API invalide. Elle doit commencer par "gsk_". '
        'Obtenez-en une sur console.groq.com.',
      );
      return;
    }

    try {
      final result = await _gemini.readDocument(bytes);
      if (!mounted) return;
      setState(() {
        _resultText = result;
        _state = _ScanState.success;
      });
      await _tts.speak(result);
    } catch (e) {
      if (!mounted) return;
      final msg = _friendlyError(e.toString());
      _setError(msg);
    }
  }

  void _setError(String message) {
    setState(() {
      _state = _ScanState.error;
      _errorMessage = message;
    });
    _tts.speak(message);
  }

  String _friendlyError(String raw) {
    _rawError = raw; // sauvegarde pour affichage debug
    if (raw.contains('API_KEY') || raw.contains('403') || raw.contains('401') || raw.contains('API key')) {
      return 'Clé API refusée. Vérifiez votre clé sur aistudio.google.com.';
    }
    if (raw.contains('SocketException') || raw.contains('network') || raw.contains('connection') || raw.contains('NetworkError')) {
      return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
    }
    if (raw.contains('429') || raw.contains('quota') || raw.contains('RESOURCE_EXHAUSTED')) {
      return 'Quota API dépassé. Attendez quelques minutes et réessayez.';
    }
    if (raw.contains('Réponse vide')) {
      return 'Aucun contenu détecté dans l\'image. Prenez une photo plus nette.';
    }
    return 'Erreur d\'analyse.';
  }

  String _rawError = '';

  Future<void> _retry() async {
    if (_imageBytes == null) return;
    setState(() {
      _state = _ScanState.loading;
      _errorMessage = '';
    });
    await _tts.speak('Nouvelle tentative en cours.');
    await _analyzeImage(_imageBytes!);
  }

  void _reset() {
    setState(() {
      _state = _ScanState.idle;
      _imageBytes = null;
      _resultText = '';
      _errorMessage = '';
    });
    _tts.speak('Scanner réinitialisé. Prenez une nouvelle photo.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: const Text(
          'Scanner un document',
          style: TextStyle(color: kTextColor, fontSize: kFontSizeMedium),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextColor, size: 28),
          onPressed: () {
            _tts.stop();
            Navigator.pop(context);
          },
          tooltip: 'Retour',
        ),
        actions: [
          if (_state == _ScanState.success)
            IconButton(
              icon: const Icon(Icons.volume_up, color: kAccentColor, size: 28),
              onPressed: () => _tts.speak(_resultText),
              tooltip: 'Relire',
            ),
          if (_state != _ScanState.idle)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 28),
              onPressed: _reset,
              tooltip: 'Recommencer',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Boutons de capture (toujours visibles)
              if (_state == _ScanState.idle || _state == _ScanState.error)
                Row(
                  children: [
                    Expanded(
                      child: AccessibleButton(
                        icon: Icons.camera_alt_rounded,
                        label: 'Prendre\nphoto',
                        semanticLabel: 'Prendre une photo avec la caméra',
                        color: const Color(0xFF1565C0),
                        size: 80,
                        onTap: () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AccessibleButton(
                        icon: Icons.photo_library_rounded,
                        label: 'Depuis\ngalerie',
                        semanticLabel: 'Choisir une image depuis la galerie',
                        color: const Color(0xFF4A148C),
                        size: 80,
                        onTap: () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Prévisualisation image
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    semanticLabel: 'Image capturée',
                  ),
                ),

              const SizedBox(height: 16),

              // Corps principal selon l'état
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),

      floatingActionButton: _state == _ScanState.success
          ? FloatingActionButton.extended(
              onPressed: () => _tts.speak(_resultText),
              backgroundColor: kAccentColor,
              icon: const Icon(Icons.volume_up, color: Colors.white),
              label: const Text(
                'Relire',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: kFontSizeMedium,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ScanState.idle:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.document_scanner_outlined,
                size: 80,
                color: Colors.white24,
              ),
              const SizedBox(height: 16),
              const Text(
                'Prenez en photo un document,\nune lettre, ou un produit\npour que je le lise à voix haute.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: kFontSizeMedium,
                  height: 1.6,
                ),
              ),
            ],
          ),
        );

      case _ScanState.loading:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: kAccentColor,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              const Text(
                'Lecture du document en cours...',
                style: TextStyle(color: Colors.white70, fontSize: kFontSizeMedium),
              ),
              const SizedBox(height: 8),
              Text(
                'Gemini analyse votre image',
                style: TextStyle(color: Colors.white38, fontSize: kFontSizeSmall),
              ),
            ],
          ),
        );

      case _ScanState.error:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: kFontSizeMedium,
                  height: 1.5,
                ),
              ),
              if (_rawError.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Détail : ${_rawError.length > 200 ? _rawError.substring(0, 200) : _rawError}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_imageBytes != null)
                ElevatedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
            ],
          ),
        );

      case _ScanState.success:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade700),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.text_snippet, color: Colors.greenAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Contenu lu :',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: kFontSizeSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _resultText,
                  style: const TextStyle(
                    color: kTextColor,
                    fontSize: kFontSizeMedium,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
