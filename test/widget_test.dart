import 'package:flutter_test/flutter_test.dart';
import 'package:kangue_app/utils/constants.dart';

void main() {
  test('Known apps dictionary is not empty', () {
    expect(kKnownApps.isNotEmpty, true);
    expect(kKnownApps.containsKey('whatsapp'), true);
  });

  test('Supported languages contain French', () {
    expect(kSupportedLanguages.containsKey('Français'), true);
    expect(kSupportedLanguages['Français'], 'fr-FR');
  });
}
