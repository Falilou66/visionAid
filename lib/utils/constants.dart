import 'package:flutter/material.dart';

const kPrimaryColor = Color(0xFF1565C0);
const kAccentColor = Color(0xFFFFA000);
const kBackgroundColor = Color(0xFF0D0D0D);
const kSurfaceColor = Color(0xFF1A1A1A);
const kTextColor = Color(0xFFFFFFFF);
const kButtonSize = 90.0;
const kFontSizeLarge = 22.0;
const kFontSizeMedium = 18.0;
const kFontSizeSmall = 14.0;

const kSupportedLanguages = {
  'Français': 'fr-FR',
  'Wolof': 'fr-FR',
  'English': 'en-US',
};

// Map nom parlé -> package. `launchByName` fait un `contains`, donc les alias
// (« messenger », « facebook messenger »…) pointent vers le même package.
// NB: en dernier recours, si le package n'est pas trouvé, `launchByName`
// tente une résolution par libellé via le PackageManager (voir le service).
const kKnownApps = {
  'whatsapp': 'com.whatsapp',
  'messenger': 'com.facebook.orca',
  'facebook messenger': 'com.facebook.orca',
  'facebook': 'com.facebook.katana',
  'chrome': 'com.android.chrome',
  'appareil photo': 'com.android.camera2',
  'camera': 'com.android.camera2',
  'paramètres': 'com.android.settings',
  'settings': 'com.android.settings',
  'youtube': 'com.google.android.youtube',
  'maps': 'com.google.android.apps.maps',
  'gmail': 'com.google.android.gm',
  'téléphone': 'com.android.dialer',
  'messages': 'com.google.android.apps.messaging',
  'sms': 'com.google.android.apps.messaging',
  'musique': 'com.google.android.music',
  'play store': 'com.android.vending',
  'instagram': 'com.instagram.android',
  'twitter': 'com.twitter.android',
  'telegram': 'org.telegram.messenger',
  'tiktok': 'com.zhiliaoapp.musically',
  'tik tok': 'com.zhiliaoapp.musically',
  'snapchat': 'com.snapchat.android',
  'snap': 'com.snapchat.android',
  'spotify': 'com.spotify.music',
  'netflix': 'com.netflix.mediaclient',
  'linkedin': 'com.linkedin.android',
  'photos': 'com.google.android.apps.photos',
  'contacts': 'com.android.contacts',
  'horloge': 'com.google.android.deskclock',
  'calendrier': 'com.google.android.calendar',
  'zoom': 'us.zoom.videomeetings',
  'google': 'com.google.android.googlequicksearchbox',
};
