import 'dart:io';

enum AdDensity { maximize, balanced, minimize }

class AdConfig {
  // ── Test IDs (Google official — safe to commit) ──────────────────────────
  static const String _testAndroidBannerId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testAndroidInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testIosBannerId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testIosInterstitialId =
      'ca-app-pub-3940256099942544/4411468910';

  // ── Production IDs (replace after AdMob account approval) ───────────────
  static const String _prodAndroidBannerId =
      'ca-app-pub-REPLACE_WITH_YOUR_ID/BANNER_UNIT';
  static const String _prodAndroidInterstitialId =
      'ca-app-pub-REPLACE_WITH_YOUR_ID/INTERSTITIAL_UNIT';
  static const String _prodIosBannerId =
      'ca-app-pub-REPLACE_WITH_YOUR_ID/IOS_BANNER_UNIT';
  static const String _prodIosInterstitialId =
      'ca-app-pub-REPLACE_WITH_YOUR_ID/IOS_INTERSTITIAL_UNIT';

  // Test App IDs (AndroidManifest / Info.plist use these until you have real ones)
  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';

  // ── Set false and fill prod IDs above before release ────────────────────
  static const bool useTestAds = true;

  static String get bannerAdUnitId => useTestAds
      ? (Platform.isIOS ? _testIosBannerId : _testAndroidBannerId)
      : (Platform.isIOS ? _prodIosBannerId : _prodAndroidBannerId);

  static String get interstitialAdUnitId => useTestAds
      ? (Platform.isIOS ? _testIosInterstitialId : _testAndroidInterstitialId)
      : (Platform.isIOS ? _prodIosInterstitialId : _prodAndroidInterstitialId);

  // ── Default frequency per density mode ──────────────────────────────────
  static int feedAdFrequency(AdDensity density) {
    switch (density) {
      case AdDensity.maximize:
        return 3;
      case AdDensity.balanced:
        return 5;
      case AdDensity.minimize:
        return 10;
    }
  }

  static int interstitialFrequency(AdDensity density) {
    switch (density) {
      case AdDensity.maximize:
        return 2;
      case AdDensity.balanced:
        return 5;
      case AdDensity.minimize:
        return 10;
    }
  }
}
