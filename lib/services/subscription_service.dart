import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/config/app_env.dart';

class SubscriptionService {
  final ApiService _apiService;

  SubscriptionService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  /// Returns the ekloadmin root URL (strips /api/v1 suffix from baseUrl).
  String _rootUrl() {
    final base = AppEnv.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return base.replaceAll(RegExp(r'/api/v\d+$', caseSensitive: false), '');
  }

  Future<List<SubscriptionItem>> getSubscriptions() async {
    final root = _rootUrl();
    final dio = Dio(BaseOptions(
      baseUrl: root,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    // Copy auth headers from the main client
    final authDio = await _apiService.getDioClient();
    dio.options.headers.addAll(authDio.options.headers);

    final actions = <String>['my_subscriptions', 'subscriptions'];

    for (final action in actions) {
      try {
        final response = await dio.get(
          'subscriptions.php',
          queryParameters: {'action': action},
          options: Options(responseType: ResponseType.plain),
        );

        final payload = _asMap(response.data);
        if (payload == null) continue;

        final status = payload['status']?.toString().toLowerCase();
        if (status != 'success') {
          final message = (payload['message'] ?? '').toString().toLowerCase();
          if (_looksLikeMissingAction(message)) continue;
          return <SubscriptionItem>[];
        }

        final list =
            payload['subscriptions'] ?? payload['items'] ?? payload['data'];
        if (list is! List) return <SubscriptionItem>[];

        return list
            .whereType<Map>()
            .map((e) => SubscriptionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } on DioException {
        continue;
      }
    }

    return <SubscriptionItem>[];
  }

  Future<SubscriptionActionResult> cancelSubscription({
    required String subscriptionId,
  }) async {
    final root = _rootUrl();
    final dio = Dio(BaseOptions(baseUrl: root));
    final authDio = await _apiService.getDioClient();
    dio.options.headers.addAll(authDio.options.headers);
    final actions = <String>['cancel_subscription', 'subscription_cancel'];
    bool hadTransportFailure = false;

    for (final action in actions) {
      try {
        final response = await dio.post(
          'subscriptions.php',
          queryParameters: {'action': action},
          data: {
            'subscription_id': subscriptionId,
            'id': subscriptionId,
          },
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );

        final payload = _asMap(response.data);
        if (payload == null) {
          hadTransportFailure = true;
          continue;
        }

        final status = payload['status']?.toString().toLowerCase() ?? '';
        final message = payload['message']?.toString() ?? '';

        if (status == 'success') {
          return SubscriptionActionResult(
            success: true,
            message: message.isNotEmpty
                ? message
                : 'Subscription canceled successfully',
          );
        }

        if (_looksLikeMissingAction(message.toLowerCase())) {
          continue;
        }

        return SubscriptionActionResult(
          success: false,
          message:
              message.isNotEmpty ? message : 'Unable to cancel subscription',
        );
      } on DioException {
        hadTransportFailure = true;
      }
    }

    return SubscriptionActionResult(
      success: false,
      message: hadTransportFailure
          ? 'Wallet API error'
          : 'Subscription cancel endpoint not available',
      endpointUnavailable: !hadTransportFailure,
    );
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

  bool _looksLikeMissingAction(String message) {
    return message.contains('unknown action') ||
        message.contains('invalid action') ||
        message.contains('not found');
  }
}
