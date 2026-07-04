import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';

class AppLauncherService {
  static final AppLauncherService _instance = AppLauncherService._internal();
  factory AppLauncherService() => _instance;
  AppLauncherService._internal();

  // Ouvre une app par son nom
  Future<bool> launchByName(String appName) async {
    final normalized = appName.toLowerCase().trim();

    if (Platform.isIOS) {
      final url = _iosUrlForApp(normalized);
      if (url == null) return false;
      return _launch(url);
    }

    // Android
    String? packageName;
    for (final entry in kKnownApps.entries) {
      if (normalized.contains(entry.key)) {
        packageName = entry.value;
        break;
      }
    }
    if (packageName == null) return false;
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Envoie un message — ouvre l'app avec le message pré-rempli
  // Sur iOS on ne peut pas sélectionner le contact automatiquement,
  // donc on ouvre l'app avec le message ; l'utilisateur choisit le contact.
  Future<bool> sendMessage({
    required String app,
    required String? recipientName,
    required String message,
  }) async {
    final appNorm = app.toLowerCase();
    final encoded = Uri.encodeComponent(message);

    if (appNorm.contains('whatsapp')) {
      // Avec numéro si possible, sinon message pré-rempli sans destinataire
      return _launch('whatsapp://send?text=$encoded');
    }
    if (appNorm.contains('telegram') || appNorm.contains('tg')) {
      return _launch('tg://msg?text=$encoded');
    }
    if (appNorm.contains('sms') || appNorm.contains('message')) {
      return _launch('sms:?&body=$encoded');
    }
    return false;
  }

  // Passe un appel — ouvre le composeur iOS avec le nom
  // iOS reconnaît les noms des contacts dans le composeur
  Future<bool> makeCall(String contactName) async {
    // Sur iOS, on ne peut pas passer un appel par nom directement.
    // On ouvre le composeur — l'utilisateur n'a qu'à appuyer sur appel.
    return _launch('tel://');
  }

  // Ouvre l'app Rappels iOS
  Future<void> openReminder(String reminderText) async {
    await _launch('x-apple-reminderkit://');
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String? _iosUrlForApp(String name) {
    const urls = {
      'whatsapp': 'whatsapp://',
      'telegram': 'tg://',
      'instagram': 'instagram://',
      'twitter': 'twitter://',
      'facebook': 'fb://',
      'youtube': 'youtube://',
      'gmail': 'googlegmail://co',
      'maps': 'https://maps.apple.com/',
      'paramètres': 'app-settings:',
      'settings': 'app-settings:',
      'téléphone': 'tel://',
      'musique': 'music://',
      'safari': 'https://www.google.com',
    };
    for (final entry in urls.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return null;
  }

  Future<bool> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri);
      return launched;
    } catch (_) {
      return false;
    }
  }
}
