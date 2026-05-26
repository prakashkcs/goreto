import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/api_service.dart';

class GiftService {
  final ApiService _apiService;

  GiftService({ApiService? apiService}) : _apiService = apiService ?? ApiService();

  Future<List<GiftItem>> getGifts() async {
    final dio = await _apiService.getDioClient();
    final actions = <String>['gifts', 'list_gifts', 'gift_list'];

    for (final action in actions) {
      try {
        final response = await dio.get(
          '/wallet.php',
          queryParameters: {'action': action},
          options: Options(responseType: ResponseType.plain),
        );

        final payload = _asMap(response.data);
        if (payload == null) continue;

        final status = payload['status']?.toString().toLowerCase();
        if (status != 'success') {
          final message = (payload['message'] ?? '').toString().toLowerCase();
          if (_looksLikeMissingAction(message)) continue;
          return <GiftItem>[];
        }

        final list = payload['gifts'] ?? payload['items'] ?? payload['data'];
        if (list is! List) return <GiftItem>[];

        return list
            .whereType<Map>()
            .map((e) => GiftItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } on DioException {
        continue;
      }
    }

    return <GiftItem>[];
  }

  Future<GiftActionResult> buyGift({required int giftId}) async {
    return _giftAction(
      actions: const ['buy_gift', 'gift_buy'],
      giftId: giftId,
      successFallback: 'Gift purchased',
      unavailableFallback: 'Gift purchase endpoint not available',
    );
  }

  Future<GiftActionResult> sellGift({required int giftId}) async {
    return _giftAction(
      actions: const ['sell_gift', 'gift_sell'],
      giftId: giftId,
      successFallback: 'Gift sold',
      unavailableFallback: 'Gift sell endpoint not available',
    );
  }

  Future<GiftActionResult> _giftAction({
    required List<String> actions,
    required int giftId,
    required String successFallback,
    required String unavailableFallback,
  }) async {
    final dio = await _apiService.getDioClient();
    bool hadTransportFailure = false;

    for (final action in actions) {
      try {
        final response = await dio.post(
          '/wallet.php',
          queryParameters: {'action': action},
          data: {
            'gift_id': giftId.toString(),
            'id': giftId.toString(),
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
          return GiftActionResult(
            success: true,
            message: message.isNotEmpty ? message : successFallback,
          );
        }

        if (_looksLikeMissingAction(message.toLowerCase())) {
          continue;
        }

        return GiftActionResult(
          success: false,
          message: message.isNotEmpty ? message : 'Gift action failed',
        );
      } on DioException {
        hadTransportFailure = true;
      }
    }

    return GiftActionResult(
      success: false,
      message: hadTransportFailure ? 'Wallet API error' : unavailableFallback,
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
