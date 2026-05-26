import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';

class InstallReferrerService {
  static const MethodChannel _channel = MethodChannel(
    'love_vibe/install_referrer',
  );

  final WalletService _walletService;

  InstallReferrerService({WalletService? walletService})
    : _walletService = walletService ?? WalletService();

  Future<void> processInstallReferrerOnce() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final settings = await SettingsStore.getInstance();
    final alreadyChecked = await settings.getInstallReferrerChecked();
    if (alreadyChecked) {
      await _walletService.applyPendingInstallReferralIfAny();
      return;
    }

    try {
      final dynamic raw = await _channel.invokeMethod('getInstallReferrer');
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final referrer = (map['referrer'] ?? '').toString();

      final code = _extractReferralCode(referrer);
      if (code != null && code.isNotEmpty) {
        await _walletService.setPendingInstallReferralCode(code);
        final result = await _walletService.applyReferralCode(
          referralCode: code,
          source: 'install_referrer',
        );

        if (result.success) {
          await settings.setInstallReferrerApplied(true);
          await _walletService.clearPendingInstallReferralCode();
        }
      }
    } catch (_) {
      // Keep silent; we still mark checked to ensure one-time behavior.
    } finally {
      await settings.setInstallReferrerChecked(true);
    }

    await _walletService.applyPendingInstallReferralIfAny();
  }

  String? _extractReferralCode(String rawReferrer) {
    final trimmed = rawReferrer.trim();
    if (trimmed.isEmpty) return null;

    String? candidate;

    if (trimmed.contains('=')) {
      try {
        final params = Uri.splitQueryString(trimmed);
        candidate = params['ref'] ?? params['referral_code'] ?? params['code'];

        if (candidate == null || candidate.isEmpty) {
          final value = params['referrer'];
          if (value != null && value.startsWith('ref_') && value.length > 4) {
            candidate = value.substring(4);
          }
        }
      } catch (_) {
        candidate = null;
      }
    }

    candidate ??= trimmed.startsWith('ref_') ? trimmed.substring(4) : trimmed;

    if (candidate.trim().isEmpty) return null;
    return candidate.trim().toUpperCase();
  }
}
