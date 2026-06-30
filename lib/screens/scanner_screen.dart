import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../utils/constants.dart';
import '../widgets/accessible_button.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _gemini = GeminiService();
  final _tts = TtsService();
  final _picker = ImagePicker();

  bool _isLoading = false;
  String _resultText = '';
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _tts.speak(
      'Écran scanner. Choisissez de prendre une photo ou d\'utiliser votre galerie.',
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _isLoading = true;
      _resultText = '';
    });

    await _tts.speak('Image reçue. Analyse en cours...');

    final result = await _gemini.readDocument(bytes);

    setState(() {
      _resultText = result;
      _isLoading = false;
    });

    await _tts.speak(result);
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
          if (_resultText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.volume_up, color: kAccentColor, size: 28),
              onPressed: () => _tts.speak(_resultText),
              tooltip: 'Relire le texte',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Boutons de capture
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

              const SizedBox(height: 20),

              // Prévisualisation image
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    semanticLabel: 'Image capturée',
                  ),
                ),

              const SizedBox(height: 16),

              // Indicateur de chargement
              if (_isLoading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: kAccentColor),
                    SizedBox(height: 12),
                    Text(
                      'Lecture du document en cours...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: kFontSizeMedium,
                      ),
                    ),
                  ],
                ),

              // Résultat texte
              if (_resultText.isNotEmpty)
                Expanded(
                  child: Container(
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
                              Icon(
                                Icons.text_snippet,
                                color: Colors.greenAccent,
                                size: 20,
                              ),
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
                  ),
                ),

              if (!_isLoading && _resultText.isEmpty && _imageBytes == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
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
                  ),
                ),
            ],
          ),
        ),
      ),

      // Bouton relire en bas
      floatingActionButton: _resultText.isNotEmpty
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

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
