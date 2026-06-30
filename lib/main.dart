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

  await dotenv.load(fileName: '.env');
  final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  GeminiService().init(apiKey);
  await TtsService().init();
  await NotificationService().init();

  await _requestPermissions();

  runApp(const KangueApp());
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(1.0, 1.4),
            ),
          ),
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}
