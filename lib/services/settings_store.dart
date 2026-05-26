import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Settings store for persisting user preferences locally.
/// All values are stored in SharedPreferences.
class SettingsStore {
  static const String _keyShowIdNearby = 'show_id_nearby';
  static const String _keyShowOnline = 'show_online';
  static const String _keyAllowDm = 'allow_dm';
  static const String _keyAllowTag = 'allow_tag';
  static const String _keyNearbyEnabled = 'nearby_enabled';
  static const String _keyShareDistance = 'share_distance';
  static const String _keyKycVerified = 'kyc_verified';
  static const String _keyKycStatus = 'kyc_status';
  static const String _keySubscriptionActive = 'subscription_active';
  static const String _keyPayPerMinEnabled = 'pay_per_min_enabled';
  static const String _keyPayPerMinRate = 'pay_per_min_rate';
  static const String _keyWalletBalance = 'wallet_balance';
  static const String _keyReferralCode = 'referral_code';
  static const String _keyReferralEditCount = 'referral_edit_count';
  static const String _keyInstallReferrerChecked = 'install_referrer_checked';
  static const String _keyInstallReferrerApplied = 'install_referrer_applied';
  static const String _keyTheme = 'theme_mode';
  static const String _keyNotifications = 'notifications_enabled';
  static const String _keyLanguage = 'language_code';
  static const String _keyGuestModeEnabled = 'enable_guest_mode';
  static const String _keyEyeBlinkScrollEnabled = 'eye_blink_scroll_enabled';
  static const String _keyBlinkClosedThreshold = 'blink_closed_threshold';
  static const String _keyBlinkOpenThreshold = 'blink_open_threshold';
  static const String _keyBlinkDoubleWindowMs = 'blink_double_window_ms';
  static const String _keyBlinkCooldownMs = 'blink_cooldown_ms';
  static const String _keyBlinkBackgroundScan = 'blink_background_scan';
  static const String _keySubscriptionStatus = 'subscription_status';
  static const String _keyFeedActionSubscribe = 'feed_action_subscribe';

  static SettingsStore? _instance;
  static SharedPreferences? _prefs;

  SettingsStore._();

  static Future<SettingsStore> getInstance() async {
    if (_instance == null) {
      _prefs = await SharedPreferences.getInstance();
      _instance = SettingsStore._();
    }
    return _instance!;
  }

  /// Fetch settings from backend and cache them
  Future<void> fetchAndCacheSettings() async {
    try {
      final settings = await ApiService().getPublicSettings();
      if (settings.isNotEmpty) {
        if (settings['enable_guest_mode'] != null) {
          await _prefs?.setBool(
            _keyGuestModeEnabled,
            settings['enable_guest_mode'].toString() == '1',
          );
        }
        if (settings['pay_per_min_rate'] != null) {
          await _prefs?.setDouble(
            _keyPayPerMinRate,
            double.tryParse(settings['pay_per_min_rate'].toString()) ?? 0.0,
          );
        }
        if (settings['subscription_status'] != null) {
          await _prefs?.setString(
            _keySubscriptionStatus,
            settings['subscription_status'].toString(),
          );
        }
      }
    } catch (_) {}
  }

  Future<bool> getGuestModeEnabled() async {
    return _prefs?.getBool(_keyGuestModeEnabled) ?? true;
  }

  // ── Privacy & Visibility ────────────────────────────────────────────────

  Future<bool> getShowIdNearby() async {
    return _prefs?.getBool(_keyShowIdNearby) ?? true;
  }

  Future<void> setShowIdNearby(bool value) async {
    await _prefs?.setBool(_keyShowIdNearby, value);
  }

  Future<bool> getShowOnline() async {
    return _prefs?.getBool(_keyShowOnline) ?? true;
  }

  Future<void> setShowOnline(bool value) async {
    await _prefs?.setBool(_keyShowOnline, value);
  }

  Future<bool> getAllowDm() async {
    return _prefs?.getBool(_keyAllowDm) ?? true;
  }

