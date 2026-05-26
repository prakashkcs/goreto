import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/models/kyc_models.dart';
import 'package:love_vibe_pro/screens/settings/kyc_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/settings_store.dart';

class KycStatusController extends ChangeNotifier {
  static final KycStatusController instance = KycStatusController._();
  KycStatusController._();

  static const String _cacheKey = 'kyc_status_cached_json';

  KycStatusModel _status = KycStatusModel.empty;
  bool _initialized = false;
  bool _loading = false;

  KycStatusModel get status => _status;
  bool get initialized => _initialized;
  bool get loading => _loading;
  bool get basicApproved => _status.basicApproved;
  bool get fullApproved => _status.fullApproved;

  Future<void> init({bool refresh = false}) async {
    if (!_initialized) {
      await _loadCached();
      _initialized = true;
      notifyListeners();
    }

    if (refresh) {
      await refreshFromServer();
    }
  }

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _status = KycStatusModel.fromJson(decoded);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_status.toJson()));
    } catch (_) {}
  }

  Future<void> refreshFromServer() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      final remote = await ApiService().getKycStatusRemote();
      
      _status = remote;
      await _persist();
      
      // Sync with SettingsStore (which many older screens rely on)
      final store = await SettingsStore.getInstance();
      await store.setKycStatus(remote.basicStatus);
      
    } catch (e) {
      // keep cached value on network/API failure
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> ensureBasicApproved(BuildContext context) async {
    await init(refresh: true);
    if (basicApproved) return true;
    return _showRequiredDialog(
      context,
      title: 'Basic KYC required',
      message:
          'Basic KYC is required for Match and Random Video Call. Please complete KYC first.',
    );
  }

  Future<bool> ensureFullApproved(BuildContext context) async {
    await init(refresh: true);
    if (fullApproved) return true;
    return _showRequiredDialog(
      context,
      title: 'Full KYC required',
      message:
          'Full KYC required. Please complete full KYC to continue.',
    );
  }

  Future<bool> _showRequiredDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Go to KYC'),
          ),
        ],
      ),
    );

    if (go == true && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const KycScreen()),
      );
      await refreshFromServer();
      return fullApproved || basicApproved;
    }

    return false;
  }
}
