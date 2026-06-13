// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/services/socket_service.dart';
import 'package:love_vibe_pro/services/secure_storage_service.dart';
import 'package:love_vibe_pro/services/chat_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/providers/match_provider.dart';

/// Result of an email/password login attempt.
enum LoginOutcome { success, twoFactorRequired }

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
    await prefs.remove('shown_gift_ids'); // legacy non-scoped key
    _isAuthenticated = false;
    _isDebugMode = false;
    _isGuest = false;
    _userId = null;
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  /// Email pending a 2FA code (set when a login returns `2fa_required`).
  String? _pending2faEmail;
  String? get pending2faEmail => _pending2faEmail;

  Future<LoginOutcome> loginWithGoogle() async {
    try {
      g_auth.GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        return LoginOutcome.success;
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

      // Account has 2FA enabled — an OTP was emailed; defer session creation.
      if (response['status'] == '2fa_required') {
        _pending2faEmail = response['email']?.toString();
        notifyListeners();
        return LoginOutcome.twoFactorRequired;
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
      await _bindAccountCaches(userId);

      _apiService.setToken(appToken);
      _isAuthenticated = true;
      _isGuest = false;
      _userId = userId;

      FCMService.instance.init();
      SocketService.instance.connect();

      notifyListeners();
      return LoginOutcome.success;
    } catch (e) {
      rethrow;
    }
  }

  // ── Email/Password Login ──────────────────────────────────────────────────

  Future<LoginOutcome> loginWithEmail(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.loginWithEmail(email, password);

      // Account has 2FA enabled — an OTP was emailed; defer session creation.
      if (response['status'] == '2fa_required') {
        _pending2faEmail = response['email']?.toString() ?? email;
        _isLoading = false;
        notifyListeners();
        return LoginOutcome.twoFactorRequired;
      }

      await _persistSession(response['data'] as Map<String, dynamic>?, email);
      return LoginOutcome.success;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Complete a login that required 2FA, by submitting the emailed OTP.
  Future<bool> verifyTwoFactor(String email, String code) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.verifyLogin2FA(email, code);
      await _persistSession(response['data'] as Map<String, dynamic>?, email);
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Persists the token + user from a successful auth response and flips the
  /// provider into the authenticated state. Shared by login and 2FA verify.
  Future<void> _persistSession(
      Map<String, dynamic>? dataMap, String email) async {
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

    await _bindAccountCaches(userId);

    FCMService.instance.init();
    SocketService.instance.connect();

    notifyListeners();
  }

  /// Bind per-account singleton caches to a newly-established session. Wipes any
  /// chat/message/block/profile state left over from a previous account (the
  /// singletons survive across logout→login since the Dart process keeps
  /// running), then points the chat layer at the new user id. Call from EVERY
  /// session-establishing path (login, Google, signup) so a freshly-created or
  /// switched account never shows the previous user's chats or history.
  Future<void> _bindAccountCaches(String userId) async {
    if (userId.isEmpty) return;
    try {
      ChatService.instance.clearForLogout();
      await ProfileService.instance.clearCachedProfile();
      ChatService.instance.setCurrentUserId(userId);
    } catch (_) {}
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
      // New account — force onboarding; skip the server re-check that would
      // incorrectly mark onboarding done if the backend sets a default gender.
      await prefs.setBool('onboarding_done', false);
      await prefs.setBool('onboarding_server_checked', true);
      await SecureStorageService.instance.writeToken(appToken);
      await _bindAccountCaches(userId);

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
    // Capture context before any awaits to avoid BuildContext-across-async-gap.
    final ctx = _navigatorKey?.currentContext;

    SocketService.instance.disconnect();

    // Mark the user offline on the server while the token is still valid.
    try {
      await _apiService.setPresence(false);
    } catch (_) {}

    // Stop background location tracking so the logged-out account's
    // coordinates are no longer sent to the server.
    try {
      final bgSvc = FlutterBackgroundService();
      if (await bgSvc.isRunning()) bgSvc.invoke('stopService');
    } catch (_) {}

    // Clear FCM token on server — also clears location columns server-side.
    try {
      await FCMService.instance.clearTokenOnServer();
    } catch (_) {}

    // Wipe in-memory nearby/match cache so the next account starts fresh.
    try {
      if (ctx != null) {
        Provider.of<MatchProvider>(ctx, listen: false).clearForLogout();
      }
    } catch (_) {}

    // Wipe per-account singleton caches so the next account never sees the
    // previous user's chats/messages/block-state or cached profile. These
    // singletons survive the logout→login transition, so they MUST be cleared
    // here (centralised) — otherwise a freshly-created account shows old data.
    try {
      ChatService.instance.clearForLogout();
    } catch (_) {}
    try {
      await ProfileService.instance.clearCachedProfile();
    } catch (_) {}

    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
    notifyListeners();
  }
}
