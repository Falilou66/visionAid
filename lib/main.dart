import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/gemini_service.dart';
import 'services/tts_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
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

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
  GeminiService().init(apiKey);

  // Store API key in SharedPreferences for the native background service
  await BackgroundService().init(apiKey);

  try {
    await TtsService().init();
  } catch (_) {}
  try {
    await NotificationService().init();
  } catch (_) {}

  runApp(const KangueApp());
}

class KangueApp extends StatelessWidget {
  const KangueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kangue',
      debugShowCheckedModeBanner: false,
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
