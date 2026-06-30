import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/gemini_service.dart';
import 'services/tts_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Chargement sécurisé du .env
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  GeminiService().init(apiKey);

  // Ces services peuvent ne pas être disponibles sur Linux/web
  try {
    await TtsService().init();
  } catch (_) {}
  try {
    await NotificationService().init();
  } catch (_) {}

  // Les permissions ne sont disponibles que sur mobile
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await _requestPermissions();
  }

  runApp(
    DevicePreview(
      enabled: kDebugMode,
      builder: (_) => const KangueApp(),
    ),
  );
}

Future<void> _requestPermissions() async {
  await [
    Permission.microphone,
    Permission.camera,
    Permission.notification,
    Permission.speech,
  ].request();
}

class KangueApp extends StatelessWidget {
  const KangueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kangue',
      debugShowCheckedModeBanner: false,
      locale: DevicePreview.locale(context),
      // DevicePreview.appBuilder injecte le device frame + les bonnes MediaQuery
      builder: DevicePreview.appBuilder,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: kPrimaryColor,
          secondary: kAccentColor,
          surface: kSurfaceColor,
        ),
        scaffoldBackgroundColor: kBackgroundColor,
        useMaterial3: true,
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: kTextColor, fontSize: kFontSizeMedium),
          bodyMedium: TextStyle(color: kTextColor, fontSize: kFontSizeSmall),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