  Future<void> setAllowDm(bool value) async {
    await _prefs?.setBool(_keyAllowDm, value);
  }

  Future<bool> getAllowTag() async {
    return _prefs?.getBool(_keyAllowTag) ?? true;
  }

  Future<void> setAllowTag(bool value) async {
    await _prefs?.setBool(_keyAllowTag, value);
  }

  // ── Discovery & Nearby ────────────────────────────────────────────────────

  Future<bool> getNearbyEnabled() async {
    return _prefs?.getBool(_keyNearbyEnabled) ?? true;
  }

  Future<void> setNearbyEnabled(bool value) async {
    await _prefs?.setBool(_keyNearbyEnabled, value);
  }

  Future<bool> getShareDistance() async {
    return _prefs?.getBool(_keyShareDistance) ?? false;
  }

  Future<void> setShareDistance(bool value) async {
    await _prefs?.setBool(_keyShareDistance, value);
  }

  // ── KYC Verification ──────────────────────────────────────────────────────

  Future<bool> getKycVerified() async {
    final bool storedFlag = _prefs?.getBool(_keyKycVerified) ?? false;
    final String status = await getKycStatus();
    return storedFlag || status == 'verified' || status == 'approved';
  }

  Future<void> setKycVerified(bool value) async {
    await _prefs?.setBool(_keyKycVerified, value);
  }

  /// Returns: 'not_submitted', 'pending', 'verified'
  Future<String> getKycStatus() async {
    return _prefs?.getString(_keyKycStatus) ?? 'not_submitted';
  }

  Future<void> setKycStatus(String status) async {
    await _prefs?.setString(_keyKycStatus, status);
    if (status == 'verified' || status == 'approved') {
      await setKycVerified(true);
    }
  }

  // ── Subscription ──────────────────────────────────────────────────────────

  Future<bool> getSubscriptionActive() async {
    return _prefs?.getBool(_keySubscriptionActive) ?? false;
  }

  Future<void> setSubscriptionActive(bool value) async {
    await _prefs?.setBool(_keySubscriptionActive, value);
  }

  /// Returns: 'active', 'inactive', 'disabled'
  Future<String> getSubscriptionStatus() async {
    return _prefs?.getString(_keySubscriptionStatus) ?? 'inactive';
  }

  Future<void> setSubscriptionStatus(String status) async {
    await _prefs?.setString(_keySubscriptionStatus, status);
  }

  Future<bool> getFeedActionSubscribe() async {
    return _prefs?.getBool(_keyFeedActionSubscribe) ?? false;
  }

  Future<void> setFeedActionSubscribe(bool value) async {
    await _prefs?.setBool(_keyFeedActionSubscribe, value);
  }

  // ── Pay Per Minute ────────────────────────────────────────────────────────

  Future<bool> getPayPerMinEnabled() async {
    return _prefs?.getBool(_keyPayPerMinEnabled) ?? false;
  }

  Future<void> setPayPerMinEnabled(bool value) async {
    await _prefs?.setBool(_keyPayPerMinEnabled, value);
  }

  Future<double> getPayPerMinRate() async {
    return _prefs?.getDouble(_keyPayPerMinRate) ?? 0.0;
  }

  Future<void> setPayPerMinRate(double value) async {
    await _prefs?.setDouble(_keyPayPerMinRate, value);
  }

  // ── Wallet ────────────────────────────────────────────────────────────────

  Future<double> getWalletBalance() async {
    return _prefs?.getDouble(_keyWalletBalance) ?? 0.0;
  }

  Future<void> setWalletBalance(double value) async {
    await _prefs?.setDouble(_keyWalletBalance, value);
  }

  Future<String> getReferralCode() async {
    var code = _prefs?.getString(_keyReferralCode);
    if (code == null || code.isEmpty) {
      code = _generateReferralCode();
      await setReferralCode(code);
    }
    return code;
  }

