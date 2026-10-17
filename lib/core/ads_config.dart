import 'package:flutter/foundation.dart';

/// Ads stay opt-in at build time until the publisher finishes AdMob setup.
class AdsConfig {
  static const enabled = bool.fromEnvironment('ADS_ENABLED');
  static const testMode =
      bool.fromEnvironment('ADS_TEST_MODE', defaultValue: true);

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  static String get bannerId => testMode
      ? (_ios
          ? 'ca-app-pub-3940256099942544/2934735716'
          : 'ca-app-pub-3940256099942544/6300978111')
      : (_ios
          ? const String.fromEnvironment('ADMOB_IOS_BANNER_ID')
          : const String.fromEnvironment('ADMOB_ANDROID_BANNER_ID'));
  static String get interstitialId => testMode
      ? (_ios
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712')
      : (_ios
          ? const String.fromEnvironment('ADMOB_IOS_INTERSTITIAL_ID')
          : const String.fromEnvironment('ADMOB_ANDROID_INTERSTITIAL_ID'));

  static bool get configured =>
      enabled &&
      supported &&
      (testMode ||
          [bannerId, interstitialId].every((id) =>
              RegExp(r'^ca-app-pub-\d{16}/\d{10}$').hasMatch(id) &&
              !id.startsWith('ca-app-pub-3940256099942544/')));
}
