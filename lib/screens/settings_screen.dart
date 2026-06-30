import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tts_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tts = TtsService();
  double _speechRate = 0.45;
  String _selectedLanguage = 'Français';
  bool _readNotifications = true;
  bool _hapticFeedback = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speechRate = prefs.getDouble('speech_rate') ?? 0.45;
      _selectedLanguage = prefs.getString('language') ?? 'Français';
      _readNotifications = prefs.getBool('read_notifications') ?? true;
      _hapticFeedback = prefs.getBool('haptic_feedback') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setString('language', _selectedLanguage);
    await prefs.setBool('read_notifications', _readNotifications);
    await prefs.setBool('haptic_feedback', _hapticFeedback);

    final langCode =
        kSupportedLanguages[_selectedLanguage] ?? 'fr-FR';
    await _tts.setLanguage(langCode);
    await _tts.setRate(_speechRate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: const Text(
          'Paramètres',
          style: TextStyle(color: kTextColor, fontSize: kFontSizeMedium),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextColor, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Voix'),
          _buildSliderTile(
            label: 'Vitesse de lecture',
            value: _speechRate,
            min: 0.2,
            max: 1.0,
            divisions: 8,
            onChanged: (v) {
              setState(() => _speechRate = v);
              _tts.setRate(v);
            },
            semanticLabel: 'Ajuster la vitesse de lecture',
          ),
          _buildTestVoiceTile(),
          const SizedBox(height: 16),

          _buildSection('Langue'),
          ...kSupportedLanguages.keys.map(
            (lang) => _buildRadioTile(
              title: lang,
              value: lang,
              groupValue: _selectedLanguage,
              onChanged: (v) {
                setState(() => _selectedLanguage = v!);
                _saveSettings();
                _tts.speak('Langue changée en $v');
              },
            ),
          ),
          const SizedBox(height: 16),

          _buildSection('Notifications'),
          _buildSwitchTile(
            title: 'Lire les notifications à voix haute',
            subtitle: 'Kangue lira chaque notification reçue',
            value: _readNotifications,
            onChanged: (v) {
              setState(() => _readNotifications = v);
              _saveSettings();
            },
          ),
          const SizedBox(height: 16),

          _buildSection('Accessibilité'),
          _buildSwitchTile(
            title: 'Retour haptique (vibration)',
            subtitle: 'Vibrer légèrement lors des touches',
            value: _hapticFeedback,
            onChanged: (v) {
              setState(() => _hapticFeedback = v);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: kAccentColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String semanticLabel,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: kTextColor, fontSize: kFontSizeSmall),
          ),
          Semantics(
            label: semanticLabel,
            slider: true,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: kAccentColor,
                thumbColor: kAccentColor,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestVoiceTile() {
    return GestureDetector(
      onTap: () => _tts.speak(
        'Bonjour ! Ceci est un test de la voix de Kangue.',
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimaryColor.withValues(alpha: 0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.play_circle_outline, color: kAccentColor, size: 28),
            SizedBox(width: 12),
            Text(
              'Tester la voix',
              style: TextStyle(color: kTextColor, fontSize: kFontSizeSmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(color: kTextColor, fontSize: kFontSizeSmall),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: kAccentColor, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? kAccentColor : Colors.white54,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: kTextColor,
                fontSize: kFontSizeSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