  Future<void> setReferralCode(String code) async {
    await _prefs?.setString(_keyReferralCode, code);
  }

  Future<int> getReferralEditCount() async {
    return _prefs?.getInt(_keyReferralEditCount) ?? 0;
  }

  Future<void> setReferralEditCount(int value) async {
    await _prefs?.setInt(_keyReferralEditCount, value);
  }

  Future<int> incrementReferralEditCount() async {
    final current = await getReferralEditCount();
    final next = current + 1;
    await setReferralEditCount(next);
    return next;
  }

  Future<bool> getInstallReferrerChecked() async {
    return _prefs?.getBool(_keyInstallReferrerChecked) ?? false;
  }

  Future<void> setInstallReferrerChecked(bool value) async {
    await _prefs?.setBool(_keyInstallReferrerChecked, value);
  }

  Future<bool> getInstallReferrerApplied() async {
    return _prefs?.getBool(_keyInstallReferrerApplied) ?? false;
  }

  Future<void> setInstallReferrerApplied(bool value) async {
    await _prefs?.setBool(_keyInstallReferrerApplied, value);
  }

  String _generateReferralCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── App Settings ──────────────────────────────────────────────────────────

  Future<bool> getNotificationsEnabled() async {
    return _prefs?.getBool(_keyNotifications) ?? true;
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefs?.setBool(_keyNotifications, value);
  }

  Future<String> getLanguageCode() async {
    return _prefs?.getString(_keyLanguage) ?? 'en';
  }

  Future<void> setLanguageCode(String code) async {
    await _prefs?.setString(_keyLanguage, code);
  }

  Future<String> getThemeMode() async {
    return _prefs?.getString(_keyTheme) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs?.setString(_keyTheme, mode);
  }

  // ── Accessibility: Eye-blink scroll ───────────────────────────────────────

  Future<bool> getEyeBlinkScrollEnabled() async {
    return _prefs?.getBool(_keyEyeBlinkScrollEnabled) ?? false;
  }

  Future<void> setEyeBlinkScrollEnabled(bool value) async {
    await _prefs?.setBool(_keyEyeBlinkScrollEnabled, value);
  }

  Future<double> getBlinkClosedThreshold() async {
    return _prefs?.getDouble(_keyBlinkClosedThreshold) ?? 0.35;
  }

  Future<void> setBlinkClosedThreshold(double value) async {
    await _prefs?.setDouble(_keyBlinkClosedThreshold, value);
  }

  Future<double> getBlinkOpenThreshold() async {
    return _prefs?.getDouble(_keyBlinkOpenThreshold) ?? 0.65;
  }

  Future<void> setBlinkOpenThreshold(double value) async {
    await _prefs?.setDouble(_keyBlinkOpenThreshold, value);
  }

  Future<int> getBlinkDoubleWindowMs() async {
    return _prefs?.getInt(_keyBlinkDoubleWindowMs) ?? 1000;
  }

  Future<void> setBlinkDoubleWindowMs(int value) async {
    await _prefs?.setInt(_keyBlinkDoubleWindowMs, value);
  }

  Future<int> getBlinkCooldownMs() async {
    return _prefs?.getInt(_keyBlinkCooldownMs) ?? 800;
  }

  Future<void> setBlinkCooldownMs(int value) async {
    await _prefs?.setInt(_keyBlinkCooldownMs, value);
  }

  Future<bool> getBlinkBackgroundScanEnabled() async {
    return _prefs?.getBool(_keyBlinkBackgroundScan) ?? false;
  }

  Future<void> setBlinkBackgroundScanEnabled(bool value) async {
    await _prefs?.setBool(_keyBlinkBackgroundScan, value);
  }

  // ── Blocked Users (placeholder) ───────────────────────────────────────────

  Future<List<String>> getBlockedUsers() async {
    return _prefs?.getStringList('blocked_users') ?? [];
  }

  Future<void> setBlockedUsers(List<String> users) async {
    await _prefs?.setStringList('blocked_users', users);
  }
}
