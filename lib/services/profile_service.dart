import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/models/collection.dart';
import 'package:dio/dio.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/services/settings_store.dart';

/// ProfileService handles profile data with local caching and API sync
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  static ProfileService get instance => _instance;

  /// Check if a status value indicates success (handles bool, int, String).
  static bool _isStatusOk(dynamic status) {
    if (status == null) return false;
    if (status is bool) return status;
    if (status is int) return status == 1;
    final s = status.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s.startsWith('success') || s == 'ok';
  }

  /// Converts a DioException into a user-friendly message.
  static String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Could not connect to server. Please check your internet connection and try again.';
      case DioExceptionType.badResponse:
        final msg = _extractErrorMessage(e.response?.data);
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Server returned an error (${e.response?.statusCode ?? 'unknown'}).';
      default:
        final msg = _extractErrorMessage(e.response?.data);
        return msg ?? 'Network error. Please try again.';
    }
  }

  /// Extract error message from a Dio response body.
  static String? _extractErrorMessage(dynamic data) {
    if (data == null) return null;
    dynamic parsed = data;
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return parsed;
      }
    }
    if (parsed is Map) {
      return (parsed['message'] ?? parsed['error'] ?? parsed['msg'])
          ?.toString();
    }
    return null;
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
        'Connection': 'close',
      },
      persistentConnection: false,
    ),
  );

  // Cache keys
  static const String _profileKey = 'cached_profile';
  static const String _collectionsKey = 'cached_collections';
  String? _lastCollectionCreateError;
  String? get lastCollectionCreateError => _lastCollectionCreateError;

  UserProfile? _cachedProfile;
  final Map<String, Future<UserProfile>> _inFlightProfileRequests = {};
  final ValueNotifier<UserProfile?> currentProfileNotifier =
      ValueNotifier<UserProfile?>(null);

  void _setCurrentProfile(UserProfile profile) {
    _cachedProfile = profile;
    currentProfileNotifier.value = profile;
  }

  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    return (userId == null || userId.isEmpty) ? null : userId;
  }

  Future<UserProfile?> getCachedProfile() async {
    if (_cachedProfile != null) return _cachedProfile;
    final prefs = await SharedPreferences.getInstance();
    final cachedProfile = prefs.getString(_profileKey);
    if (cachedProfile == null || cachedProfile.isEmpty) return null;
    final json = jsonDecode(cachedProfile) as Map<String, dynamic>;
    final profile = UserProfile.fromJson(json);
    _setCurrentProfile(profile);
    return profile;
  }

  Future<UserProfile?> getCachedOrFetchCurrentUser() async {
    final cached = await getCachedProfile();
    if (cached != null) {
      return cached;
    }
    try {
      return await getMyProfile(forceRefresh: true);
    } catch (_) {
      return null;
    }
  }

  /// Get the current user's profile
  /// First tries SharedPreferences cache (unless forceRefresh), then API.
  Future<UserProfile> getMyProfile({
    bool forceRefresh = false,
    String? userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!forceRefresh) {
        final cached = await getCachedProfile();
        if (cached != null) {
          return cached;
        }
      }

      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      if (token == null || token.isEmpty) {
        throw Exception('Not logged in. Please sign in again.');
      }

      final resolvedUserId = userId ?? prefs.getString('user_id');
      if (resolvedUserId == null || resolvedUserId.isEmpty) {
        throw Exception('user_id missing for profile fetch');
      }

      final existingRequest = _inFlightProfileRequests[resolvedUserId];
      if (existingRequest != null) {
        if (kDebugMode) {}
        return await existingRequest;
      }

      final requestFuture = () async {
        final baseUrl = await AppEnv.getBaseUrlAsync();
        final url = '${baseUrl}profile_v19.php?user_id=$resolvedUserId';

        try {
          final response = await _dio.get(
            url,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json, text/plain, */*',
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
                'Connection': 'close',
              },
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          );
          final statusCode = response.statusCode ?? 0;
          final body = response.data?.toString() ?? '';

          // Guard: reject non-200 or empty body before attempting JSON parse
          if (statusCode != 200 || body.trim().isEmpty) {
            throw Exception(
              'Profile API error: HTTP $statusCode body=${body.length > 200 ? body.substring(0, 200) : body}',
            );
          }

          dynamic payload = response.data;
          if (payload is String) payload = jsonDecode(payload);

          if (payload is Map<String, dynamic> &&
              _isStatusOk(payload['status'])) {
            // Prefer 'user' key, fallback to 'data'
            final userData = payload['user'] ?? payload['data'];
            if (userData is Map) {
              final profile = UserProfile.fromJson(
                Map<String, dynamic>.from(userData),
              );
              await cacheProfile(profile);
              return profile;
            }
          }

          // Extract backend error message
          final backendMsg =
              (payload is Map ? payload['message'] : null)?.toString() ??
                  'Invalid profile data from API.';
          throw Exception(backendMsg);
        } on DioException catch (e) {
          throw Exception(_friendlyDioError(e));
        }
      }();

      _inFlightProfileRequests[resolvedUserId] = requestFuture;

      try {
        return await requestFuture;
      } finally {
        if (identical(
          _inFlightProfileRequests[resolvedUserId],
          requestFuture,
        )) {
          _inFlightProfileRequests.remove(resolvedUserId);
        }
      }
    } catch (e) {
      if (!forceRefresh) {
        try {
          final cached = await getCachedProfile();
          if (cached != null) {
            return cached;
          }
        } catch (_) {}
      }
      throw Exception('Failed to load profile: $e');
    }
  }

  /// Cache profile to SharedPreferences
  Future<void> cacheProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    _setCurrentProfile(profile);

    // Sync KYC status locally for UI components using SettingsStore to ensure
    // 'approved' is mapped to 'verified' consistently.
    if (profile.kycStatus.isNotEmpty) {
      try {
        final loveVibeProStore = await SettingsStore.getInstance();
        await loveVibeProStore.setKycStatus(profile.kycStatus);
      } catch (e) {
        // Fallback to raw if store isn't ready
        await prefs.setString('kyc_status', profile.kycStatus);
      }
    } else {}

    // Sync subscription status locally for UI components
    if (profile.subscriptionStatus.isNotEmpty) {
      try {
        final loveVibeProStore = await SettingsStore.getInstance();
        await loveVibeProStore
            .setSubscriptionStatus(profile.subscriptionStatus);
      } catch (e) {}
    }

    final avatarUrl =
        profile.avatar.isNotEmpty ? profile.avatar : profile.profilePicUrl;
  }

  Future<void> clearCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    _cachedProfile = null;
    currentProfileNotifier.value = null;
  }

  Future<UserProfile> _fetchUserProfileFromEndpoint({
    required String endpoint,
    required String userId,
    required String token,
  }) async {
    final response = await _dio.get(
      endpoint,
      queryParameters: {'user_id': userId},
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json, text/plain, */*',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
          'Connection': 'close',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    final body = response.data?.toString() ?? '';
    final trimmedBody = body.trim();

    if (statusCode != 200 || trimmedBody.isEmpty) {
      throw Exception(
        'Profile API error: HTTP $statusCode body=${body.length > 200 ? body.substring(0, 200) : body}',
      );
    }

    if (trimmedBody.startsWith('<!DOCTYPE html') ||
        trimmedBody.startsWith('<html')) {
      throw Exception('Profile API returned HTML instead of JSON');
    }

    dynamic payload = response.data;
    if (payload is String) {
      payload = jsonDecode(payload);
    }

    if (payload is List) {
      payload = <String, dynamic>{'data': payload};
    }

    if (payload is! Map) {
      throw Exception(
        'Unexpected user profile response type: ${payload.runtimeType}',
      );
    }

    final payloadMap = Map<String, dynamic>.from(payload);

    Map<String, dynamic>? userData;
    if (payloadMap['user'] is Map) {
      userData = Map<String, dynamic>.from(payloadMap['user']);
    } else if (payloadMap['data'] is Map) {
      final dataMap = Map<String, dynamic>.from(payloadMap['data']);
      if (dataMap['user'] is Map) {
        userData = Map<String, dynamic>.from(dataMap['user']);
      } else {
        userData = dataMap;
      }
    }

    if (_isStatusOk(payloadMap['status']) && userData != null) {
      final socialLinks = userData['social_links'];
      if (socialLinks == null || socialLinks is List) {
        userData['social_links'] = <String, dynamic>{};
      } else if (socialLinks is Map) {
        userData['social_links'] = Map<String, dynamic>.from(
          socialLinks.map((key, value) => MapEntry('$key', value)),
        );
      } else {
        userData['social_links'] = <String, dynamic>{};
      }

      return UserProfile.fromJson(userData);
    }

    final backendMsg = payloadMap['message']?.toString() ??
        'Invalid user profile data from API.';
    throw Exception(backendMsg);
  }

  /// Get another user's profile by ID
  /// This is used when viewing other users' profiles
  Future<UserProfile> getUserProfile(String userId,
      {bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      if (token == null) {
        throw Exception('Authentication token not found.');
      }

      final baseUrl = await AppEnv.getBaseUrlAsync();
      final primaryEndpoint = '${baseUrl}profile_v19.php';
      final fallbackEndpoint = '${baseUrl}profile.php';

      try {
        return await _fetchUserProfileFromEndpoint(
          endpoint: primaryEndpoint,
          userId: userId,
          token: token,
        );
      } catch (primaryError) {
        try {
          return await _fetchUserProfileFromEndpoint(
            endpoint: fallbackEndpoint,
            userId: userId,
            token: token,
          );
        } catch (_) {
          rethrow;
        }
      }
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    } catch (e) {
      throw Exception('Failed to load user profile: $e');
    }
  }

  /// Update profile fields
  Future<void> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? location,
    String? avatar,
    String? cover,
    Map<String, String>? socialLinks,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      final userId = prefs.getString('user_id');
      if (token == null || userId == null || userId.isEmpty) {
        throw Exception(
          'Authentication token or user_id not found for profile update.',
        );
      }

      final baseUrl = await AppEnv.getBaseUrlAsync();
      final endpoint = '${baseUrl}profile.php';

      final payload = <String, dynamic>{
        'user_id': userId,
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
        if (location != null) 'location': location,
        if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
        if (cover != null && cover.isNotEmpty) 'cover': cover,
        if (socialLinks != null) 'social_links': socialLinks,
      };

      try {
        final response = await _dio.post(
          endpoint,
          data: payload,
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        );

        final statusCode = response.statusCode ?? 0;
        dynamic body = response.data;
        if (body is String && body.isNotEmpty) {
          try {
            body = jsonDecode(body);
          } catch (_) {
            // body is plain text — treat as error message
            throw Exception(body.toString().length > 200
                ? body.toString().substring(0, 200)
                : body.toString());
          }
        }

        if (body is Map<String, dynamic> && body['status'] == 'success') {
          final updatedData = body['data'] ?? body['user'];
          if (updatedData is Map) {
            try {
              await cacheProfile(
                UserProfile.fromJson(Map<String, dynamic>.from(updatedData)),
              );
            } catch (_) {}
          }
          return;
        }

        // Extract a meaningful error message from the response
        final serverMsg = body is Map
            ? (body['message'] ?? body['error'] ?? body['msg'])?.toString()
            : null;
        final msg = serverMsg ??
            (statusCode != 200
                ? 'Server returned HTTP $statusCode'
                : 'Profile update failed');
        throw Exception(msg);
      } on DioException catch (e) {
        final msg = _extractErrorMessage(e.response?.data) ?? e.message;
        throw Exception('Profile API error: $msg');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Upload profile avatar
  Future<String?> uploadAvatar(File imageFile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token missing for avatar upload');
      }

      final userId = prefs.getString('user_id');
      final userIdInt = int.tryParse(userId ?? '');
      if (userIdInt == null) {
        throw Exception('Invalid user_id for avatar upload');
      }

      final baseUrl = await AppEnv.getBaseUrlAsync();
      final uploadUrl = "${baseUrl}upload_avatar.php";

      final fileName = imageFile.path.split('/').last;
      final formData = FormData.fromMap({
        'user_id': userIdInt,
        'avatar': await MultipartFile.fromFile(
          imageFile.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post(
        uploadUrl,
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
        ),
      );

      dynamic payload = response.data;
      if (payload is String && payload.isNotEmpty) {
        payload = jsonDecode(payload);
      }

      if (payload is Map<String, dynamic>) {
      } else {}

      if (response.statusCode == 200 &&
          payload is Map<String, dynamic> &&
          payload['status'] == 'success') {
        final url = payload['url']?.toString();
        if (url == null || url.isEmpty) {
          throw Exception('Avatar upload succeeded but url is missing');
        }

        // Update cached profile with new avatar URL
        final currentProfile = await getCachedProfile();
        if (currentProfile != null) {
          await cacheProfile(
            currentProfile.copyWith(avatar: url, profilePicUrl: url),
          );
        }
        return url;
      }

      throw Exception("Avatar upload failed");
    } catch (e) {
      rethrow;
    }
  }

  /// Upload cover photo
  Future<String?> uploadCover(File imageFile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');

      if (token == null) return null; // Or throw error

      final baseUrl = await AppEnv.getBaseUrlAsync();
      final uploadUrl = '${baseUrl}upload_cover.php';

      final fileName = imageFile.path.split('/').last;
      final formData = FormData.fromMap({
        'cover': await MultipartFile.fromFile(
          imageFile.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post(
        uploadUrl,
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String && payload.isNotEmpty) {
        payload = jsonDecode(payload);
      }

      if (payload is Map<String, dynamic> && payload['url'] != null) {
        final uploadedCoverUrl = payload['url'].toString();
        final currentProfile = await getCachedProfile();
        if (currentProfile != null) {
          await cacheProfile(
            currentProfile.copyWith(
              cover: uploadedCoverUrl,
              coverPicUrl: uploadedCoverUrl,
            ),
          );
        }
        return uploadedCoverUrl;
      }

      return null; // Or throw error
    } on DioException {
      return null;
    } catch (e) {
      return null; // Or throw error
    }
  }

  // ——————————————————————————————————————————————————————————————————————————
  // COLLECTIONS - Local persistence with SharedPreferences
  // ——————————————————————————————————————————————————————————————————————————

  /// Get collections for a user.
  /// If [userId] is null, uses the authenticated user from the token.
  Future<List<Collection>> getCollections({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_token') ?? prefs.getString('auth_token') ?? '';
      final baseUrl = await AppEnv.getBaseUrlAsync();

      // Always pass user_id so the backend can skip auth for public reads
      final uid = userId ?? prefs.getString('user_id') ?? prefs.getString('uid') ?? '';

      if (uid.isEmpty && token.isEmpty) {
        return await _loadCachedCollections();
      }

      final Map<String, dynamic> queryParams = {'action': 'get_all'};
      if (uid.isNotEmpty) queryParams['user_id'] = uid;

      final Map<String, dynamic> reqHeaders = token.isNotEmpty
          ? {'Authorization': 'Bearer $token'}
          : {};

      final response = await _dio.get(
        '${baseUrl}collections.php',
        queryParameters: queryParams,
        options: Options(headers: reqHeaders, responseType: ResponseType.plain),
      );

      dynamic payload = response.data;
      if (payload is String && payload.isNotEmpty) {
        payload = jsonDecode(payload);
      }

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        final raw = (payload['collections'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final list = raw.map((e) => _normalizeCollection(e, baseUrl)).toList();

        await _cacheCollections(list);
        return list;
      }

      return await _loadCachedCollections();
    } catch (e) {
      return await _loadCachedCollections();
    }
  }

  Future<List<Collection>> _loadCachedCollections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_collectionsKey);
      if (cached != null) {
        final List<dynamic> jsonList = jsonDecode(cached);
        return jsonList
            .whereType<Map>()
            .map((j) => Collection.fromJson(Map<String, dynamic>.from(j)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Add a new collection
  Future<Collection?> addCollection(
    String title, {
    String? coverUrl,
    File? coverFile,
  }) async {
    _lastCollectionCreateError = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      final userIdRaw = prefs.getString('user_id');
      final int? userIdInt = int.tryParse(userIdRaw ?? '');
      final String? userIdStr =
          (userIdRaw != null && userIdRaw.isNotEmpty) ? userIdRaw : null;
      if (token == null || token.isEmpty) {
        _lastCollectionCreateError = 'Authentication token missing';
        return null;
      }

      final baseUrl = await AppEnv.getBaseUrlAsync();
      final endpoint = '${baseUrl}collections.php';

      final map = <String, dynamic>{
        'action': 'create',
        'title': title.trim(),
        'token': token, // fallback for servers where Authorization header is stripped
        if (userIdInt != null) 'user_id': userIdInt,
        if (userIdInt == null && userIdStr != null) 'user_id': userIdStr,
        if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
      };

      if (coverFile != null) {
        map['cover'] = await MultipartFile.fromFile(
          coverFile.path,
          filename: coverFile.path.split('/').last,
        );
      }

      final response = await _dio.post(
        endpoint,
        data: FormData.fromMap(map),
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String && payload.isNotEmpty) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {}
      }

      final isSuccess = payload is Map<String, dynamic> &&
          (payload['status'] == 'success' || payload['success'] == true);

      if (isSuccess) {
        final rawCollection = payload['collection'] is Map
            ? Map<String, dynamic>.from(payload['collection'])
            : <String, dynamic>{
                'id': payload['collection_id'],
                'name': title,
                'cover_url': coverUrl,
                'item_count': 0,
                'created_at': DateTime.now().toIso8601String(),
              };

        final created = _normalizeCollection(rawCollection, baseUrl);

        // Refresh collections cache after create success
        await getCollections(userId: userIdStr);

        _lastCollectionCreateError = null;
        if (kDebugMode) {}

        return created;
      }

      if (payload is Map<String, dynamic>) {
        _lastCollectionCreateError = payload['message']?.toString() ??
            payload['error']?.toString() ??
            'Unknown collection create error';
      } else {
        _lastCollectionCreateError = 'Unexpected response format';
      }

      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = e.message;
      _lastCollectionCreateError =
          'status=$status, message=${message ?? 'request failed'}';

      return null;
    } catch (e) {
      _lastCollectionCreateError = e.toString();
      return null;
    }
  }

  Collection _normalizeCollection(Map<String, dynamic> raw, String baseUrl) {
    final normalized = Map<String, dynamic>.from(raw);
    normalized['title'] = raw['title'] ?? raw['name'];

    final cover = normalizeMediaUrl(
      raw['cover_url'] ?? raw['cover_thumb'] ?? raw['cover'],
      baseUrl: baseUrl,
      folder: 'collections',
    );
    normalized['cover_url'] = cover;
    normalized['cover_thumb'] = cover;

    return Collection.fromJson(normalized);
  }

  /// Delete a collection
  Future<bool> deleteCollection(String collectionId) async {
    try {
      final baseUrl = await AppEnv.getBaseUrlAsync();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_token') ?? prefs.getString('auth_token') ?? '';
      final headers = token.isNotEmpty
          ? <String, dynamic>{'Authorization': 'Bearer $token'}
          : <String, dynamic>{};
      final response = await _dio.post(
        '${baseUrl}collections.php',
        data: FormData.fromMap({
          'action': 'delete',
          'collection_id': collectionId,
        }),
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      dynamic parsed = response.data;
      if (parsed is String) parsed = jsonDecode(parsed);
      if (parsed is! Map || parsed['status'] != 'success') return false;
      final collections = await _loadCachedCollections();
      collections.removeWhere((c) => c.id == collectionId);
      await _cacheCollections(collections);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Rename a collection
  Future<bool> renameCollection(String collectionId, String newTitle) async {
    try {
      final collections = await getCollections();
      final index = collections.indexWhere((c) => c.id == collectionId);

      if (index >= 0) {
        collections[index] = collections[index].copyWith(title: newTitle);
        await _cacheCollections(collections);
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _cacheCollections(List<Collection> collections) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = collections.map((c) => c.toJson()).toList();
    await prefs.setString(_collectionsKey, jsonEncode(jsonList));
  }

  // ——————————————————————————————————————————————————————————————————————————
  // USER POSTS - Filter by type
  // ——————————————————————————————————————————————————————————————————————————

  /// Get posts for a user, optionally filtered by type
  Future<List<Map<String, dynamic>>> getUserPosts({
    String? userId,
    String? viewerId,
    String? type,
    int page = 1,
    int? limit,
    int? offset,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('app_token') ?? prefs.getString('auth_token');
      final currentUserId = prefs.getString('user_id');

      final targetUserId = userId ?? currentUserId;
      final resolvedViewerId = (viewerId != null && viewerId.isNotEmpty)
          ? viewerId
          : (currentUserId ?? targetUserId);

      if (token == null || targetUserId == null) {
        throw Exception('Authentication token or user ID not found.');
      }

      final baseUrl = await AppEnv.getBaseUrlAsync();

      final queryParams = <String, dynamic>{
        'scope': 'profile',
        'user_id': targetUserId,
        'viewer_id': resolvedViewerId,
        'page': page,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

      if (type != null && type != 'content') {
        queryParams['type'] = type;
      }

      final response = await _dio.get(
        '${baseUrl}posts.php',
        queryParameters: queryParams,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.plain,
        ),
      );

      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        final rawPosts = List<Map<String, dynamic>>.from(
          payload['posts'] ?? payload['data'] ?? [],
        );
        return rawPosts.map((p) => _normalizeProfilePost(p, baseUrl)).toList();
      }
      throw Exception('Invalid post data from API.');
    } on DioException catch (e) {
      throw Exception('Error loading user posts: ${e.message}');
    } catch (e) {
      throw Exception('Failed to load user posts: $e');
    }
  }

  Map<String, dynamic> _normalizeProfilePost(
    Map<String, dynamic> raw,
    String baseUrl,
  ) {
    final normalized = Map<String, dynamic>.from(raw);

    final mediaUrl = normalizeMediaUrl(
      raw['media_url'] ??
          raw['file_url'] ??
          raw['image_url'] ??
          raw['video_url'],
      baseUrl: baseUrl,
    );

    final thumbRaw = (raw['thumbnail_url'] ?? '').toString().trim();
    final thumb = thumbRaw.isNotEmpty ? normalizeMediaUrl(thumbRaw, baseUrl: baseUrl) : '';

    final typeStr = (raw['type'] ?? raw['post_type'] ?? '').toString().toLowerCase();
    final isVideoPost = typeStr == 'video' ||
        typeStr == 'reel' ||
        mediaUrl.toLowerCase().endsWith('.mp4') ||
        mediaUrl.toLowerCase().endsWith('.mov') ||
        mediaUrl.toLowerCase().endsWith('.m3u8');

    normalized['media_url'] = mediaUrl;
    normalized['file_url'] = mediaUrl;
    normalized['thumbnail_url'] = thumb.isNotEmpty ? thumb : (isVideoPost ? '' : mediaUrl);
    normalized['image_url'] = thumb.isNotEmpty ? thumb : (isVideoPost ? '' : mediaUrl);

    final avatar = normalizeMediaUrl(
      raw['user_avatar'] ?? raw['user_profile_pic'] ?? raw['profile_pic'],
      baseUrl: baseUrl,
      folder: 'profiles',
    );
    if (avatar.isNotEmpty) {
      normalized['user_avatar'] = avatar;
      normalized['user_profile_pic'] = avatar;
    }

    if (kDebugMode) {}

    return normalized;
  }
}
