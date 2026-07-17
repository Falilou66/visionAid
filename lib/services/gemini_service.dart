import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _textModel = 'llama-3.3-70b-versatile';
  static const _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  String _apiKey = '';
  bool _initialized = false;

  void init(String apiKey) {
    _apiKey = apiKey;
    _initialized = apiKey.isNotEmpty;
  }

  bool get isInitialized => _initialized;
  bool get hasValidKeyFormat => _apiKey.startsWith('gsk_') && _apiKey.length > 20;

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Groq ${response.statusCode}: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractContent(Map<String, dynamic> response) {
    return (response['choices'] as List).first['message']['content'] as String;
  }

  Future<CommandIntent> parseVoiceCommand(String command) async {
    const systemPrompt =
        'Tu es Kangue, un assistant vocal pour personnes malvoyantes, comme Siri mais meilleur. '
        'Tu comprends le français, le wolof, et le mélange des deux. '
        'Réponds UNIQUEMENT en JSON valide, sans markdown, sans explication.';

    final userPrompt = '''
Analyse cette commande vocale: "$command"

Réponds UNIQUEMENT avec ce JSON:
{
  "action": "open_app|send_message|make_call|get_time|get_weather|answer_question|describe_surroundings|scan_document|set_reminder|calculate|translate|get_battery|help|read_screen|unknown",
  "app": "nom de l'application à ouvrir (ex: whatsapp, tiktok, messenger, instagram, youtube, snapchat, spotify…) ou null",
  "target": "destinataire, contact, ou sujet principal ou null",
  "message": "texte du message ou null",
  "query": "question ou calcul ou texte à traduire ou null",
  "lang": "langue cible pour traduction ou null",
  "response": "réponse vocale courte en français (ou wolof si demandé)"
}

Règles:
- Pour toute question générale (météo, actualités, définitions, histoire, maths…) → action: answer_question, query: la question
- Pour "traduis X en anglais" → action: translate, query: X, lang: english
- Pour "quelle heure" → action: get_time
- Pour "météo" ou "temps qu'il fait" → action: get_weather
- Pour "décris ce que tu vois" ou "qu'est-ce qu'il y a devant moi" → action: describe_surroundings
- Pour "scanne un document", "scanne ce papier", "lis ce document", "scanne ma facture" → action: scan_document
- Pour "ouvre X", "lance X", "démarre X" (où X est une application: tiktok, whatsapp, messenger, instagram…) → action: open_app, app: X
- Pour "rappelle-moi de X" ou "alarme à X heures" → action: set_reminder, query: le rappel
- Pour calcul → action: calculate, query: le calcul
- Pour "lis-moi cet article", "lis l'écran", "que dit l'écran", "lis ce texte", "lis ce que tu vois sur l'écran" → action: read_screen
- Pour appel → action: make_call, target: nom du contact
- Pour message → action: send_message, app: l app, target: destinataire, message: contenu
- Pour ouvrir app → action: open_app, app: nom de l app

Exemples:
- "c'est quoi la capitale du Sénégal" → action:answer_question, query:"capitale du Sénégal"
- "combien font 25 fois 48" → action:calculate, query:"25 fois 48"
- "traduis bonjour en wolof" → action:translate, query:"bonjour", lang:"wolof"
- "appelle maman" → action:make_call, target:"maman"
- "dis à Cheikh sur whatsapp envoie-moi le cours" → action:send_message, app:"whatsapp", target:"Cheikh", message:"Envoie-moi le cours d hier"
- "quel temps fait-il" → action:get_weather
- "décris ce qu'il y a devant moi" → action:describe_surroundings
- "ouvre TikTok" → action:open_app, app:"tiktok"
- "lance Messenger" → action:open_app, app:"messenger"
- "scanne ce document" → action:scan_document
''';

    try {
      final response = await _post({
        'model': _textModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.1,
      });

      final text = _extractContent(response);
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1) throw Exception('JSON invalide');
      final map = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      return CommandIntent.fromJson(map);
    } catch (_) {
      return CommandIntent(
        action: 'unknown',
        response: 'Je n\'ai pas compris. Pouvez-vous répéter ?',
      );
    }
  }

  // Répond à une question générale
  Future<String> answerQuestion(String question) async {
    try {
      final response = await _post({
        'model': _textModel,
        'messages': [
          {
            'role': 'system',
            'content':
                'Tu es Kangue, un assistant vocal pour malvoyants. '
                'Réponds de façon courte et claire, en 1 à 3 phrases maximum. '
                'Pas de markdown, pas de listes, juste du texte fluide à lire à voix haute. '
                'Tu parles français et wolof.',
          },
          {'role': 'user', 'content': question},
        ],
        'temperature': 0.3,
      });
      return _extractContent(response);
    } catch (_) {
      return 'Je n\'ai pas pu répondre à cette question. Réessayez.';
    }
  }

  // Récupère la météo
  Future<String> getWeather() async {
    try {
      final res = await http
          .get(Uri.parse('https://wttr.in/?format=3&lang=fr'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final raw = res.body.trim();
        return _cleanWeatherText(raw);
      }
    } catch (_) {}
    return 'Impossible de récupérer la météo. Vérifiez votre connexion.';
  }

  String _cleanWeatherText(String text) {
    // Supprime les emojis pour une lecture TTS propre
    final emojiPattern = RegExp(
      r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
      unicode: true,
    );
    final cleaned = text.replaceAll(emojiPattern, '').replaceAll('  ', ' ').trim();
    // Reformule en phrase
    // Format wttr: "Ville, Region, Pays: Condition +T°C"
    final parts = cleaned.split(':');
    if (parts.length >= 2) {
      final location = parts[0].trim().split(',').first.trim();
      final condition = parts[1].trim();
      return 'À $location, $condition.';
    }
    return cleaned;
  }

  // Traduit un texte
  Future<String> translate(String text, String targetLang) async {
    try {
      final response = await _post({
        'model': _textModel,
        'messages': [
          {
            'role': 'system',
            'content': 'Tu es un traducteur. Traduis uniquement le texte donné, sans explication.',
          },
          {'role': 'user', 'content': 'Traduis en $targetLang: $text'},
        ],
        'temperature': 0.1,
      });
      return _extractContent(response);
    } catch (_) {
      return 'Je n\'ai pas pu traduire ce texte.';
    }
  }

  // Lit et décrit un document/image — lève une exception en cas d'erreur
  Future<String> readDocument(Uint8List imageBytes) async {
    if (!_initialized) throw Exception('API non initialisée');

    const prompt =
        'Tu es un assistant pour personnes malvoyantes. '
        'Analyse cette image et:\n'
        '1. Si c\'est un document ou du texte: lis TOUT le texte visible, clairement et dans l\'ordre.\n'
        '2. Si c\'est une scène ou un environnement: décris précisément ce que tu vois (personnes, objets, lieux, couleurs, distances).\n'
        '3. Si c\'est un produit: donne le nom, la marque, les infos importantes (prix, date, ingrédients).\n'
        'Sois très précis et détaillé. Parle en français. Ne mentionne pas que tu es une IA.';

    final base64Image = base64Encode(imageBytes);

    final response = await _post({
      'model': _visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
            },
          ],
        },
      ],
      'temperature': 0.1,
    });

    final text = _extractContent(response).trim();
    if (text.isEmpty) throw Exception('Réponse vide');
    return text;
  }

  Future<String> chat(String message) async {
    try {
      final response = await _post({
        'model': _textModel,
        'messages': [
          {
            'role': 'system',
            'content':
                'Tu es Kangue, assistant vocal pour malvoyants. '
                'Réponds de façon courte, claire, sans markdown.',
          },
          {'role': 'user', 'content': message},
        ],
      });
      return _extractContent(response);
    } catch (_) {
      return 'Une erreur s\'est produite. Veuillez réessayer.';
    }
  }
}

class CommandIntent {
  final String action;
  final String? app;
  final String? target;
  final String? message;
  final String? query;
  final String? lang;
  final String response;

  CommandIntent({
    required this.action,
    this.app,
    this.target,
    this.message,
    this.query,
    this.lang,
    required this.response,
  });

  factory CommandIntent.fromJson(Map<String, dynamic> json) {
    return CommandIntent(
      action: json['action'] as String? ?? 'unknown',
      app: json['app'] as String?,
      target: json['target'] as String?,
      message: json['message'] as String?,
      query: json['query'] as String?,
      lang: json['lang'] as String?,
      response: json['response'] as String? ?? 'Commande reçue.',
    );
  }
}
