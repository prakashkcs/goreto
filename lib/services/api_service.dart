import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/secure_storage_service.dart';
import 'package:love_vibe_pro/models/kyc_models.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/models/wallet_gift_item.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/services/engagement_tracker.dart';
import 'package:love_vibe_pro/main.dart' show navigatorKey;
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/auth/ban_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

/// Single constant API base URL for all endpoints
/// Use AppEnv.baseUrl for synchronous access, or AppEnv.getBaseUrlAsync() for custom URL
class ApiConstants {
  static String get baseUrl => AppEnv.baseUrl;

  // Token keys in SharedPreferences
  static const String authTokenKey = 'auth_token';
  static const String appTokenKey = 'app_token';
}

class ApiService {
  late Dio _dio;
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  String? _cachedToken;
  final EngagementTracker _engagementTracker = EngagementTracker();

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal();

  Future<void> init() async {
    if (_isInitialized) return;
    final baseUrl = await AppEnv.getBaseUrlAsync(); // Await for the base URL

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Identify as the mobile app so Imunify360 WAF doesn't block requests.
          'User-Agent': 'GoretoApp/1.0 (Android; Flutter)',
        },
      ),
    );

    // Wire engagement tracker → server
    _engagementTracker.setEngagementCallback((postId, action, watchSeconds) {
      recordEngagement(
          postId: postId, action: action, watchSeconds: watchSeconds);
    });

    // Cache token at init time
    await _refreshCachedToken();

    // Interceptor to add token to every request (uses cached token, no disk I/O)
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _cachedToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // HMAC-SHA256 app-signature for server-side enforcement.
          // Server checks X-App-ID + X-App-Timestamp + X-App-Signature.
          const appId = 'love_vibe_pro';
          const appSecret =
              'Ib47RTmAiMO66Vg2kY5gzMYekBNpctMusB7AWAHZDR0IEA1en09r8y1ZDFYM52ni';
          final ts =
              (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
          final method = options.method.toUpperCase();
          final path = options.uri.toString();
          // Compute signature body. FormData and other non-JSON-encodable
          // payloads (file uploads, multipart) sign over an empty body — the
          // server doesn't currently verify the signature, but a throw here
          // would crash the interceptor and fail the request entirely.
          String body;
          if (options.data is String) {
            body = options.data as String;
          } else if (options.data == null || options.data is FormData) {
            body = '';
          } else {
            try {
              body = jsonEncode(options.data);
            } catch (_) {
              body = '';
            }
          }
          final base = '$appId|$ts|$method|$path|$body';
          final sig = Hmac(sha256, utf8.encode(appSecret))
              .convert(utf8.encode(base))
              .toString();
          options.headers['X-App-ID'] = appId;
          options.headers['X-App-Timestamp'] = ts;
          options.headers['X-App-Signature'] = sig;
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // Retry once on connection errors caused by the server closing a
          // stale keep-alive connection before our request was received.
          if (e.type == DioExceptionType.connectionError &&
              e.requestOptions.extra['_retried'] != true) {
            try {
              e.requestOptions.extra['_retried'] = true;
              final response = await _dio.fetch(e.requestOptions);
              return handler.resolve(response);
            } catch (_) {
              // Fall through to normal error handling below.
            }
          }

          final status = e.response?.statusCode;

          // 401 — token invalid / account deleted: clear session and go to login.
          if (status == 401) {
            await _clearSession();
            _navigateToLogin();
          }

          // 403 — account banned, device banned, or pending delete.
          // ONLY clear session + show ban page when the server explicitly signals
          // a ban state. Generic 403s (permission denied on another user's profile,
          // private content, etc.) must fall through as normal errors so they do
          // not incorrectly log the current user out.
          if (status == 403) {
            try {
              final data = e.response?.data;
              Map<String, dynamic> body = {};
              if (data is Map<String, dynamic>) {
                body = data;
              } else if (data is String && data.trim().startsWith('{')) {
                try { body = Map<String, dynamic>.from(
                    json.decode(data) as Map); } catch (_) {}
              }
              final String apiStatus =
                  (body['status'] ?? body['api_status'] ?? '').toString();

              // Only known ban statuses trigger the full ban flow.
              const banStatuses = {
                'banned', 'account_banned', 'device_banned',
                'pending_delete', 'suspended',
              };
              if (banStatuses.contains(apiStatus)) {
                final String reason =
                    (body['ban_reason'] ?? body['message'] ?? '').toString();
                final String bannedAt = (body['banned_at'] ?? '').toString();

                String title;
                if (apiStatus == 'device_banned') {
                  title = 'Device Banned';
                } else if (apiStatus == 'pending_delete') {
                  title = 'Account Scheduled for Deletion';
                } else {
                  title = 'Account Suspended';
                }

                await _clearSession();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  navigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => BanScreen(
                        status: apiStatus,
                        title: title,
                        reason: reason,
                        bannedAt: bannedAt.isNotEmpty ? bannedAt : null,
                      ),
                    ),
                    (_) => false,
                  );
                });
              }
            } catch (_) {
              // Parse failure — do not log user out on a 403 we can't read.
            }
          }

          return handler.next(e);
        },
      ),
    );
    _isInitialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  // --- Auth & Tokens ---

  void setToken(String token) async {
    _cachedToken = token;
    // Persist to both secure storage (primary) and SharedPreferences (legacy
    // fallback — some internal methods still read the token directly from prefs).
    await SecureStorageService.instance.writeToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ApiConstants.authTokenKey, token);
  }

  /// Refresh cached token — tries secure storage first, then SharedPreferences.
  Future<void> _refreshCachedToken() async {
    final secure = await SecureStorageService.instance.readToken();
    if (secure != null && secure.isNotEmpty) {
      _cachedToken = secure;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(ApiConstants.authTokenKey) ??
        prefs.getString(ApiConstants.appTokenKey);
  }

  /// Call this after login/logout to update the cached token
  Future<void> refreshToken() async {
    await _refreshCachedToken();
  }

  /// Validates a stored token against the server.
  /// Returns true if the server accepts it, false on 401 / account_deleted / any error.
  /// Network failures return true (fail-open) to avoid logging out users on poor connectivity.
  Future<bool> validateToken(String token) async {
    try {
      final dio = await _ensureInitializedDio();
      final response = await dio.get(
        'auth.php',
        queryParameters: {'action': 'validate'},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.plain,
          // Short timeout — this runs on every cold start
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      dynamic payload = response.data;
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {}
      }
      if (payload is Map) {
        final status = payload['status']?.toString();
        if (status == 'success') return true;
        // Explicit rejection codes
        if (status == 'error') return false;
      }
      // 2xx with unexpected body → treat as valid
      return response.statusCode != null && response.statusCode! < 300;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return false;
      // Network error / timeout → fail-open (keep user logged in)
      return true;
    } catch (_) {
      return true;
    }
  }

  // Ensure _dio is initialized before use
  Future<Dio> _ensureInitializedDio() async {
    if (!_isInitialized) await init();
    return _dio;
  }

  /// Exposes the shared Dio client configured with base URL + auth interceptor.
  Future<Dio> getDioClient() async {
    return _ensureInitializedDio();
  }

  /// Fetch public app settings
  Future<Map<String, dynamic>> getPublicSettings() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'admin.php',
        queryParameters: {'action': 'get_public_settings'},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return Map<String, dynamic>.from(payload['settings'] ?? {});
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Login with email and password
  /// POST /auth.php?action=login
  Future<Map<String, dynamic>> loginWithEmail(
    String email,
    String password,
  ) async {
    const String endpoint = 'auth.php?action=login';
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        endpoint,
        data: {'email': email, 'password': password},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          return payload;
        } else {
          throw Exception(payload['message'] ?? 'Login failed');
        }
      }

      throw Exception('Invalid response format');
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      throw Exception(errorMsg);
    }
  }

  /// Signup with name, email and password
  /// POST /auth.php?action=register
  Future<Map<String, dynamic>> signupWithEmail(
    String name,
    String email,
    String password,
  ) async {
    const String endpoint = 'auth.php?action=register';
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        endpoint,
        data: {'name': name, 'email': email, 'password': password},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          return payload;
        } else {
          throw Exception(payload['message'] ?? 'Signup failed');
        }
      }

      throw Exception('Invalid response format');
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      throw Exception(errorMsg);
    }
  }

  /// Forgot Password - Request reset code
  /// Uses http package directly to avoid Dio baseUrl issues with ../ paths
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final baseUrl = AppEnv.baseUrl;
      // Remove /api/v1/ suffix to get parent URL (with or without trailing slash)
      final parentUrl = baseUrl.replaceAll(RegExp(r'api/v1/?$'), '');
      // Ensure parentUrl does NOT end with a slash
      String cleanParent = parentUrl;
      while (cleanParent.endsWith('/')) {
        cleanParent = cleanParent.substring(0, cleanParent.length - 1);
      }
      final uri = Uri.parse(
          '$cleanParent/api_password_reset.php?action=forgot_password');

      if (kDebugMode) print('[forgotPassword] POST $uri');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (kDebugMode)
        print(
            '[forgotPassword] status=${response.statusCode} body=${response.body}');

      dynamic payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
      throw Exception('Invalid response format');
    } catch (e) {
      if (kDebugMode) print('[forgotPassword] ERROR: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Verify reset code
  /// Uses http package directly to avoid Dio baseUrl issues with ../ paths
  Future<Map<String, dynamic>> verifyResetCode(
      String email, String code) async {
    try {
      final baseUrl = AppEnv.baseUrl;
      final parentUrl = baseUrl.replaceAll(RegExp(r'api/v1/$'), '');
      final uri =
          Uri.parse('$parentUrl/api_password_reset.php?action=verify_code');

      if (kDebugMode) print('[verifyResetCode] POST $uri');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (kDebugMode)
        print(
            '[verifyResetCode] status=${response.statusCode} body=${response.body}');

      dynamic payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
      throw Exception('Invalid response format');
    } catch (e) {
      if (kDebugMode) print('[verifyResetCode] ERROR: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Reset password with code
  /// Uses http package directly to avoid Dio baseUrl issues with ../ paths
  Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    try {
      final baseUrl = AppEnv.baseUrl;
      final parentUrl = baseUrl.replaceAll(RegExp(r'api/v1/$'), '');
      final uri =
          Uri.parse('$parentUrl/api_password_reset.php?action=reset_password');

      if (kDebugMode) print('[resetPassword] POST $uri');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'email': email, 'code': code, 'new_password': newPassword}),
      );

      if (kDebugMode)
        print(
            '[resetPassword] status=${response.statusCode} body=${response.body}');

      dynamic payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
      throw Exception('Invalid response format');
    } catch (e) {
      if (kDebugMode) print('[resetPassword] ERROR: $e');
      throw Exception('Network error: $e');
    }
  }

  Future<void> login(String email, String password) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'auth.php?action=login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200 && response.data['token'] != null) {
        final token = response.data['token'];
        setToken(token);
      } else {
        throw Exception(response.data['message'] ?? 'Login failed');
      }
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Sends a proposal to another user. Returns {matched: bool}
  Future<Map<String, dynamic>> sendProposal({
    required String targetUserId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=send_proposal',
        data: {'target_user_id': targetUserId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return payload;
      }
      throw Exception(payload?['message'] ?? 'Failed to send proposal');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Accept a received proposal
  Future<Map<String, dynamic>> acceptProposal({
    int? proposalId,
    int? senderId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=accept_proposal',
        data: {
          if (proposalId != null) 'proposal_id': proposalId,
          if (senderId != null) 'sender_id': senderId,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return payload;
      }
      throw Exception(payload?['message'] ?? 'Failed to accept proposal');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Reject a received proposal
  Future<bool> rejectProposal({int? proposalId, int? senderId}) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'user_actions.php?action=reject_proposal',
        data: {
          if (proposalId != null) 'proposal_id': proposalId,
          if (senderId != null) 'sender_id': senderId,
        },
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('rejectProposal error: $e');
      return false;
    }
  }

  /// Block a user. Returns true on success, false on failure.
  Future<bool> blockUser({required String blockedId}) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'user_actions.php?action=block_user',
        data: {'blocked_id': blockedId},
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('blockUser error: $e');
      return false;
    }
  }

  /// Get pending proposals received by the current user
  Future<List<dynamic>> getMyProposals({String type = 'received'}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=get_proposals',
        data: {'type': type},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return payload['proposals'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get accepted proposal connections
  Future<List<dynamic>> getConnections() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=get_connections',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return payload['connections'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  USER MANAGEMENT (block, mute, report, disconnect)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Unblock a user
  Future<bool> unblockUser({required String blockedId}) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'user_actions.php?action=unblock_user',
        data: {'blocked_id': blockedId},
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('unblockUser error: $e');
      return false;
    }
  }

  /// Mute a user (suppress notifications from them)
  Future<Map<String, dynamic>> muteUser({required String targetUserId}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=mute_user',
        data: {'target_user_id': targetUserId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> ? payload : {};
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Unmute a user
  Future<Map<String, dynamic>> unmuteUser({
    required String targetUserId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=unmute_user',
        data: {'target_user_id': targetUserId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> ? payload : {};
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Report a user
  Future<Map<String, dynamic>> reportUser({
    required String targetUserId,
    required String reason,
    String? details,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=report_user',
        data: {
          'target_user_id': targetUserId,
          'reason': reason,
          if (details != null && details.isNotEmpty) 'details': details,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      throw Exception('Invalid response');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Report a reel sound / music track
  Future<Map<String, dynamic>> reportSound({
    required String postId,
    required String reason,
    String? soundName,
    String? details,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_posts.php',
        data: {
          'action': 'report_sound',
          'post_id': postId,
          'reason': reason,
          if (soundName != null && soundName.isNotEmpty)
            'sound_name': soundName,
          if (details != null && details.isNotEmpty) 'details': details,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      throw Exception('Invalid response');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Disconnect a proposal connection
  Future<Map<String, dynamic>> disconnectProposal({
    required String targetUserId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=disconnect_proposal',
        data: {'target_user_id': targetUserId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      throw Exception('Invalid response');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Toggle public display setting for a proposal connection
  Future<Map<String, dynamic>> setProposalPublic({
    required int proposalId,
    required bool isPublic,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=toggle_public_proposal',
        data: {'proposal_id': proposalId, 'is_public': isPublic ? 1 : 0},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      throw Exception('Invalid response');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Get the current user's relationship status with another user
  /// Returns: { is_blocked, is_muted, is_proposal_connected, target_name }
  Future<Map<String, dynamic>> getUserActionStatus({
    required String targetUserId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'user_actions.php?action=get_user_status&target_user_id=$targetUserId',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return payload;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get the count of unread pending proposals (for badge display)
  Future<int> getProposalBadgeCount() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'user_actions.php?action=get_proposal_badge_count',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return (payload['unread_count'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Mark all received proposals as read (clears badge)
  Future<bool> markProposalsRead() async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'user_actions.php?action=mark_proposals_read',
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('markProposalsRead error: $e');
      return false;
    }
  }

  /// Sync offline BLE encounters and final location ping
  Future<void> syncOfflineData(
    List<Map<String, dynamic>> encounters,
    Map<String, dynamic>? finalPing,
  ) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_privacy.php?action=sync_offline_data',
        data: {'encounters': encounters, 'final_offline_ping': finalPing},
      );

      if (response.statusCode != 200 || response.data['status'] != 'success') {
        throw Exception(
          response.data['message'] ?? 'Failed to sync offline data',
        );
      }
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Right to be Forgotten: Wipe location tracking data
  Future<void> forgetMe() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post('api_privacy.php?action=forget_me');
      if (response.statusCode != 200 || response.data['status'] != 'success') {
        throw Exception(
          response.data['message'] ?? 'Failed to initiate forget_me',
        );
      }
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Submit KYC verification payload
  /// POST /user_actions.php?action=submit_kyc
  Future<bool> submitKyc({
    required String firstName,
    required String lastName,
    required File idFront,
    required File idBack,
    required File selfie,
    required File livenessVideo,
  }) async {
    const String endpoint = 'user_actions.php?action=submit_kyc';
    final dio = await _ensureInitializedDio();

    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      FormData formData = FormData.fromMap({
        'first_name': firstName,
        'last_name': lastName,
        'id_front': await MultipartFile.fromFile(
          idFront.path,
          filename: idFront.path.split('/').last,
        ),
        'id_back': await MultipartFile.fromFile(
          idBack.path,
          filename: idBack.path.split('/').last,
        ),
        'selfie': await MultipartFile.fromFile(
          selfie.path,
          filename: selfie.path.split('/').last,
        ),
        'liveness_video': await MultipartFile.fromFile(
          livenessVideo.path,
          filename: livenessVideo.path.split('/').last,
        ),
      });

      final response = await dio.post(
        endpoint,
        data: formData,
        options: Options(
          headers: {
            if (appToken != null) 'Authorization': 'Bearer $appToken',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      } else {
        final msg = payload?['message'] ?? 'Unknown error';
        final details = payload?['details'];
        if (details != null) {
          throw Exception('$msg Details: ${jsonEncode(details)}');
        }
        throw Exception(msg);
      }
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel a pending KYC verification
  /// POST /user_actions.php?action=cancel_kyc
  Future<bool> cancelKyc() async {
    const String endpoint = 'user_actions.php?action=cancel_kyc';
    final dio = await _ensureInitializedDio();

    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.post(
        endpoint,
        options: Options(
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Google Sign-In authentication.
  /// Posts id_token to backend endpoint: /auth.php?action=google
  /// Expected success response: {"status":"success", "data":{"token":"...", "user":{}}}
  /// Expected error response: {"status":"error", "message":"..."}
  Future<Map<String, dynamic>> authGoogle(String idToken) async {
    const String endpoint = 'auth.php?action=google';
    final dio = await _ensureInitializedDio();
    final String fullUrl = '${dio.options.baseUrl}$endpoint';
    try {
      final response = await dio.post(
        endpoint,
        data: {'id_token': idToken},
        options: Options(responseType: ResponseType.plain),
      );
      // Check for non-200 status
      if (response.statusCode != 200) {
        final errorMsg = 'HTTP ${response.statusCode}: ${response.data}';
        throw Exception(errorMsg);
      }

      // Parse response
      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }

      if (payload is! Map<String, dynamic>) {
        throw Exception('Invalid response format: expected JSON object');
      }

      // Check for error status from backend
      if (payload['status'] == 'error') {
        final errorMsg = payload['message'] ?? 'Unknown backend error';
        throw Exception(errorMsg);
      }

      // Validate success response structure
      if (payload['status'] == 'success') {
        final data = payload['data'] as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Missing "data" field in response');
        }
        final token = data['token']?.toString();
        if (token == null || token.isEmpty) {
          throw Exception('Missing "token" in response data');
        }
        return payload;
      }

      // Fallback: return raw payload if status is missing but has token
      return payload;
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      final responseBody = e.response?.data?.toString() ?? 'No response body';
      throw Exception('Network error: $errorMsg. Body: $responseBody');
    } catch (e) {
      rethrow;
    }
  }

  // --- Posts & Feed ---

  Future<List<dynamic>> getReels({String? type, String? soundName}) async {
    final dio = await _ensureInitializedDio();
    try {
      // Attach interest signals to personalise trending/for-you reels
      String interests = '';
      try {
        interests = await _engagementTracker.interestParam();
      } catch (_) {}

      if (type != null && type.isNotEmpty) {
        final response = await dio.get(
          'posts.php?action=reels',
          queryParameters: {
            'type': type,
            'limit': '20',
            if (interests.isNotEmpty) 'interests': interests,
            if (soundName != null && soundName.isNotEmpty) 'sound_name': soundName,
          },
          options: Options(responseType: ResponseType.plain),
        );

        dynamic payload = response.data;
        if (payload is String) {
          payload = jsonDecode(payload);
        }

        List<dynamic> posts = [];
        if (payload is Map<String, dynamic>) {
          posts = (payload['posts'] ?? payload['reels'] ?? []) as List<dynamic>;
        } else if (payload is List) {
          posts = payload;
        }

        if (posts.isNotEmpty) {
          return posts.where((post) {
            final isRepostStr = post['is_repost']?.toString() ?? '0';
            final isRepost = isRepostStr == '1' || isRepostStr == 'true';
            if (isRepost) return false; // Filter out reposts

            final fileUrl = (post['file_url'] ?? '').toString().toLowerCase();
            final t = (post['type'] ?? '').toString().toLowerCase();
            return t == 'video' ||
                t == 'reel' ||
                post['video_url'] != null ||
                fileUrl.endsWith('.mp4') ||
                fileUrl.endsWith('.mov') ||
                fileUrl.endsWith('.m4v') ||
                fileUrl.endsWith('.webm');
          }).toList();
        }
      }

      final feed = await getFeed();
      return feed.where((post) {
        final isRepostStr = post['is_repost']?.toString() ?? '0';
        final isRepost = isRepostStr == '1' || isRepostStr == 'true';
        if (isRepost) return false;

        final t = (post['type'] ?? '').toString().toLowerCase();
        return t == 'video' || t == 'reel';
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getFollowingReels() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get('posts.php?action=following_reels');
      dynamic payload = response.data;

      if (payload is String) {
        payload = jsonDecode(payload);
      }

      List<dynamic> posts = [];
      if (payload is Map<String, dynamic>) {
        posts = (payload['posts'] ?? payload['reels'] ?? []) as List<dynamic>;
      } else if (payload is List) {
        posts = payload;
      }

      return posts.where((post) {
        final isRepostStr = post['is_repost']?.toString() ?? '0';
        final isRepost = isRepostStr == '1' || isRepostStr == 'true';
        if (isRepost) return false;

        final fileUrl = (post['file_url'] ?? '').toString().toLowerCase();
        final t = (post['type'] ?? '').toString().toLowerCase();
        return t == 'video' ||
            t == 'reel' ||
            post['video_url'] != null ||
            fileUrl.endsWith('.mp4') ||
            fileUrl.endsWith('.mov') ||
            fileUrl.endsWith('.m4v') ||
            fileUrl.endsWith('.webm');
      }).toList();
    } catch (e) {
      // Fallback: derive following reels from global reels payload if flags exist.
      final reels = await getReels();
      return reels.where((post) {
        final user = post['user'];
        return post['is_following'] == true ||
            post['following'] == true ||
            post['is_followed'] == true ||
            (user is Map &&
                (user['is_following'] == true ||
                    user['following'] == true ||
                    user['is_followed'] == true));
      }).toList();
    }
  }

  /// Legacy like used by old widgets ï¿½ kept for backward compat
  Future<bool> likePost(dynamic postId) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post('like_post.php', data: {'post_id': postId});
      return true;
    } catch (e) {
      if (kDebugMode) print('likePost error: $e');
      return false;
    }
  }

  /// Toggle like using new endpoint: POST /likes.php?action=toggle
  /// Returns {liked: bool, count: int}
  Future<Map<String, dynamic>> toggleLike(dynamic postId) async {
    const String endpoint = 'likes.php?action=toggle';
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.post(
        endpoint,
        data: {'post_id': postId},
        options: Options(responseType: ResponseType.plain),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          final data = payload['data'] as Map<String, dynamic>?;
          final rawLiked = data?['liked'];
          final serverLiked = rawLiked == true ||
              rawLiked == 1 ||
              rawLiked == '1' ||
              rawLiked == 'true';
          final count = data?['likes_count'] ?? data?['count'] ?? 0;

          // Update local liked state
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString('user_id') ?? 'anonymous';
          final likedKey = 'liked_posts_$userId';
          final likedSet = prefs.getStringList(likedKey)?.toSet() ?? {};
          final postIdStr = postId.toString();

          if (serverLiked) {
            likedSet.add(postIdStr);
          } else {
            likedSet.remove(postIdStr);
          }
          await prefs.setStringList(likedKey, likedSet.toList());

          return {'liked': serverLiked, 'count': count};
        }
      }

      return {'liked': false, 'count': 0};
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      return {'liked': false, 'count': 0, 'error': errorMsg};
    } catch (e) {
      return {'liked': false, 'count': 0, 'error': e.toString()};
    }
  }

  /// Legacy method - now calls toggleLike
  Future<Map<String, dynamic>> likePostToggle(dynamic postId) async {
    return toggleLike(postId);
  }

  /// Check if a post is liked locally (from SharedPreferences)
  Future<bool> isPostLikedLocally(dynamic postId) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'anonymous';
    final likedKey = 'liked_posts_$userId';
    final likedSet = prefs.getStringList(likedKey)?.toSet() ?? {};
    return likedSet.contains(postId.toString());
  }

  /// Get all liked post IDs for current user
  Future<Set<String>> getLikedPostIds() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'anonymous';
    final likedKey = 'liked_posts_$userId';
    return prefs.getStringList(likedKey)?.toSet() ?? {};
  }

  // --- Post Management API ---------------------------------------------------

  /// Upload a media post (photo, video, reel, audio).
  /// Sends multipart/form-data to api_posts.php?action=create.
  /// Returns the server response map on success, throws on failure.
  Future<Map<String, dynamic>> uploadPost(
    File mediaFile,
    String caption,
    String type, {
    String? hashtags,
    String? soundName,
    bool muteAudio = false,
    bool subscriberOnly = false,
    String? thumbnailPath,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final fileName = mediaFile.path.split('/').last.split('\\').last;
      final formData = FormData.fromMap({
        'action': 'create',
        'caption': caption,
        'type': type,
        if (hashtags != null && hashtags.isNotEmpty) 'hashtags': hashtags,
        if (soundName != null && soundName.isNotEmpty) 'sound_name': soundName,
        'mute_audio': muteAudio ? '1' : '0',
        'subscriber_only': subscriberOnly ? '1' : '0',
        'file':
            await MultipartFile.fromFile(mediaFile.path, filename: fileName),
        if (thumbnailPath != null && thumbnailPath.isNotEmpty)
          'thumbnail': await MultipartFile.fromFile(
            thumbnailPath,
            filename: thumbnailPath.split('/').last.split('\\').last,
          ),
      });

      final response = await dio.post(
        'api_posts.php',
        data: formData,
        options: Options(
          responseType: ResponseType.plain,
          // Large files need more time
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        final ok = payload['status'] == true ||
            payload['status'] == 'true' ||
            payload['status'] == 'success';
        if (ok) return payload;
        throw Exception(payload['message']?.toString() ?? 'Upload failed');
      }
      throw Exception('Invalid response from server');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Upload a text-only post (no media file).
  /// Sends JSON to api_posts.php?action=create.
  Future<Map<String, dynamic>> uploadTextPost(
    String caption,
    String type, {
    String? hashtags,
    bool subscriberOnly = false,
    String bgStyle = '0',
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_posts.php',
        data: {
          'action': 'create',
          'caption': caption,
          'type': type,
          if (hashtags != null && hashtags.isNotEmpty) 'hashtags': hashtags,
          'subscriber_only': subscriberOnly ? 1 : 0,
          'bg_style': bgStyle,
        },
        options: Options(responseType: ResponseType.plain),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        final ok = payload['status'] == true ||
            payload['status'] == 'true' ||
            payload['status'] == 'success';
        if (ok) return payload;
        throw Exception(payload['message']?.toString() ?? 'Upload failed');
      }
      throw Exception('Invalid response from server');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// Record engagement signal (watch time / skip / share / save): POST /posts.php action=engage
  Future<void> recordEngagement({
    required String postId,
    required String action,
    int watchSeconds = 0,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'posts.php',
        data: {
          'action': 'engage',
          'post_id': postId,
          'engage_action': action,
          'watch_seconds': watchSeconds,
        },
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      if (kDebugMode) print('recordEngagement error: $e');
    }
  }

  /// Record a view for a post: POST /posts.php?action=view
  Future<void> recordView(dynamic postId) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'posts.php',
        data: {'action': 'view', 'post_id': postId},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      if (kDebugMode) print('recordView error: $e');
    }
  }

  /// Track profile visit: POST /profile.php?action=visit
  Future<void> trackProfileVisit(String targetUserId) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'profile.php',
        data: {'action': 'visit', 'user_id': targetUserId},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      if (kDebugMode) print('trackProfileVisit error: $e');
    }
  }

  /// Record that the current user viewed a profile.
  Future<void> recordProfileView(String profileId) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post('profile_views.php', data: {'profile_id': profileId});
    } catch (_) {}
  }

  /// Fetch the list of users who viewed the current user's profile.
  Future<Map<String, dynamic>> getProfileViewers({int page = 1}) async {
    final dio = await _ensureInitializedDio();
    try {
      final resp = await dio.get('profile_views.php',
          queryParameters: {'page': page});
      if (resp.data is Map<String, dynamic>) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'viewers': []};
  }

  /// Delete a post (must be own post)
  /// Server expects HTTP DELETE to /posts.php with post_id in body
  Future<bool> deletePost(dynamic postId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.delete(
        'posts.php',
        data: {'post_id': postId, 'id': postId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Edit/update a post caption (must be own post)
  /// TODO: Backend endpoint needed - POST /posts.php?action=edit
  Future<bool> editPost(dynamic postId, String newCaption) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'posts.php',
        queryParameters: {'action': 'edit'},
        data: {'post_id': postId, 'caption': newCaption},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Report a post with reason
  /// TODO: Backend endpoint needed - POST /reports.php or /posts.php?action=report
  Future<bool> reportPost(
    dynamic postId,
    String reason, {
    String? details,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'posts.php',
        queryParameters: {'action': 'report'},
        data: {
          'post_id': postId,
          'reason': reason,
          if (details != null && details.isNotEmpty) 'details': details,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Submit a system / content / abuse report from the user.
  /// Optionally attaches an image (screenshot). Backed by api_reports.php.
  Future<void> reportSystem({
    required String reason,
    required String details,
    String? imagePath,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final Map<String, dynamic> fields = {
        'action': 'submit_report',
        'report_type': 'system',
        'reason': reason,
        'details': details,
        'reported_id': '0',
      };
      if (imagePath != null && imagePath.isNotEmpty) {
        fields['image'] = await MultipartFile.fromFile(
          imagePath,
          filename: 'report_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }
      final response = await dio.post(
        'api_reports.php',
        data: FormData.fromMap(fields),
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map && payload['status'] != 'success') {
        throw Exception(payload['message'] ?? 'Report failed');
      }
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  /// List comments for a post: GET /comments.php?action=list&post_id=<int>
  /// Uses Authorization: Bearer <app_token>
  Future<List<dynamic>> listComments(dynamic postId) async {
    final String endpoint = 'comments.php?action=list&post_id=$postId';
    final dio = await _ensureInitializedDio();
    final String fullUrl = '${dio.options.baseUrl}$endpoint';
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.get(
        endpoint,
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          final comments = (payload['data'] as List<dynamic>? ?? []);
          return comments;
        } else {
          final errorMsg = payload['message'] ?? 'Unknown error';
        }
      }
      return [];
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      final responseBody = e.response?.data?.toString() ?? 'No response body';
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Add a comment: POST /comments.php?action=add
  /// JSON body: { "post_id": <int>, "comment": "<text>" }
  /// Uses Authorization: Bearer <app_token>
  Future<Map<String, dynamic>?> addComment(
    dynamic postId,
    String commentText,
  ) async {
    const String endpoint = 'comments.php?action=add';
    final dio = await _ensureInitializedDio();
    final String fullUrl = '${dio.options.baseUrl}$endpoint';
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      if (appToken == null) {}

      final response = await dio.post(
        endpoint,
        data: {'post_id': postId, 'comment': commentText},
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          // Strict: only return payload['data'] if it's a Map
          final data = payload['data'];
          if (data is Map<String, dynamic>) {
            return data;
          } else {
            return null;
          }
        } else {
          final errorMsg = payload['message'] ?? 'Unknown error';
        }
      }
      return null;
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      final responseBody = e.response?.data?.toString() ?? 'No response body';
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Reply to a comment: POST /comments.php?action=reply
  /// Body: {post_id, parent_id, comment}
  Future<Map<String, dynamic>?> replyToComment(
    dynamic postId,
    String parentId,
    String commentText,
  ) async {
    const String endpoint = '/comments.php?action=reply';
    final dio = await _ensureInitializedDio();
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.post(
        endpoint,
        data: {
          'post_id': postId,
          'parent_id': parentId,
          'comment': commentText,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Edit a comment: POST /comments.php?action=edit
  /// Body: {comment_id, comment}
  Future<bool> editComment(dynamic commentId, String newText) async {
    const String endpoint = '/comments.php?action=edit';
    final dio = await _ensureInitializedDio();
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.post(
        endpoint,
        data: {'comment_id': commentId, 'comment': newText},
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Delete a comment: POST /comments.php?action=delete
  /// Body: {comment_id}
  Future<bool> deleteComment(dynamic commentId) async {
    const String endpoint = '/comments.php?action=delete';
    final dio = await _ensureInitializedDio();
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.post(
        endpoint,
        data: {'comment_id': commentId},
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Share/repost on profile: POST /share.php?action=profile
  /// Body: { "post_id": <int>, "caption": "<string>" }
  /// Auth: Bearer <app_token>
  Future<Map<String, dynamic>?> shareOnProfile(
    dynamic postId,
    String caption,
  ) async {
    const String endpoint =
        'https://goreto.org/ekloadmin/api/v1/share.php?action=profile';
    final dio = await _ensureInitializedDio();
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      final response = await dio.post(
        endpoint,
        data: {'post_id': postId, 'caption': caption},
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          headers: {if (appToken != null) 'Authorization': 'Bearer $appToken'},
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        if (payload['status'] == 'success') {
          return payload;
        } else {
          final errorMsg = payload['message'] ?? 'Unknown error';
        }
      }
      return null;
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      final responseBody = e.response?.data?.toString() ?? 'No response body';
      return null;
    } catch (e) {
      return null;
    }
  }

  /// GET /follow.php?action=status&user_id=<targetId>
  /// Returns normalized map: {
  ///   is_following: bool,
  ///   followers_count: int,
  ///   following_count: int,
  ///   posts_count: int
  /// }
  Future<Map<String, dynamic>?> getFollowStatus(dynamic targetUserId) async {
    final String endpoint = 'follow.php?action=status&user_id=$targetUserId';
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.get(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );
      return _extractProfileStats(response.data, includeFollowState: true);
    } catch (e) {
      return null;
    }
  }

  /// POST /follow.php?action=follow
  /// Body: {"user_id": targetId}
  Future<Map<String, dynamic>?> followUser(dynamic targetUserId) async {
    return _followAction('follow', targetUserId);
  }

  /// POST /follow.php?action=unfollow
  /// Body: {"user_id": targetId}
  Future<Map<String, dynamic>?> unfollowUser(dynamic targetUserId) async {
    return _followAction('unfollow', targetUserId);
  }

  Future<Map<String, dynamic>?> _followAction(
    String action,
    dynamic targetUserId,
  ) async {
    final String endpoint = 'follow.php?action=$action';
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.post(
        endpoint,
        data: FormData.fromMap({'user_id': targetUserId}),
        options: Options(responseType: ResponseType.plain),
      );
      return _extractProfileStats(response.data, includeFollowState: true);
    } on DioException catch (e) {
      final errorMsg = _handleError(e);
      final responseBody = e.response?.data?.toString() ?? 'No response body';
      return null;
    } catch (e) {
      return null;
    }
  }

  /// GET /profile_counts.php?user_id=<targetId>
  /// Returns normalized map: {
  ///   followers_count: int,
  ///   following_count: int,
  ///   posts_count: int
  /// }
  /// GET /follow.php?action=followers&user_id=X&page=N
  /// GET /follow.php?action=following&user_id=X&page=N
  /// Returns: {status, users: [{id,name,username,avatar,is_following}], total, page, has_more}
  Future<Map<String, dynamic>?> getFollowList({
    required dynamic userId,
    required String type, // 'followers' or 'following'
    int page = 1,
    int limit = 20,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'follow.php?action=$type&user_id=$userId&page=$page&limit=$limit',
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      if (raw is Map && raw['status'] == true) return Map<String, dynamic>.from(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getProfileCounts(dynamic targetUserId) async {
    final String endpoint = 'profile_counts.php?user_id=$targetUserId';
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.get(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );
      return _extractProfileStats(response.data, includeFollowState: false);
    } catch (e) {
      return null;
    }
  }

  /// GET /profile.php?user_id=<targetId>
  /// Returns normalized map:
  /// {
  ///   followers_count: int,
  ///   following_count: int,
  ///   posts_count: int,
  ///   is_following: bool,
  ///   social_links: Map<String, String>
  /// }
  Future<Map<String, dynamic>?> getProfileStats(dynamic targetUserId) async {
    final String endpoint = '/profile_v19.php?user_id=$targetUserId';
    final dio = await _ensureInitializedDio();
    final String fullUrl = '${dio.options.baseUrl}$endpoint';
    try {
      final response = await dio.get(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );
      return _extractProfileStats(response.data, includeFollowState: true);
    } catch (e) {
      return null;
    }
  }

  /// GET /match_profiles.php?action=get_my_profile&user_id=<profileUserId>
  /// Returns the match profile settings (interests, qualities, etc) for ANY user
  Future<Map<String, dynamic>?> getMatchProfile(String targetUserId) async {
    final String endpoint =
        '/match_profiles.php?action=get_my_profile&user_id=$targetUserId';
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );

      dynamic parsed = response.data;
      if (parsed is String) {
        parsed = jsonDecode(parsed);
      }
      if (parsed is! Map<String, dynamic>) return null;

      if (parsed['status'] == 'success' && parsed['profile'] is Map) {
        return Map<String, dynamic>.from(parsed['profile']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// GET /social_links.php?action=get&user_id=<profileUserId>
  /// Returns only non-empty social links for the requested profile user.
  Future<Map<String, String>?> getProfileSocialLinks(
    dynamic targetUserId,
  ) async {
    final String endpoint =
        '/social_links.php?action=get&user_id=$targetUserId';
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.get(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );

      dynamic parsed = response.data;
      if (parsed is String) {
        parsed = jsonDecode(parsed);
      }
      if (parsed is! Map<String, dynamic>) return null;

      dynamic linksRaw = parsed['links'];
      if (linksRaw is! Map) {
        final data = parsed['data'];
        if (data is Map<String, dynamic>) {
          linksRaw = data['links'] is Map ? data['links'] : data;
        }
      }
      if (linksRaw is! Map) return <String, String>{};

      final linksMap = Map<String, dynamic>.from(linksRaw);
      final result = <String, String>{};
      for (final entry in linksMap.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          result[key] = value;
        }
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _extractProfileStats(
    dynamic payload, {
    required bool includeFollowState,
  }) {
    dynamic parsed = payload;
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return null;
      }
    }

    if (parsed is! Map<String, dynamic>) return null;

    final status = parsed['status'];
    final successFlag = parsed['success'];
    if (status != null) {
      final statusStr = status.toString().toLowerCase();
      final isStatusOk = status == true ||
          status == 1 ||
          statusStr.startsWith('success') ||
          statusStr == 'ok';
      if (!isStatusOk && successFlag != true && successFlag != 1) {
        return null;
      }
    }

    final data = parsed['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(parsed['user'])
        : (parsed['data'] is Map<String, dynamic>
            ? ((parsed['data']['user'] is Map<String, dynamic>)
                ? Map<String, dynamic>.from(parsed['data']['user'])
                : Map<String, dynamic>.from(parsed['data']))
            : (parsed['counts'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(parsed['counts'])
                : parsed));

    int? pickInt(List<String> keys) {
      for (final key in keys) {
        final dynamic value = data.containsKey(key) ? data[key] : parsed[key];
        final int? parsedInt = _toInt(value);
        if (parsedInt != null) return parsedInt;
      }
      return null;
    }

    final result = <String, dynamic>{};

    final followers = pickInt([
      'followers_count',
      'followers',
      'follower_count',
    ]);
    final following = pickInt(['following_count', 'following']);
    final posts = pickInt([
      'posts_count',
      'posts',
      'post_count',
      'total_posts',
    ]);

    if (followers != null) result['followers_count'] = followers;
    if (following != null) result['following_count'] = following;
    if (posts != null) result['posts_count'] = posts;

    if (includeFollowState) {
      final followRaw = parsed['is_following'] ??
          data['is_following'] ??
          parsed['following'] ??
          data['following'];
      final followBool = _toBool(followRaw);
      if (followBool != null) result['is_following'] = followBool;
    }

    final socialLinksRaw = data['social_links'] ?? parsed['social_links'];
    if (socialLinksRaw is Map) {
      final social = <String, String>{};
      for (final entry in socialLinksRaw.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          social[key] = value;
        }
      }
      if (social.isNotEmpty) {
        result['social_links'] = social;
      }
    }

    // Pass through match profile traits
    if (data.containsKey('interests')) {
      result['interests'] = data['interests'];
    } else if (parsed.containsKey('interests'))
      result['interests'] = parsed['interests'];

    if (data.containsKey('looking_for')) {
      result['looking_for'] = data['looking_for'];
    } else if (parsed.containsKey('looking_for'))
      result['looking_for'] = parsed['looking_for'];

    if (data.containsKey('qualities')) {
      result['qualities'] = data['qualities'];
    } else if (parsed.containsKey('qualities'))
      result['qualities'] = parsed['qualities'];

    if (data.containsKey('income')) {
      result['income'] = data['income'];
    } else if (parsed.containsKey('income'))
      result['income'] = parsed['income'];

    if (data.containsKey('income_status')) {
      result['income_status'] = data['income_status'];
    } else if (parsed.containsKey('income_status'))
      result['income_status'] = parsed['income_status'];

    return result.isEmpty ? null : result;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool? _toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return null;
  }

  /// Legacy methods - now call new endpoints
  Future<List<dynamic>> getComments(dynamic postId) async {
    return listComments(postId);
  }

  Future<Map<String, dynamic>?> postComment(dynamic postId, String text) async {
    return addComment(postId, text);
  }

  /// Search users: GET /search.php?action=users&q=<text>
  Future<List<dynamic>> searchUsers(String query) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/search.php',
        queryParameters: {'action': 'users', 'q': query},
        options: Options(responseType: ResponseType.plain),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic>) {
        final users = payload['data'] ?? payload['users'] ?? [];
        if (users is List) return users;
      }
      if (payload is List) return payload;
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> searchPosts(String query) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/posts.php',
        queryParameters: {'action': 'search', 'q': query},
        options: Options(responseType: ResponseType.plain),
      );

      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }

      if (payload is Map<String, dynamic>) {
        return (payload['data'] ?? payload['posts'] ?? []) as List<dynamic>;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// GET /posts.php?action=get&post_id=X — fetch a single post by ID.
  Future<Map<String, dynamic>?> getPostById(String postId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/posts.php',
        queryParameters: {'action': 'get', 'post_id': postId},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (payload == null) return null;
      final post = payload['post'];
      if (post is Map) return _normalizeFeedPost(Map<String, dynamic>.from(post));
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFeed({bool force = false}) async {
    final dio = await _ensureInitializedDio();
    try {
      // Attach user interest signals so the server can personalise ranking
      String interests = '';
      try {
        interests = await _engagementTracker.interestParam();
      } catch (_) {}

      final response = await dio.get(
        '/posts.php',
        queryParameters: {
          'type': 'feed',
          if (interests.isNotEmpty) 'interests': interests,
          if (force || kDebugMode) '_t': DateTime.now().millisecondsSinceEpoch,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (force || kDebugMode) 'Cache-Control': 'no-cache'},
        ),
      );

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      List<dynamic> items;
      if (data is Map<String, dynamic> && data['posts'] is List) {
        items = List<dynamic>.from(data['posts'] as List);
      } else if (data is Map<String, dynamic> && data['data'] is List) {
        items = List<dynamic>.from(data['data'] as List);
      } else if (data is Map<String, dynamic> &&
          data['data'] is Map &&
          (data['data'] as Map)['posts'] is List) {
        items = List<dynamic>.from((data['data'] as Map)['posts'] as List);
      } else if (data is List) {
        items = List<dynamic>.from(data);
      } else {
        items = <dynamic>[];
      }

      final normalized = items
          .whereType<Map>()
          .map((p) => _normalizeFeedPost(Map<String, dynamic>.from(p)))
          .toList();

      // Client-side interest re-ranking
      final reranked = await _engagementTracker.rerankFeed(normalized);
      return reranked.cast<Map<String, dynamic>>();
    } catch (e) {
      return <Map<String, dynamic>>[];
    }
  }

  // --- Stories ---

  Map<String, dynamic>? _extractUploadedPostFromPayload(
    Map<String, dynamic> payload,
  ) {
    final candidates = <dynamic>[
      payload['post'],
      if (payload['posts'] is List && (payload['posts'] as List).isNotEmpty)
        (payload['posts'] as List).first,
      if (payload['data'] is Map<String, dynamic>)
        (payload['data'] as Map<String, dynamic>)['post'],
      if (payload['data'] is Map<String, dynamic> &&
          (payload['data'] as Map<String, dynamic>)['posts'] is List &&
          ((payload['data'] as Map<String, dynamic>)['posts'] as List)
              .isNotEmpty)
        (((payload['data'] as Map<String, dynamic>)['posts'] as List).first),
    ];

    for (final candidate in candidates) {
      if (candidate is Map) {
        return Map<String, dynamic>.from(candidate);
      }
    }

    return null;
  }

  Map<String, dynamic> _normalizeFeedPost(Map<String, dynamic> raw) {
    final base =
        _dio.options.baseUrl.isNotEmpty ? _dio.options.baseUrl : AppEnv.baseUrl;

    final normalized = Map<String, dynamic>.from(raw);

    final isRepost = _toBool(raw['is_repost']) == true ||
        (int.tryParse((raw['repost_of'] ?? '0').toString()) ?? 0) > 0 ||
        raw['original_post_id'] != null;

    // Handle locked premium posts (is_locked flag injected from posts.php API)
    final bool backendLocked =
        raw['is_locked'] == 1 || raw['is_locked'] == true;
    bool isLocked = backendLocked;

    dynamic rawMediaStr = _firstNonEmptyValue([
      raw['file_url'],
      raw['image_url'],
      raw['media_url'],
      raw['image'],
      raw['photo'],
      raw['raw_file_url'],
      if (isRepost) raw['original_file_url'],
    ]);

    if (rawMediaStr != null && rawMediaStr.toString().startsWith('LOCKED:')) {
      isLocked = true;
      rawMediaStr = rawMediaStr.toString().substring(7); // strip 'LOCKED:'
    }

    final mediaUrl = normalizeMediaUrl(rawMediaStr, baseUrl: base, folder: '');

    if (mediaUrl.isEmpty) {}

    final avatarUrl = normalizeMediaUrl(
      raw['author_avatar'] ??
          raw['user_avatar'] ??
          raw['user_profile_pic'] ??
          raw['profile_pic'] ??
          raw['user']?['avatar'] ??
          raw['user']?['profile_pic'],
      baseUrl: base,
      folder: 'profiles',
    );

    // Force canonical media fields so UI never accidentally binds avatar/other keys.
    normalized['media_url'] = mediaUrl;
    normalized['file_url'] = mediaUrl;
    normalized['image'] = mediaUrl;
    normalized['is_repost'] = isRepost ? 1 : (raw['is_repost'] ?? 0);
    normalized['is_locked'] = isLocked;

    final repostCaption = (raw['repost_caption'] ?? '').toString().trim();
    if (isRepost) {
      normalized['caption'] = repostCaption.isNotEmpty
          ? repostCaption
          : (raw['caption'] ?? '').toString();
    }

    final isVideo = isLikelyVideoPost(raw, mediaUrl);
    if (isVideo) {
      normalized['video_url'] = mediaUrl;
      final thumbRaw = (raw['thumbnail_url'] ?? '').toString().trim();
      final thumb = thumbRaw.isNotEmpty ? normalizeMediaUrl(thumbRaw, baseUrl: base) : '';
      normalized['thumbnail_url'] = thumb;
      normalized['image_url'] = thumb;
    } else {
      normalized['video_url'] = '';
      normalized['image_url'] = mediaUrl;
      normalized['thumbnail_url'] = mediaUrl;
    }

    if (avatarUrl.isNotEmpty) {
      normalized['user_avatar'] = avatarUrl;
      normalized['user_profile_pic'] = avatarUrl;
      normalized['userImage'] = avatarUrl;
    }

    // Normalize user object for widgets expecting nested user payload
    final user = raw['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(raw['user'])
        : <String, dynamic>{};
    if (raw['user_id'] != null && user['id'] == null) {
      user['id'] = raw['user_id'];
    }

    final nameVal = raw['author_name'] ?? raw['user_name'] ?? '';
    if (nameVal.toString().isNotEmpty && user['name'] == null) {
      user['name'] = nameVal;
    }
    if (avatarUrl.isNotEmpty) {
      user['avatar'] = avatarUrl;
      user['profile_pic'] = avatarUrl;
    }
    final subStatus =
        raw['author_subscription_status'] ?? raw['subscription_status'];
    if (subStatus != null) {
      user['subscription_status'] = subStatus.toString();
    }
    if (user.isNotEmpty) normalized['user'] = user;
    if (subStatus != null) {
      normalized['author_subscription_status'] = subStatus.toString();
    }

    final usernameVal = raw['author_username'] ?? raw['username'] ?? nameVal;
    if (usernameVal.toString().isNotEmpty &&
        (normalized['username'] ?? '').toString().isEmpty) {
      normalized['username'] = usernameVal;
    }

    // Build nested original_post for repost widgets from flat SQL fields.
    if (raw['original_post_id'] != null) {
      final originalMedia = normalizeMediaUrl(
        _firstNonEmptyValue([
          raw['original_file_url'],
          raw['original_image_url'],
          raw['original_media_url'],
          raw['original_photo'],
        ]),
        baseUrl: base,
        folder: '',
      );
      final originalAvatar = normalizeMediaUrl(
        raw['original_user_profile_pic'],
        baseUrl: base,
        folder: 'profiles',
      );

      normalized['original_post'] = {
        'id': raw['original_post_id'],
        'post_id': raw['original_post_id'],
        'user_id': raw['original_user_id'],
        'caption': raw['original_caption'] ?? '',
        'type': raw['original_type'] ?? 'image',
        'file_url': originalMedia,
        'image_url': originalMedia,
        'media_url': originalMedia,
        'created_at': raw['original_created_at'],
        'likes_count': raw['original_likes_count'] ?? 0,
        'comments_count': raw['original_comments_count'] ?? 0,
        'views_count': raw['original_views_count'] ?? 0,
        'user': {
          'id': raw['original_user_id'],
          'name': raw['original_user_name'] ?? 'User',
          'avatar': originalAvatar,
          'profile_pic': originalAvatar,
          'subscription_status':
              raw['original_user_subscription_status'] ?? 'inactive',
        },
        'author_subscription_status':
            raw['original_user_subscription_status'] ?? 'inactive',
      };
    }

    if (kDebugMode) {}

    final followVal = raw['is_following'] ?? raw['following'];
    normalized['is_following'] = followVal == true ||
        followVal == 1 ||
        followVal == '1' ||
        followVal == 'true';

    return normalized;
  }

  dynamic _firstNonEmptyValue(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return value;
    }
    return null;
  }

  /// Upload a story with optional music and tags metadata
  /// For images, the file should be pre-rendered with overlays
  /// For videos, music/tags are sent as metadata for future processing
  Future<void> uploadStory(
    File file, {
    String type = 'image',
    String? music,
    List<String>? tags,
    String? filterName,
    String? bgColor,
    String? textOverlays,
  }) async {
    final dio = await _ensureInitializedDio();
    // stories.php lives at server root, not under /api/v1/
    final base = dio.options.baseUrl;
    final rootUrl = base.contains('/api/') ? base.substring(0, base.indexOf('/api/') + 1) : base;
    final uri = Uri.parse('${rootUrl}stories.php');
    final prefs = await SharedPreferences.getInstance();
    final token =
        prefs.getString('auth_token') ?? prefs.getString('app_token') ?? '';

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      request.fields['type'] = type;
      if (music != null && music.isNotEmpty) request.fields['music'] = music;
      if (tags != null && tags.isNotEmpty) request.fields['tags'] = jsonEncode(tags);
      if (filterName != null && filterName.isNotEmpty) request.fields['filter_name'] = filterName;
      if (bgColor != null && bgColor.isNotEmpty) request.fields['bg_color'] = bgColor;
      if (textOverlays != null && textOverlays.isNotEmpty) request.fields['text_overlays'] = textOverlays;

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        throw Exception(
          'Story upload failed (HTTP ${streamed.statusCode}): ${body.isEmpty ? 'No response body' : body}',
        );
      }

      if (body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['status'] != 'success') {
          throw Exception('Story upload failed: ${decoded['message'] ?? body}');
        }
      }
    } catch (e) {
      throw Exception('Story upload error: $e');
    }
  }

  Future<List<dynamic>> getActiveStories() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get('/stories.php?action=active');
      if (response.statusCode == 200) {
        return response.data['stories'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- Profile & User ---

  Future<Map<String, dynamic>> getUserProfile() async {
    final dio = await _ensureInitializedDio();
    try {
      // Get current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? prefs.getString('uid') ?? '';
      if (userId.isEmpty) {
        return {};
      }

      final response = await dio.get(
        '/profile_v19.php',
        queryParameters: {'user_id': userId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }
      if (payload is Map<String, dynamic>) {
        // Server returns {status: 'success', user: {...}}
        if (payload['user'] is Map) {
          return Map<String, dynamic>.from(payload['user']);
        }
        return payload;
      }
      return {};
    } on DioException catch (_) {
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<void> updateAvatar(File imageFile) async {
    final dio = await _ensureInitializedDio();
    try {
      String fileName = imageFile.path.split('/').last;
      FormData formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          imageFile.path,
          filename: fileName,
        ),
      });
      await dio.post('/upload_avatar.php', data: formData);
    } on DioException catch (e) {
      if (kDebugMode) print('uploadAvatar error: $e');
    }
  }

  Future<void> walletDeposit(double amount) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        '/wallet.php',
        queryParameters: {'action': 'request_deposit'},
        data: {'coins': amount.toInt()},
      );
    } on DioException catch (e) {
      if (kDebugMode) print('walletDeposit error: $e');
    }
  }

  // --- Wallet + KYC V1 ---

  Future<WalletInfo> getWalletBalanceRemote() async {
    final dio = await _ensureInitializedDio();
    final response = await dio.get(
      '/wallet.php',
      queryParameters: {'action': 'balance'},
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    final data = _extractDataMap(payload);
    return WalletInfo.fromJson(data ?? payload ?? <String, dynamic>{});
  }

  Future<List<WalletTransaction>> getWalletTransactionsRemote() async {
    final dio = await _ensureInitializedDio();
    final response = await dio.get(
      '/wallet.php',
      queryParameters: {'action': 'transactions'},
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    final list = _extractDataList(payload) ??
        (payload?['transactions'] is List
            ? payload!['transactions'] as List
            : <dynamic>[]);
    return list
        .whereType<Map>()
        .map((e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<WalletSettingsModel> getWalletSettingsRemote() async {
    final dio = await _ensureInitializedDio();
    final response = await dio.get(
      '/wallet.php',
      queryParameters: {'action': 'settings'},
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    final data = _extractDataMap(payload);
    return WalletSettingsModel.fromJson(data ?? payload ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> getWalletSettings() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/wallet_settings.php',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }
      if (payload is Map<String, dynamic>) {
        final status = payload['status'];
        if (status == true || status == 'success') {
          return (payload['settings'] is Map)
              ? Map<String, dynamic>.from(payload['settings'])
              : {};
        }
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<bool> requestWalletDeposit({
    required int coins,
    File? proofFile,
  }) async {
    final dio = await _ensureInitializedDio();
    final map = <String, dynamic>{'coins': coins};
    if (proofFile != null) {
      map['proof'] = await MultipartFile.fromFile(
        proofFile.path,
        filename: proofFile.path.split('/').last,
      );
    }

    final response = await dio.post(
      '/wallet.php',
      queryParameters: {'action': 'request_deposit'},
      data: FormData.fromMap(map),
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    return _isSuccessPayload(payload);
  }

  Future<bool> requestWalletWithdraw({
    required int coins,
    File? proofFile,
  }) async {
    final dio = await _ensureInitializedDio();
    final map = <String, dynamic>{'coins': coins};
    if (proofFile != null) {
      map['proof'] = await MultipartFile.fromFile(
        proofFile.path,
        filename: proofFile.path.split('/').last,
      );
    }

    final response = await dio.post(
      '/wallet.php',
      queryParameters: {'action': 'request_withdraw'},
      data: FormData.fromMap(map),
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    return _isSuccessPayload(payload);
  }

  Future<KycStatusModel> getKycStatusRemote() async {
    final dio = await _ensureInitializedDio();
    final response = await dio.get(
      '/kyc.php',
      queryParameters: {'action': 'status'},
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data) ?? {};
    final data = _extractDataMap(payload);
    final kycData = (payload.containsKey('kyc') && payload['kyc'] is Map)
        ? Map<String, dynamic>.from(payload['kyc'])
        : (data ?? payload);

    return KycStatusModel.fromJson(kycData);
  }

  Future<KycTaskModel> getRandomKycTask({required String level}) async {
    final dio = await _ensureInitializedDio();
    final response = await dio.get(
      '/kyc.php',
      queryParameters: {'action': 'random_task', 'level': level},
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    final data = _extractDataMap(payload);
    return KycTaskModel.fromJson(
      data ?? payload ?? <String, dynamic>{},
      level: level,
    );
  }

  Future<bool> submitBasicKyc({
    required String fullName,
    required String taskId,
    required File videoFile,
  }) async {
    final dio = await _ensureInitializedDio();
    final response = await dio.post(
      '/kyc.php',
      queryParameters: {'action': 'submit_basic'},
      data: FormData.fromMap({
        'full_name': fullName,
        'task_id': taskId,
        'video': await MultipartFile.fromFile(
          videoFile.path,
          filename: videoFile.path.split('/').last,
        ),
      }),
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    return _isSuccessPayload(payload);
  }

  Future<bool> submitFullKyc({
    required String taskId,
    required File videoFile,
  }) async {
    final dio = await _ensureInitializedDio();
    final response = await dio.post(
      '/kyc.php',
      queryParameters: {'action': 'submit_full'},
      data: FormData.fromMap({
        'task_id': taskId,
        'video': await MultipartFile.fromFile(
          videoFile.path,
          filename: videoFile.path.split('/').last,
        ),
      }),
      options: Options(responseType: ResponseType.plain),
    );

    final payload = _asJsonMap(response.data);
    return _isSuccessPayload(payload);
  }

  // --- Task 2: Location update for Nearby tab (geolocator wrapper) ---------

  /// Updates user's real-time lat/lng on the backend (called every 5 min).
  /// Pushes to both update_location.php AND match_profiles lat/lng column.
  Future<void> updateUserLocation(double lat, double lng) async {
    final dio = await _ensureInitializedDio();
    try {
      // Update primary location table
      final res1 = await dio.post(
        '/update_location.php',
        data: {'lat': lat, 'lng': lng},
      );

      // Trigger nearby proximity notifications
      final res2 = await dio.post(
        '/match_profiles.php',
        queryParameters: {'action': 'update_location'},
        data: {'lat': lat, 'lng': lng},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      if (e is DioException) {}
    }
  }

  // --- Live Stream APIs ---

  Future<bool> startLive() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_live_stream.php',
        data: {'action': 'start_live'},
      );
      final json =
          (response.data is String) ? jsonDecode(response.data) : response.data;
      return json['status'] == 'success';
    } catch (e) {
      if (kDebugMode) print('[startLive] error $e');
      return false;
    }
  }

  Future<bool> endLive() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_live_stream.php',
        data: {'action': 'end_live'},
      );
      final json =
          (response.data is String) ? jsonDecode(response.data) : response.data;
      return json['status'] == 'success';
    } catch (e) {
      if (kDebugMode) print('[endLive] error $e');
      return false;
    }
  }

  Future<bool> heartbeatLive() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_live_stream.php',
        data: {'action': 'heartbeat'},
      );
      final json =
          (response.data is String) ? jsonDecode(response.data) : response.data;
      return json['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  Future<bool> inviteToLive(List<String> userIds) async {
    if (userIds.isEmpty) return true;
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'api_live_stream.php',
        data: {'action': 'invite_to_live', 'user_ids': userIds.join(',')},
      );
      final json =
          (response.data is String) ? jsonDecode(response.data) : response.data;
      return json['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> getLiveUsers() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_live_stream.php',
        queryParameters: {'action': 'get_live_users'},
      );
      final json =
          (response.data is String) ? jsonDecode(response.data) : response.data;
      if (json['status'] == 'success') {
        return json['profiles'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[getLiveUsers] error $e');
      return [];
    }
  }

  Future<List<dynamic>> getNearbyMatchProfiles({
    required String userId,
    double? lat,
    double? lng,
    String? sort,
    String? gender,
    int page = 1,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final params = <String, dynamic>{
        'action': 'nearby',
        'user_id': userId,
        'page': page,
      };
      if (lat != null) params['lat'] = lat;
      if (lng != null) params['lng'] = lng;
      if (sort != null) params['sort'] = sort;
      if (gender != null) params['gender'] = gender;

      final response = await dio.get(
        'match_profiles.php',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        // Server may return 'profiles' (list) or 'profile' (list/single)
        final data = payload['profiles'] ?? payload['profile'];
        if (data is List) return data;
        if (data is Map) return [data]; // Single profile wrapped in list
        return [];
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[getNearbyMatchProfiles] Error: $e');
      return [];
    }
  }

  Future<bool> updateLocation({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'match_profiles.php',
        data: {
          'action': 'update_location',
          'user_id': userId,
          'lat': lat,
          'lng': lng,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return (payload is Map<String, dynamic> &&
          payload['status'] == 'success');
    } catch (_) {
      return false;
    }
  }

  // --- Match Profile API ---------------------------------------------------

  /// GET ?action=feed ï¿½ paginated match cards for the 3-card carousel
  Future<List<dynamic>> getMatchFeed({int page = 1}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/match_profiles.php',
        queryParameters: {'action': 'feed', 'page': page},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return (payload['profiles'] as List<dynamic>? ?? []);
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('[getMatchFeed] Error: $e');
      return [];
    }
  }

  /// GET ?action=get_my_profile
  Future<Map<String, dynamic>> getMyMatchProfile() async {
    final dio = await _ensureInitializedDio();
    final userId = await getCurrentUserId();
    try {
      final response = await dio.get(
        '/match_profiles.php',
        queryParameters: {'action': 'get_my_profile', 'user_id': userId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      return {};
    } catch (e) {
      return {};
    }
  }

  /// POST ?action=save â€“ multipart: cover_pic, profile_pic, interests, qualities, location, age, bio, gender, income, is_visible, looking_for
  Future<void> saveMatchProfile({
    File? coverPic,
    File? profilePic,
    required List<String> interests,
    required List<String> qualities,
    required List<String> lookingFor,
    required String location,
    required String age,
    required String bio,
    required String gender,
    required String income,
    required bool isVisible,
    List<File?>? incomeProofs,
  }) async {
    final dio = await _ensureInitializedDio();
    final userId = await getCurrentUserId();

    final formMap = <String, dynamic>{
      'action': 'save',
      'user_id': userId,
      'interests': interests.join(','),
      'qualities': qualities.join(','),
      'looking_for': lookingFor.join(','),
      'location': location,
      'age': age,
      'bio': bio,
      'gender': gender,
      'income': income,
      'is_visible': isVisible ? '1' : '0',
    };

    if (coverPic != null) {
      formMap['cover_pic'] = await MultipartFile.fromFile(
        coverPic.path,
        filename: coverPic.path.split('/').last,
      );
    }
    if (profilePic != null) {
      formMap['profile_pic'] = await MultipartFile.fromFile(
        profilePic.path,
        filename: profilePic.path.split('/').last,
      );
    }

    if (incomeProofs != null) {
      for (int i = 0; i < incomeProofs.length; i++) {
        if (incomeProofs[i] != null) {
          formMap['income_proof_${i + 1}'] = await MultipartFile.fromFile(
            incomeProofs[i]!.path,
            filename: incomeProofs[i]!.path.split('/').last,
          );
        }
      }
    }

    final formData = FormData.fromMap(formMap);
    await dio.post(
      'match_profiles.php',
      data: formData,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  Future<void> cancelIncomeReview({required String userId}) async {
    final dio = await _ensureInitializedDio();
    try {
      final formData = FormData.fromMap({
        'action': 'cancel_income_review',
        'user_id': userId,
      });
      await dio.post(
        'match_profiles.php',
        data: formData,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'application/json'},
        ),
      );
    } catch (e) {}
  }

  Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? prefs.getString('uid') ?? '';
  }

  /// POST ?action=react ï¿½ record like / reject / follow
  Future<void> reactMatchProfile(dynamic toUserId, String reaction) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        '/match_profiles.php',
        queryParameters: {'action': 'react'},
        data: {'to_user': toUserId, 'reaction': reaction},
      );
    } catch (e) {}
  }

  /// POST ?action=random_call ï¿½ join queue and check for a partner
  Future<Map<String, dynamic>> startRandomCall() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/match_profiles.php',
        queryParameters: {'action': 'random_call'},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      return {'found': false};
    } catch (e) {
      return {'found': false};
    }
  }

  /// Task 3: Toggle is_visible flag in match_profiles (Profile Settings switch)
  Future<bool> updateMatchVisibility(bool visible) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        '/match_profiles.php',
        queryParameters: {'action': 'set_visibility'},
        data: {'is_visible': visible ? 1 : 0},
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('updateMatchVisibility error: $e');
      return false;
    }
  }

  /// POST ?action=cancel_call ï¿½ leave the queue
  Future<void> cancelRandomCall() async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        '/match_profiles.php',
        queryParameters: {'action': 'cancel_call'},
      );
    } catch (e) {}
  }

  // --- Account Security --------------------------------------------------

  Future<Map<String, dynamic>> changeEmail(
    String newEmail,
    String password,
  ) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/account.php',
        queryParameters: {'action': 'change_email'},
        data: {'new_email': newEmail, 'password': password},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (_isSuccessPayload(payload)) return payload!;
      throw Exception(payload?['message'] ?? 'Failed to change email');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/account.php',
        queryParameters: {'action': 'change_password'},
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (_isSuccessPayload(payload)) return payload!;
      throw Exception(payload?['message'] ?? 'Failed to change password');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  Future<List<dynamic>> getSessions() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'account.php',
        queryParameters: {'action': 'sessions'},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (payload != null) {
        final data = payload['data'] ?? payload['sessions'] ?? [];
        if (data is List) return data;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> terminateSession(dynamic sessionId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'account.php',
        queryParameters: {'action': 'terminate_session'},
        data: {'session_id': sessionId},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return _isSuccessPayload(payload);
    } catch (_) {
      return false;
    }
  }

  // --- Privacy Settings -------------------------------------------------

  Future<Map<String, dynamic>> getUserPrivacySettings() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/privacy.php',
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (payload == null) return {};
      // Unwrap 'user' key — backend returns {status: true, user: {...settings}}
      final user = payload['user'];
      if (user is Map<String, dynamic>) return user;
      // Fallback: if backend ever returns flat map, return it directly
      return payload;
    } catch (e) {
      return {};
    }
  }

  /// Returns the updated settings map on success, or null on failure.
  Future<Map<String, dynamic>?> updateUserPrivacySettings(
      Map<String, dynamic> fields) async {
    final dio = await _ensureInitializedDio();
    final intFields = fields.map((key, value) {
      if (value is bool) return MapEntry(key, value ? 1 : 0);
      return MapEntry(key, value);
    });
    try {
      final response = await dio.post(
        '/privacy.php',
        data: jsonEncode(intFields),
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final payload = _asJsonMap(response.data);
      if (_isSuccessPayload(payload)) {
        // Unwrap 'user' key — backend returns {status: true, user: {...settings}}
        final user = payload?['user'];
        if (user is Map<String, dynamic>) return user;
        return payload;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // --- Blocked Users ----------------------------------------------------

  Future<List<dynamic>> getBlockedUsers() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/blocks.php',
        queryParameters: {'action': 'list'},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (payload != null) {
        final data = payload['blocked_users'] ??
            payload['data'] ??
            payload['users'] ??
            payload['blocked'] ??
            [];
        if (data is List) return data;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // unblockUser is now defined in the user management section above (using user_actions.php)

  // --- Delete Account ---------------------------------------------------

  Future<Map<String, dynamic>> deleteAccount(String password) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/account.php',
        queryParameters: {'action': 'delete_account'},
        data: {'password': password},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (_isSuccessPayload(payload)) return payload!;
      // Throw a plain string so the UI shows a clean message without "Exception:"
      throw payload?['message'] ?? 'Failed to delete account';
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> restoreAccount(
    String email,
    String password,
  ) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/auth.php',
        queryParameters: {'action': 'restore'},
        data: {'email': email, 'password': password},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (_isSuccessPayload(payload)) return payload!;
      throw Exception(payload?['message'] ?? 'Failed to restore account');
    } on DioException catch (e) {
      throw Exception(_handleError(e));
    }
  }

  // --- Gifts --------------------------------------------------------------

  /// GET /gifts.php?action=list
  /// Returns list of available gifts with gif_url, thumb_image, coin_price, etc.
  /// Handles: {gifts:[...]}, {data:[...]}, {items:[...]}, direct [...]
  Future<List<Map<String, dynamic>>> getGifts() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/gifts.php',
        queryParameters: {'action': 'list'},
        options: Options(responseType: ResponseType.plain),
      );

      dynamic raw = response.data;
      if (raw is String) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {
          return [];
        }
      }

      // Shape: direct List [...]
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Shape: Map with known list keys
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        for (final key in ['gifts', 'data', 'items']) {
          if (map[key] is List) {
            return (map[key] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
        // Fallback: try _extractDataList helper
        final dataList = _extractDataList(map);
        if (dataList != null) {
          return dataList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /gifts.php?action=send
  /// Body: { gift_id, to_user_id, context_type, context_id, message }
  /// Returns response map with status, new balance, etc.
  Future<Map<String, dynamic>> sendGift({
    required dynamic giftId,
    required String toUserId,
    required String contextType,
    required dynamic contextId,
    String? message,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final formFields = <String, dynamic>{
        'gift_id': giftId.toString(),
        'to_user_id': toUserId,
        'context_type': contextType,
        'context_id': contextId.toString(),
      };
      if (message != null && message.trim().isNotEmpty) {
        formFields['message'] = message.trim();
      }
      final response = await dio.post(
        '/gifts.php',
        queryParameters: {'action': 'send'},
        data: FormData.fromMap(formFields),
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && _isSuccessPayload(payload)) {
        return payload;
      }
      return payload ?? {'status': 'error', 'message': 'Unknown error'};
    } on DioException catch (e) {
      final msg = _handleError(e);
      return {'status': 'error', 'message': msg};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// GET /gifts.php?action=received&user_id=X
  /// Returns public gift shelf for any user's profile — no auth required.
  Future<List<Map<String, dynamic>>> fetchReceivedGifts(String userId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/gifts.php',
        queryParameters: {'action': 'received', 'user_id': userId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic raw = response.data;
      if (raw is String) { try { raw = jsonDecode(raw); } catch (_) { return []; } }
      if (raw is Map) {
        final list = (raw['gifts'] ?? raw['data'] ?? raw['items']);
        if (list is List) {
          return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      return [];
    } catch (_) { return []; }
  }

  /// GET /gifts.php?action=wallet
  /// Returns a list of gifts the user has received.
  Future<List<WalletGiftItem>> fetchWalletGifts() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/gifts.php',
        queryParameters: {'action': 'wallet'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && _isSuccessPayload(payload)) {
        final giftsRaw = payload['gifts'] as List?;
        if (giftsRaw != null) {
          return giftsRaw
              .whereType<Map<String, dynamic>>()
              .map((e) => WalletGiftItem.fromJson(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /gifts.php?action=sell
  /// Sells a specific quantity of a received gift for coins.
  Future<Map<String, dynamic>> sellWalletGift({
    required dynamic giftId,
    required int qty,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/gifts.php',
        queryParameters: {'action': 'sell'},
        data: {'gift_id': giftId, 'qty': qty},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && _isSuccessPayload(payload)) {
        return payload;
      }
      return payload ?? {'status': false, 'message': 'Unknown error'};
    } on DioException catch (e) {
      final msg = _handleError(e);
      return {'status': false, 'message': msg};
    } catch (e) {
      return {'status': false, 'message': e.toString()};
    }
  }

  /// POST /withdraw.php
  /// Requests a withdrawal of coins.
  Future<Map<String, dynamic>> requestWithdrawal({
    required int coins,
    required String paymentMethod,
    required String paymentDetails,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        '/withdraw.php',
        data: {
          'coins': coins,
          'payment_method': paymentMethod,
          'payment_details': paymentDetails,
        },
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && _isSuccessPayload(payload)) {
        return payload;
      }
      return payload ?? {'status': false, 'message': 'Unknown error'};
    } on DioException catch (e) {
      final msg = _handleError(e);
      return {'status': false, 'message': msg};
    } catch (e) {
      return {'status': false, 'message': e.toString()};
    }
  }

  /// GET /withdraw.php
  /// Fetches withdrawal history for the user.
  Future<List<Map<String, dynamic>>> fetchWithdrawals() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/withdraw.php',
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      final dataList = _extractDataList(payload);
      if (dataList != null) {
        return dataList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// GET /withdraw_methods.php
  /// Fetches available withdrawal methods and global settings from admin
  Future<Map<String, dynamic>> fetchWithdrawMethods() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/withdraw_methods.php',
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      if (payload != null && payload['status'] == true) {
        return payload;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// GET /gift_notifications.php?action=post_gifts&context_type=X&context_id=Y
  /// Returns list of gift transactions for a specific post/reel.
  Future<List<Map<String, dynamic>>> fetchPostGifts({
    required String contextType,
    required dynamic contextId,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/gift_notifications.php',
        queryParameters: {
          'action': 'post_gifts',
          'context_type': contextType,
          'context_id': contextId,
        },
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      final dataList = _extractDataList(payload);
      if (dataList != null) {
        return dataList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// GET /gift_notifications.php?action=list
  /// Returns list of all gift notifications for the current user.
  Future<List<Map<String, dynamic>>> fetchGiftNotifications() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        '/gift_notifications.php',
        queryParameters: {'action': 'list'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      final dataList = _extractDataList(payload);
      if (dataList != null) {
        return dataList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// GET /app_notifications.php
  /// Fetches live system/admin push notifications
  Future<List<Map<String, dynamic>>> fetchAppNotifications() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_notifications.php',
        queryParameters: {'action': 'list'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && payload['status'] == true) {
        final data = payload['data'] as List?;
        if (data != null) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /app_notifications.php
  /// Marks a specific system notification as read
  Future<void> markAppNotificationRead(int notificationId) async {
    final dio = await _ensureInitializedDio();
    try {
      await dio.post(
        'api_notifications.php',
        data: {'action': 'mark_read', 'id': notificationId},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {}
  }

  // --- Trending / Hashtags / Recommendations --------------------------------

  /// GET /api_trending.php?action=posts|reels|hashtags|sounds
  /// [period]: 24h | 7d | 30d | all
  Future<Map<String, dynamic>> getTrending({
    String action = 'posts',
    String period = '24h',
    int limit = 30,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_trending.php',
        queryParameters: {'action': action, 'period': period, 'limit': limit},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return payload ?? {};
    } catch (e) {
      if (kDebugMode) print('getTrending error: $e');
      return {};
    }
  }

  /// GET /api_hashtags.php?action=search&q=<tag>
  Future<Map<String, dynamic>> searchHashtag(String tag,
      {int page = 1, int limit = 30}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_hashtags.php',
        queryParameters: {
          'action': 'search',
          'q': tag,
          'page': page,
          'limit': limit
        },
        options: Options(responseType: ResponseType.plain),
      );
      return _asJsonMap(response.data) ?? {};
    } catch (e) {
      return {};
    }
  }

  /// GET /api_hashtags.php?action=related&tag=<tag>
  Future<List<dynamic>> getRelatedHashtags(String tag) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_hashtags.php',
        queryParameters: {'action': 'related', 'tag': tag},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return (payload?['related'] as List?) ?? [];
    } catch (e) {
      return [];
    }
  }

  /// GET /api_recommendations.php?action=users — "People you may know"
  Future<List<dynamic>> getRecommendedUsers({int limit = 20}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_recommendations.php',
        queryParameters: {'action': 'users', 'limit': limit},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return (payload?['users'] as List?) ?? [];
    } catch (e) {
      return [];
    }
  }

  /// GET /api_recommendations.php?action=posts — interest-ranked posts
  Future<List<dynamic>> getRecommendedPosts({int limit = 20}) async {
    final dio = await _ensureInitializedDio();
    try {
      String interests = '';
      try {
        interests = await _engagementTracker.interestParam();
      } catch (_) {}
      final response = await dio.get(
        'api_recommendations.php',
        queryParameters: {
          'action': 'posts',
          'limit': limit,
          if (interests.isNotEmpty) 'interests': interests,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return (payload?['posts'] as List?) ?? [];
    } catch (e) {
      return [];
    }
  }

  /// GET /api_recommendations.php?action=creators — top creators to follow
  Future<List<dynamic>> getRecommendedCreators({int limit = 20}) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'api_recommendations.php',
        queryParameters: {'action': 'creators', 'limit': limit},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asJsonMap(response.data);
      return (payload?['creators'] as List?) ?? [];
    } catch (e) {
      return [];
    }
  }

  /// GET /user_quality_engine.php?user_id=X
  /// Returns the dynamically calculated rating and total proposals.
  Future<Map<String, dynamic>> fetchUserQuality(dynamic userId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'user_quality_engine.php',
        queryParameters: {'user_id': userId},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _asJsonMap(response.data);
      if (payload != null && _isSuccessPayload(payload)) {
        return payload;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  // --- Session helpers (used by 401/403 interceptor) -----------------------

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_token');
      await prefs.remove('auth_token');
      await prefs.remove('user_id');
      await prefs.remove('user_id_int');
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      await prefs.remove('is_guest');
      await prefs.remove('cached_profile');
      _cachedToken = null;
    } catch (_) {}

    try {
      // Use addPostFrameCallback to avoid using BuildContext across async gap
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        try {
          Provider.of<AuthProvider>(ctx, listen: false).logout();
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _navigateToLogin() {
    try {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } catch (_) {}
  }

  // --- Error Helper --------------------------------------------------------
  String _handleError(DioException e) {
    if (e.response != null) {
      var data = e.response?.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      return 'Server error: ${e.response?.statusCode}';
    } else {
      return 'Network error: ${e.message}';
    }
  }

  Map<String, dynamic>? _asJsonMap(dynamic raw) {
    try {
      dynamic value = raw;
      if (value is String) value = jsonDecode(value);
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isSuccessPayload(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final status = payload['status'];
    if (status != null) {
      final s = status.toString().toLowerCase();
      if (s == 'success' || s == 'ok' || status == true || status == 1) {
        return true;
      }
    }
    final success = payload['success'];
    return success == true || success == 1;
  }

  Map<String, dynamic>? _extractDataMap(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  List<dynamic>? _extractDataList(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final data = payload['data'];
    if (data is List) return data;
    return null;
  }

  // -----------------------------------------------------------------
  // COLLECTIONS
  // -----------------------------------------------------------------

  /// GET /collections.php?action=posts&collection_id=X
  /// Returns list of post maps belonging to this collection.
  Future<List<Map<String, dynamic>>> getCollectionPosts(
    String collectionId,
  ) async {
    final dio = await _ensureInitializedDio();
    final baseUrl = await AppEnv.getBaseUrlAsync();
    try {
      final response = await dio.get(
        'collections.php?action=posts&collection_id=$collectionId',
        options: Options(responseType: ResponseType.plain),
      );
      dynamic parsed = response.data;
      if (parsed is String) parsed = jsonDecode(parsed);
      if (parsed is! Map) return [];
      final posts = parsed['posts'] ?? parsed['data'] ?? parsed['items'];
      if (posts is List) {
        return posts.whereType<Map>().map((e) {
          final m = Map<String, dynamic>.from(e);
          final fileUrl = normalizeMediaUrl(
            m['file_url'] ?? m['media_url'],
            baseUrl: baseUrl,
          );
          final thumbRaw = (m['thumbnail_url'] ?? '').toString().trim();
          final thumb = thumbRaw.isNotEmpty
              ? normalizeMediaUrl(thumbRaw, baseUrl: baseUrl)
              : '';
          final type = (m['type'] ?? '').toString().toLowerCase();
          final isVideo = type == 'video' || type == 'reel';
          m['file_url'] = fileUrl;
          m['media_url'] = fileUrl;
          m['thumbnail_url'] =
              thumb.isNotEmpty ? thumb : (isVideo ? '' : fileUrl);
          return m;
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /collections.php action=add_post — add a post to a collection.
  Future<bool> addPostToCollection({
    required String collectionId,
    required String postId,
  }) async {
    try {
      final dio = await _ensureInitializedDio();
      final response = await dio.post(
        'collections.php',
        data: FormData.fromMap({
          'action': 'add_post',
          'collection_id': collectionId,
          'post_id': postId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      dynamic parsed = response.data;
      if (parsed is String) parsed = jsonDecode(parsed);
      return parsed is Map &&
          (parsed['status'] == 'success' || parsed['status'] == true);
    } catch (e) {
      if (kDebugMode) print('addPostToCollection error: $e');
      return false;
    }
  }

  /// POST /collections.php?action=view&collection_id=X (fire-and-forget)
  Future<bool> recordCollectionView(String collectionId) async {
    try {
      final dio = await _ensureInitializedDio();
      await dio.post(
        'collections.php?action=view&collection_id=$collectionId',
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('recordCollectionView error: $e');
      return false;
    }
  }

  Future<bool> deleteCollection(String collectionId) async {
    try {
      final dio = await _ensureInitializedDio();
      final response = await dio.post(
        'collections.php',
        data: FormData.fromMap({
          'action': 'delete',
          'collection_id': collectionId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      dynamic parsed = response.data;
      if (parsed is String) parsed = jsonDecode(parsed);
      return parsed is Map && parsed['status'] == 'success';
    } catch (e) {
      if (kDebugMode) print('deleteCollection error: $e');
      return false;
    }
  }

  // --- Pay-Per-Minute Setup ---

  /// Creator-side: terminate one of my active subscribers. Server allows
  /// either the subscriber themselves OR the plan's creator to flip status.
  Future<Map<String, dynamic>> terminateSubscriber(int subscriptionId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'subscriptions.php?action=terminate_subscriber',
        data: {'subscription_id': subscriptionId},
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      return {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      dynamic payload = e.response?.data;
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {}
      }
      if (payload is Map<String, dynamic>) return payload;
      return {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  Future<bool> updatePayPerMinEnabled(bool enabled) async {
    final dio = await _ensureInitializedDio();
    try {
      FormData formData = FormData.fromMap({
        'pay_per_min_enabled': enabled ? 1 : 0,
      });
      final response = await dio.post(
        'update_profile.php',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      return (payload is Map<String, dynamic> &&
          payload['status'] == 'success');
    } catch (_) {
      throw Exception('Failed to update pay-per-minute status');
    }
  }

  /// Save the PPM 'charge friends' toggle. When OFF (default), mutual
  /// friends bypass PPM; when ON, even friends must start a paid session.
  Future<bool> updatePpmChargeFriends(bool enabled) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'update_profile.php',
        data: FormData.fromMap({'ppm_charge_friends': enabled ? 1 : 0}),
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          responseType: ResponseType.plain,
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> &&
          payload['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  /// Set or clear the per-user PPM override. force=true → this specific
  /// target user must start a paid session even if they're a friend.
  /// force=false → remove the override; normal rules apply.
  Future<Map<String, dynamic>> setPpmOverride({
    required int targetUserId,
    required bool force,
  }) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post(
        'chat.php?action=ppm_override_set',
        data: FormData.fromMap({
          'target_user_id': targetUserId,
          'force': force ? 1 : 0,
        }),
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          responseType: ResponseType.plain,
        ),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) return payload;
      return {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      dynamic payload = e.response?.data;
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {}
      }
      if (payload is Map<String, dynamic>) return payload;
      return {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  /// Query whether a per-user PPM override exists for [targetUserId].
  Future<bool> getPpmOverride(int targetUserId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get(
        'chat.php',
        queryParameters: {
          'action': 'ppm_override_status',
          'target_user_id': targetUserId,
        },
        options: Options(responseType: ResponseType.plain),
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload is Map<String, dynamic>) {
        final f = payload['force'];
        return f == 1 || f == '1' || f == true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> updatePayPerMinRate(double rate) async {
    final dio = await _ensureInitializedDio();
    try {
      FormData formData = FormData.fromMap({'pay_per_min_rate': rate});
      final response = await dio.post(
        'update_profile.php',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      return (payload is Map<String, dynamic> &&
          payload['status'] == 'success');
    } catch (_) {
      throw Exception('Failed to update pay-per-minute rate');
    }
  }

  /// GET api_username.php — returns {username, can_change, can_change_at}
  Future<Map<String, dynamic>> getUsernameInfo() async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.get('api_username.php');
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> ? payload : {};
    } catch (_) {
      return {};
    }
  }

  /// POST api_username.php — action: 'check' | 'update'
  Future<Map<String, dynamic>> postUsername(Map<String, dynamic> body) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post('api_username.php', data: body);
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> ? payload : {};
    } catch (e) {
      return {'success': false, 'msg': e.toString()};
    }
  }

  // ── Onboarding helpers ────────────────────────────────────────────────────

  /// Upload profile picture via multipart. Returns the server response map.
  Future<Map<String, dynamic>> uploadProfilePicture(File imageFile) async {
    final dio = await _ensureInitializedDio();
    final formData = FormData.fromMap({
      'action': 'update_profile_pic',
      'profile_pic': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'avatar.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final response = await dio.post(
      'profile_v19.php',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    dynamic payload = response.data;
    if (payload is String) payload = jsonDecode(payload);
    return payload is Map<String, dynamic> ? payload : {};
  }

  /// Upload cover photo via multipart. Returns the server response map.
  Future<Map<String, dynamic>> uploadCoverPhoto(File imageFile) async {
    final dio = await _ensureInitializedDio();
    final formData = FormData.fromMap({
      'action': 'update_cover_photo',
      'cover_photo': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'cover.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final response = await dio.post(
      'profile_v19.php',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    dynamic payload = response.data;
    if (payload is String) payload = jsonDecode(payload);
    return payload is Map<String, dynamic> ? payload : {};
  }

  /// POST profile_v19.php — update arbitrary profile fields (name, username,
  /// gender, location, age, is_match_visible, etc.) as JSON.
  Future<Map<String, dynamic>> updateProfileFields(
      Map<String, dynamic> fields) async {
    final dio = await _ensureInitializedDio();
    try {
      final body = {'action': 'update_profile', ...fields};
      final response = await dio.post('profile_v19.php', data: body);
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      return payload is Map<String, dynamic> ? payload : {};
    } catch (e) {
      return {'success': false, 'msg': e.toString()};
    }
  }
}
