import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted token storage backed by Android Keystore / iOS Keychain.
/// Falls back to plaintext SharedPreferences only during first-run migration,
/// then moves the token to secure storage.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _tokenKey = 'secure_auth_token';

  /// Read the auth token. Migrates from SharedPreferences on first access.
  Future<String?> readToken() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) return token;
      return await _migrateTokenFromPrefs();
    } catch (_) {
      return await _migrateTokenFromPrefs();
    }
  }

  /// Write the auth token to secure storage.
  Future<void> writeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  /// Remove the auth token (call on logout).
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    // Also wipe legacy plaintext copies
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_token');
      await prefs.remove('auth_token');
    } catch (_) {}
  }

  /// One-time migration: copy token from SharedPreferences into secure storage.
  Future<String?> _migrateTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      if (legacy != null && legacy.isNotEmpty) {
        await writeToken(legacy);
      }
      return legacy;
    } catch (_) {
      return null;
    }
  }
}
