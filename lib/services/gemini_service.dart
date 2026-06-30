import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  late GenerativeModel _textModel;
  late GenerativeModel _visionModel;
  bool _initialized = false;

  void init(String apiKey) {
    _textModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(
        'Tu es Kangue, un assistant vocal bienveillant pour personnes malvoyantes. '
        'Réponds toujours de façon courte, claire et directe. '
        'Tu comprends le français et le wolof. '
        'Pour les commandes d\'application, identifie toujours le nom exact de l\'app. '
        'Ne jamais inclure de markdown dans tes réponses vocales.',
      ),
    );
    _visionModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  // Analyse une commande vocale et retourne un objet structuré
  Future<CommandIntent> parseVoiceCommand(String command) async {
    final prompt = '''
Analyse cette commande vocale d'un utilisateur malvoyant: "$command"

Réponds UNIQUEMENT avec un JSON valide (sans markdown, sans ```):
{
  "action": "open_app|read_text|make_call|send_message|get_time|get_battery|help|unknown",
  "target": "nom de l'app ou du contact ou null",
  "message": "message à envoyer ou null",
  "response": "réponse vocale courte à lire à l'utilisateur"
}

Exemples:
- "ouvre whatsapp" → action: open_app, target: whatsapp
- "appelle maman" → action: make_call, target: maman
- "quelle heure est-il" → action: get_time
- "wax ci wolof" (parle en wolof) → réponds en wolof si possible
''';

    try {
      final response = await _textModel.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      final jsonStr = _extractJson(text);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CommandIntent.fromJson(map);
    } catch (e) {
      return CommandIntent(
        action: 'unknown',
        response: 'Je n\'ai pas compris cette commande. Pouvez-vous répéter ?',
      );
    }
  }

  // Lit et décrit un document/image
  Future<String> readDocument(Uint8List imageBytes) async {
    final prompt = '''
Tu es un assistant pour personnes malvoyantes.
Analyse cette image et:
1. Si c'est un document/texte: lis TOUT le texte visible de façon claire et ordonnée
2. Si c'est une scène: décris ce que tu vois de façon utile
3. Si c'est un produit: donne le nom, la marque, les infos importantes

Sois précis et lis tout le contenu textuel. Parle en français sauf si le texte est dans une autre langue.
Ne mentionne pas que tu es une IA, parle directement du contenu.
''';

    try {
      final response = await _visionModel.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]);
      return response.text ?? 'Je n\'ai pas pu lire ce document.';
    } catch (e) {
      return 'Erreur lors de la lecture du document. Veuillez réessayer.';
    }
  }

  // Conversation générale
  Future<String> chat(String message) async {
    try {
      final response = await _textModel.generateContent([Content.text(message)]);
      return response.text ?? 'Je n\'ai pas de réponse pour le moment.';
    } catch (e) {
      return 'Une erreur s\'est produite. Veuillez réessayer.';
    }
  }

  String _extractJson(String text) {
    // Extrait le JSON même si Gemini ajoute du texte autour
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}

class CommandIntent {
  final String action;
  final String? target;
  final String? message;
  final String response;

  CommandIntent({
    required this.action,
    this.target,
    this.message,
    required this.response,
  });

  factory CommandIntent.fromJson(Map<String, dynamic> json) {
    return CommandIntent(
      action: json['action'] as String? ?? 'unknown',
      target: json['target'] as String?,
      message: json['message'] as String?,
      response: json['response'] as String? ?? 'Commande reçue.',
    );
  }
}
