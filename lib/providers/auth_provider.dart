// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth;
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/services/socket_service.dart';
import 'package:love_vibe_pro/services/secure_storage_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isDebugMode = false;
  bool _isLoading = false;
  bool _isGuest = false;
  bool _isInitialized = false;
  bool _authInProgress = false;
  String? _userId;

  final g_auth.GoogleSignIn _googleSignIn = g_auth.GoogleSignIn(
    serverClientId:
        '354056335842-t2mgdi7487coht7tkjr3545dkakrmkqa.apps.googleusercontent.com',
    scopes: ['email'],
  );

  final ApiService _apiService = ApiService();

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get isAuthenticated => _isAuthenticated || _isDebugMode;
  bool get isLoading => _isLoading;
  bool get isGuest => _isGuest;
  bool get isInitialized => _isInitialized;
  bool get isRealUser => _isAuthenticated && !_isGuest;
  String? get userId => _userId;
  String? get currentUserId => _userId;

  String? get email {
    if (_isDebugMode) return 'test@debug.com';
    return _googleSignIn.currentUser?.email;
  }

  String? get name {
    if (_isDebugMode) return 'Debug User';
    return _googleSignIn.currentUser?.displayName;
  }

  String? get photoUrl {
    if (_isDebugMode) return 'https://www.w3schools.com/w3images/avatar2.png';
    return _googleSignIn.currentUser?.photoUrl;
  }

  // ── Guest Mode ────────────────────────────────────────────────────────────

  /// Enter guest mode - allows browsing without login
  Future<void> enterGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    _isGuest = true;
    _isAuthenticated = false;
    _isDebugMode = false;
    _userId = null;
    notifyListeners();
  }

  /// Exit guest mode - called when user logs in
  Future<void> exitGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_guest');
    _isGuest = false;
    notifyListeners();
  }

  /// Check if currently in guest mode
  Future<bool> checkGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isGuest = prefs.getBool('is_guest') ?? false;
    return _isGuest;
  }

  // ── Debug Bypass ──────────────────────────────────────────────────────────

  void debugLogin() async {
    // Debug bypass is stripped from release builds by R8 dead-code elimination.
    if (!kDebugMode) return;

    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 700));

    const debugToken = 'debug_bypass_sathi_2026';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_token', debugToken);
    await prefs.setString('auth_token', debugToken);
    await prefs.setString('user_id', '1');
    await prefs.setInt('user_id_int', 1);
    await prefs.remove('is_guest');

    _apiService.setToken(debugToken);
    _isDebugMode = true;
    _isAuthenticated = true;
    _isGuest = false;
    _userId = '1';
    _isLoading = false;

    notifyListeners();
  }

  // ── Restore session from SharedPreferences on cold start ──────────────────
  Future<void> checkAuth() async {
    if (_authInProgress) return;
    _authInProgress = true;
    try {
      // Read token from secure storage; migrates from SharedPreferences on first run.
      final token = await SecureStorageService.instance.readToken();
      final prefs = await SharedPreferences.getInstance();
      _isGuest = prefs.getBool('is_guest') ?? false;
      _userId = prefs.getString('user_id');

      if (token != null) {
        final isDebug = kDebugMode && (token == 'debug_bypass_sathi_2026');
        _apiService.setToken(token);

        // Optimistic auth: trust the local token immediately so the app opens
        // without waiting for a network round-trip. Validate in the background
        // and force logout only on an explicit 401/403 rejection.
        _isAuthenticated = true;
        _isDebugMode = isDebug;
        if (!isDebug) {
          SocketService.instance.connect();
          _validateTokenInBackground(token, prefs);
        } else {
          SocketService.instance.connect();
        }
      } else if (_isGuest) {
        _isAuthenticated = false;
      } else {
        _isAuthenticated = false;
      }
      _isInitialized = true;
      notifyListeners();
    } finally {
      _authInProgress = false;
    }
  }

  /// Validates the token in the background after the app is already open.
  /// On explicit rejection (401/403) clears the session and navigates to login.
  void _validateTokenInBackground(String token, SharedPreferences prefs) {
    Future.microtask(() async {
      try {
        final valid = await _apiService.validateToken(token);
        if (!valid) {
          await _clearSession(prefs);
          _isAuthenticated = false;
          _isInitialized = true;
          notifyListeners();
          // Redirect to login — use the global navigator key
          _navigatorKey?.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
        }
      } catch (_) {
        // Network error — leave user logged in (fail-open)
      }
    });
  }

  // Set by main.dart after runApp so we can redirect to /login on token rejection
  GlobalKey<NavigatorState>? _navigatorKey;
  void setNavigatorKey(GlobalKey<NavigatorState> key) => _navigatorKey = key;

  /// Wipes all locally stored session data (token, user info, feed cache).
  Future<void> _clearSession(SharedPreferences prefs) async {
    await SecureStorageService.instance.deleteToken();
    await prefs.remove('app_token');
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_id_int');
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('is_guest');
    await prefs.remove('cached_profile');
    await prefs.remove('cached_feed_items');
    _isAuthenticated = false;
    _isDebugMode = false;
    _isGuest = false;
    _userId = null;
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> loginWithGoogle() async {
    try {
      g_auth.GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        return;
      }

      final g_auth.GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      // ignore: unused_local_variable
      final String? accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception(
          'Google ID Token is null. Ensure SHA-1 is registered in Firebase and GCP Console (run: ./gradlew signingReport).',
        );
      }

      Map<String, dynamic> response;
      try {
        response = await _apiService.authGoogle(idToken);
      } catch (e) {
        rethrow;
      }

      final dataMap = response['data'] as Map<String, dynamic>?;
      final appToken = dataMap?['token']?.toString() ?? '';
      final userMap = dataMap?['user'] as Map<String, dynamic>?;
      final userId = userMap?['id']?.toString() ?? '';
      final userEmail = userMap?['email']?.toString() ?? '';
      final userName = userMap?['name']?.toString() ?? '';
      final isNewUser = response['is_new_user'] == true;

      if (appToken.isEmpty) {
        throw Exception(
          'Backend did not return a valid token. Response: $response',
        );
      }

      // Store to SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // If this is a brand-new account, wipe any stale cached data from a
      // previously deleted account that may have had the same Google email.
      if (isNewUser) {
        await prefs.remove('cached_profile');
        await prefs.remove('cached_feed_items');
        await prefs.remove('user_id_int');
      }

      await prefs.setString('app_token', appToken);
      await prefs.setString('auth_token', appToken);
      await prefs.setString('user_id', userId);
      await prefs.remove('is_guest'); // Clear guest mode on login
      if (userEmail.isNotEmpty) await prefs.setString('user_email', userEmail);
      if (userName.isNotEmpty) await prefs.setString('user_name', userName);
      await SecureStorageService.instance.writeToken(appToken);

      _apiService.setToken(appToken);
      _isAuthenticated = true;
      _isGuest = false;
      _userId = userId;

      FCMService.instance.init();
      SocketService.instance.connect();

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // ── Email/Password Login ──────────────────────────────────────────────────

  Future<bool> loginWithEmail(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.loginWithEmail(email, password);

      final dataMap = response['data'] as Map<String, dynamic>?;
      final appToken = dataMap?['token']?.toString() ?? '';
      final userMap = dataMap?['user'] as Map<String, dynamic>?;
      final userId = userMap?['id']?.toString() ?? '';
      final userName = userMap?['name']?.toString() ?? '';

      if (appToken.isEmpty) {
        throw Exception('Invalid credentials');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_token', appToken);
      await prefs.setString('auth_token', appToken);
      await prefs.setString('user_id', userId);
      await prefs.setString('user_email', email);
      await prefs.remove('is_guest');
      if (userName.isNotEmpty) await prefs.setString('user_name', userName);
      await SecureStorageService.instance.writeToken(appToken);

      _apiService.setToken(appToken);
      _isAuthenticated = true;
      _isGuest = false;
      _userId = userId;
      _isLoading = false;

      FCMService.instance.init();
      SocketService.instance.connect();

      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // ── Email/Password Signup ─────────────────────────────────────────────────

  Future<bool> signupWithEmail(
    String name,
    String email,
    String password,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.signupWithEmail(name, email, password);

      final dataMap = response['data'] as Map<String, dynamic>?;
      final appToken = dataMap?['token']?.toString() ?? '';
      final userMap = dataMap?['user'] as Map<String, dynamic>?;
      final userId = userMap?['id']?.toString() ?? '';

      if (appToken.isEmpty) {
        throw Exception('Failed to create account');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_token', appToken);
      await prefs.setString('auth_token', appToken);
      await prefs.setString('user_id', userId);
      await prefs.setString('user_email', email);
      await prefs.setString('user_name', name);
      await prefs.remove('is_guest');
      await SecureStorageService.instance.writeToken(appToken);

      _apiService.setToken(appToken);
      _isAuthenticated = true;
      _isGuest = false;
      _userId = userId;
      _isLoading = false;

      FCMService.instance.init();
      SocketService.instance.connect();

      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    SocketService.instance.disconnect();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
    notifyListeners();
  }
}
