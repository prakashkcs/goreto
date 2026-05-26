import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:love_vibe_pro/config/ad_config.dart';
import 'package:love_vibe_pro/config/app_env.dart';

class AdSettings {
  final bool adsEnabled;
  final AdDensity density;
  final int feedFrequency;
  final int interstitialFrequency;
  final String? bannerAdUnitId;
  final String? interstitialAdUnitId;

  const AdSettings({
    this.adsEnabled = true,
    this.density = AdDensity.balanced,
    this.feedFrequency = 5,
    this.interstitialFrequency = 5,
    this.bannerAdUnitId,
    this.interstitialAdUnitId,
  });

  factory AdSettings.fromJson(Map<String, dynamic> j) {
    final d = j['density']?.toString() ?? 'balanced';
    return AdSettings(
      adsEnabled: (j['ads_enabled'] ?? '1').toString() == '1',
      density: d == 'maximize'
          ? AdDensity.maximize
          : d == 'minimize'
              ? AdDensity.minimize
              : AdDensity.balanced,
      feedFrequency:
          int.tryParse(j['feed_frequency']?.toString() ?? '') ?? 5,
      interstitialFrequency:
          int.tryParse(j['interstitial_frequency']?.toString() ?? '') ?? 5,
      bannerAdUnitId: j['banner_ad_unit_id']?.toString(),
      interstitialAdUnitId: j['interstitial_ad_unit_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ads_enabled': adsEnabled ? '1' : '0',
        'density': density.name,
        'feed_frequency': feedFrequency,
        'interstitial_frequency': interstitialFrequency,
        'banner_ad_unit_id': bannerAdUnitId ?? '',
        'interstitial_ad_unit_id': interstitialAdUnitId ?? '',
      };
}

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  AdSettings _settings = const AdSettings();
  AdSettings get settings => _settings;

  InterstitialAd? _interstitialAd;
  bool _interstitialLoading = false;
  int _navCount = 0;
  bool _initialized = false;

  static const String _cacheKey = 'cached_ad_settings';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    await _loadCached();
    _fetchRemote(); // fire-and-forget
    _preloadInterstitial();
  }

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        _settings = AdSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _fetchRemote() async {
    try {
      final baseUrl = await AppEnv.getBaseUrlAsync();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get(
        '${baseUrl}ads_config.php',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic data = res.data;
      if (data is String) data = jsonDecode(data);
      if (data is Map && data['status'] == 'success') {
        final newSettings = AdSettings.fromJson(
            Map<String, dynamic>.from(data['settings'] as Map));
        _settings = newSettings;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(newSettings.toJson()));
        if (!_settings.adsEnabled) {
          _interstitialAd?.dispose();
          _interstitialAd = null;
        } else {
          _preloadInterstitial();
        }
      }
    } catch (_) {}
  }

  String get _effectiveBannerId =>
      (_settings.bannerAdUnitId?.isNotEmpty == true)
          ? _settings.bannerAdUnitId!
          : AdConfig.bannerAdUnitId;

  String get _effectiveInterstitialId =>
      (_settings.interstitialAdUnitId?.isNotEmpty == true)
          ? _settings.interstitialAdUnitId!
          : AdConfig.interstitialAdUnitId;

  // ── Banner ────────────────────────────────────────────────────────────────

  BannerAd createBannerAd({BannerAdListener? listener}) {
    final ad = BannerAd(
      adUnitId: _effectiveBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: listener ??
          BannerAdListener(
            onAdFailedToLoad: (ad, err) {
              ad.dispose();
              if (kDebugMode) print('Banner failed: ${err.message}');
            },
          ),
    );
    return ad;
  }

  // ── Interstitial ─────────────────────────────────────────────────────────

  void _preloadInterstitial() {
    if (_interstitialLoading || _interstitialAd != null) return;
    if (!_settings.adsEnabled) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _effectiveInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialLoading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (err) {
          _interstitialLoading = false;
          if (kDebugMode) print('Interstitial load failed: ${err.message}');
        },
      ),
    );
  }

  /// Call on each significant screen navigation to trigger interstitials.
  void trackNavigation() {
    if (!_settings.adsEnabled) return;
    _navCount++;
    if (_navCount >= _settings.interstitialFrequency) {
      _navCount = 0;
      showInterstitialIfReady();
    }
  }

  void showInterstitialIfReady() {
    if (_interstitialAd != null && _settings.adsEnabled) {
      _interstitialAd!.show();
    }
  }
}
