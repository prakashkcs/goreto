import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Service for creator subscription plan management
class SubscriptionPlanService {
  final ApiService _apiService;

  static final SubscriptionPlanService _instance =
      SubscriptionPlanService._internal();
  factory SubscriptionPlanService() => _instance;
  SubscriptionPlanService._internal() : _apiService = ApiService();

  /// All subscription endpoints now live under /api/v1/subscriptions.php.
  /// Use the shared authenticated Dio so the Bearer-token interceptor and
  /// HMAC signing both attach. Building a fresh Dio here used to drop the
  /// Authorization header (it's set per-request by an interceptor, not in
  /// default options) which surfaced as "missing auth header" on the
  /// server.
  Future<Dio> _rootDio() async {
    return _apiService.getDioClient();
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  /// Get current user's own subscription plans
  Future<List<Map<String, dynamic>>> getMyPlans() async {
    final dio = await _rootDio();
    try {
      final res = await dio.get(
        'subscriptions.php',
        queryParameters: {'action': 'my_plans'},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asMap(res.data);
      if (payload == null || payload['status'] != 'success') return [];
      final list = payload['plans'];
      if (list is! List) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get a creator's plans (for viewers)
  Future<List<Map<String, dynamic>>> getCreatorPlans(int creatorId) async {
    final dio = await _rootDio();
    try {
      final res = await dio.get(
        'subscriptions.php',
        queryParameters: {'action': 'get_plans', 'creator_id': creatorId},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asMap(res.data);
      if (payload == null || payload['status'] != 'success') return [];
      final list = payload['plans'];
      if (list is! List) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Create a new plan (max 2)
  Future<Map<String, dynamic>> createPlan({
    required String name,
    required int priceCoins,
    int durationDays = 30,
    List<String>? customFeatures,
    bool canMessageFirst = false,
  }) async {
    final dio = await _rootDio();
    try {
      final res = await dio.post(
        'subscriptions.php?action=create_plan',
        data: {
          'name': name,
          'price_coins': priceCoins,
          'duration_days': durationDays,
          if (customFeatures != null) 'custom_features': customFeatures,
          'can_message_first': canMessageFirst,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asMap(res.data);
      return payload ?? {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      final payload = _asMap(e.response?.data);
      return payload ??
          {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  /// Update an existing plan
  Future<Map<String, dynamic>> updatePlan({
    required int planId,
    String? name,
    int? priceCoins,
    int? durationDays,
    List<String>? customFeatures,
    bool? canMessageFirst,
  }) async {
    final dio = await _rootDio();
    try {
      final body = <String, dynamic>{'plan_id': planId};
      if (name != null) body['name'] = name;
      if (priceCoins != null) body['price_coins'] = priceCoins;
      if (durationDays != null) body['duration_days'] = durationDays;
      if (customFeatures != null) body['custom_features'] = customFeatures;
      if (canMessageFirst != null) body['can_message_first'] = canMessageFirst;

      final res = await dio.post(
        'subscriptions.php?action=update_plan',
        data: body,
        options: Options(responseType: ResponseType.plain),
      );
      return _asMap(res.data) ??
          {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      final payload = _asMap(e.response?.data);
      return payload ??
          {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  /// Delete a plan (soft-delete)
  Future<Map<String, dynamic>> deletePlan(int planId) async {
    final dio = await _rootDio();
    try {
      final res = await dio.post(
        'subscriptions.php?action=delete_plan',
        data: {'plan_id': planId},
        options: Options(responseType: ResponseType.plain),
      );
      return _asMap(res.data) ??
          {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      final payload = _asMap(e.response?.data);
      return payload ??
          {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  /// Subscribe to a plan (deducts coins)
  Future<Map<String, dynamic>> subscribeToPlan(int planId) async {
    final dio = await _rootDio();
    try {
      final res = await dio.post(
        'subscriptions.php?action=subscribe',
        data: {'plan_id': planId},
        options: Options(responseType: ResponseType.plain),
      );
      return _asMap(res.data) ??
          {'status': 'error', 'message': 'Invalid response'};
    } on DioException catch (e) {
      final payload = _asMap(e.response?.data);
      return payload ??
          {'status': 'error', 'message': e.message ?? 'Network error'};
    }
  }

  /// Check if the current user is subscribed to a creator
  Future<bool> isSubscribedTo(int creatorId) async {
    final dio = await _rootDio();
    try {
      final res = await dio.get(
        'subscriptions.php',
        queryParameters: {'action': 'check', 'creator_id': creatorId},
        options: Options(responseType: ResponseType.plain),
      );
      final payload = _asMap(res.data);
      if (payload == null) return false;
      return payload['is_subscribed'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Check if messaging is allowed for a user initiating contact
  Future<bool> checkMessagingRestriction(int creatorId) async {
    try {
      final plans = await getCreatorPlans(creatorId);
      return plans.any(
        (p) =>
            p['can_message_first'] == 1 ||
            p['can_message_first'] == '1' ||
            p['can_message_first'] == true,
      );
    } catch (_) {
      return false;
    }
  }
}
