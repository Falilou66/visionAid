import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../utils/constants.dart';

class AppLauncherService {
  static final AppLauncherService _instance = AppLauncherService._internal();
  factory AppLauncherService() => _instance;
  AppLauncherService._internal();

  // Lance une app à partir de son nom (en langage naturel)
  Future<bool> launchByName(String appName) async {
    final normalized = appName.toLowerCase().trim();

    // Cherche dans le dictionnaire des apps connues
    String? packageName;
    for (final entry in kKnownApps.entries) {
      if (normalized.contains(entry.key)) {
        packageName = entry.value;
        break;
      }
    }

    if (packageName == null) return false;

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Lance un appel téléphonique
  Future<bool> makeCall(String number) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:$number',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Ouvre l'app dialer avec un numéro pré-rempli
  Future<void> dialNumber(String number) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.DIAL',
      data: 'tel:$number',
    );
    await intent.launch();
  }

  // Ouvre les paramètres
  Future<void> openSettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.SETTINGS',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }
}
