import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:love_vibe_pro/models/deposit_models.dart';
import 'package:love_vibe_pro/models/wallet_method.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletService {
  static const String _localPendingDepositsKey =
      'wallet_local_pending_deposits';
  static const String _pendingInstallReferralCodeKey =
      'wallet_pending_install_referral_code';

  final ApiService _apiService;

  WalletService({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  Future<List<WalletMethod>> getDepositMethods() async {
    try {
      final dio = await _apiService.getDioClient();
      Response<dynamic> response;
      try {
        response = await dio.get(
          '/wallet.php',
          queryParameters: {'action': 'methods'},
          options: Options(responseType: ResponseType.plain),
        );
      } on DioException {
        response = await dio.get(
          '/wallet.php',
          queryParameters: {'action': 'deposit_methods'},
          options: Options(responseType: ResponseType.plain),
        );
      }

      final payload = _decodeMap(response.data);
      if (payload['status']?.toString().toLowerCase() != 'success') {
        throw Exception(payload['message']?.toString() ?? 'Wallet API error');
      }

      final methodsRaw = payload['methods'];
      if (methodsRaw is! List) {
        throw Exception('Wallet API error');
      }

      return methodsRaw.whereType<Map>().map((item) {
        final method = WalletMethod.fromJson(Map<String, dynamic>.from(item));
        return WalletMethod(
          id: method.id,
          name: method.name,
          accountName: method.accountName,
          accountNumber: method.accountNumber,
          qrImage: _normalizeQr(method.qrImage, dio.options.baseUrl),
        );
      }).toList();
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<CreateDepositResult> createDeposit({
    required int methodId,
    required int coins,
    required double amount,
  }) async {
    try {
      final dio = await _apiService.getDioClient();
      final payloadData = {
        'method_id': methodId.toString(),
        'coins': coins.toString(),
        'amount': amount.toStringAsFixed(2),
      };
      Response<dynamic> response;
      try {
        response = await dio.post(
          '/wallet.php',
          queryParameters: {'action': 'create_deposit'},
          data: payloadData,
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
      } on DioException {
        response = await dio.post(
          '/wallet.php',
          queryParameters: {'action': 'create_qr_deposit'},
          data: payloadData,
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
      }

      final payload = _decodeMap(response.data);
      if (payload['status']?.toString().toLowerCase() != 'success') {
        throw Exception(payload['message']?.toString() ?? 'Wallet API error');
      }

      final parsed = CreateDepositResult.fromJson(payload);
      if (parsed.depositId <= 0) {
        throw Exception('Wallet API error');
      }

      String qrImage = parsed.qrImage;
      if (qrImage.trim().isEmpty && payload['method'] is Map) {
        final method = Map<String, dynamic>.from(payload['method'] as Map);
        qrImage = (method['qr_image'] ?? '').toString();
      }

      return CreateDepositResult(
        depositId: parsed.depositId,
        qrImage: _normalizeQr(qrImage, dio.options.baseUrl),
      );
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<WalletSettingsModel> getSettings() async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get(
        '/wallet.php',
        queryParameters: {'action': 'settings'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _decodeMap(response.data);
      if (payload['status']?.toString().toLowerCase() != 'success') {
        throw Exception(payload['message']?.toString() ?? 'Wallet API error');
      }

      final settingsRaw = payload['settings'];
      if (settingsRaw is Map) {
        return WalletSettingsModel.fromJson(
          Map<String, dynamic>.from(settingsRaw),
        );
      }
      return WalletSettingsModel.fromJson(payload);
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<WalletInfo> getWalletBalance() async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get(
        '/wallet.php',
        queryParameters: {'action': 'balance'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _decodeMap(response.data);
      if (payload['status']?.toString().toLowerCase() != 'success') {
        throw Exception(payload['message']?.toString() ?? 'Wallet API error');
      }

      if (payload['wallet'] is Map) {
        return WalletInfo.fromJson(
          Map<String, dynamic>.from(payload['wallet'] as Map),
        );
      }
      return WalletInfo.fromJson(payload);
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<List<WalletTransaction>> getTransactions({int limit = 20}) async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get(
        '/wallet.php',
        queryParameters: {'action': 'transactions', 'limit': limit},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _decodeMap(response.data);
      if (payload['status']?.toString().toLowerCase() != 'success') {
        throw Exception(payload['message']?.toString() ?? 'Wallet API error');
      }

      final list = payload['transactions'] ?? payload['data'];
      if (list is! List) return <WalletTransaction>[];

      return list
          .whereType<Map>()
          .map(
            (item) =>
                WalletTransaction.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<String> getReferralCode() async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get(
        '/wallet.php',
        queryParameters: {'action': 'balance'},
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _decodeMap(response.data);
      final wallet = payload['wallet'] is Map
          ? Map<String, dynamic>.from(payload['wallet'] as Map)
          : <String, dynamic>{};

      final candidate =
          (payload['referral_code'] ??
                  wallet['referral_code'] ??
                  payload['my_referral_code'] ??
                  wallet['my_referral_code'] ??
                  '')
              .toString()
              .trim();
      return candidate;
    } catch (_) {
      return '';
    }
  }

  Future<CheckPaymentResult> depositCheck({required int depositId}) async {
    try {
      final dio = await _apiService.getDioClient();
      Response<dynamic> response;

      try {
        response = await dio.post(
          '/wallet.php',
          queryParameters: {'action': 'check_payment'},
          data: {'deposit_id': depositId.toString()},
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
      } on DioException {
        try {
          response = await dio.post(
            '/wallet.php',
            queryParameters: {'action': 'deposit_check'},
            data: {'deposit_id': depositId.toString()},
            options: Options(
              responseType: ResponseType.plain,
              contentType: Headers.formUrlEncodedContentType,
            ),
          );
        } on DioException {
          response = await dio.post(
            '/wallet.php',
            queryParameters: {'action': 'check_qr_payment'},
            data: {'deposit_id': depositId.toString()},
            options: Options(
              responseType: ResponseType.plain,
              contentType: Headers.formUrlEncodedContentType,
            ),
          );
        }
      }

      final payload = _decodeMap(response.data);
      return CheckPaymentResult.fromJson(payload);
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<CheckPaymentResult> checkPayment({required int depositId}) async {
    return depositCheck(depositId: depositId);
  }

  Future<CheckPaymentResult> uploadDepositProof({
    required int depositId,
    required String imagePath,
  }) async {
    try {
      final dio = await _apiService.getDioClient();

      final formData = FormData.fromMap({
        'deposit_id': depositId.toString(),
        'proof': await MultipartFile.fromFile(imagePath),
      });

      final response = await dio.post(
        '/wallet.php',
        queryParameters: {'action': 'upload_deposit_proof'},
        data: formData,
        options: Options(responseType: ResponseType.plain),
      );

      final payload = _decodeMap(response.data);
      return CheckPaymentResult.fromJson(payload);
    } on DioException {
      throw Exception('Wallet API error');
    } on FormatException {
      throw Exception('Wallet API error');
    }
  }

  Future<void> addLocalPendingDeposit({
    required int depositId,
    required int coins,
    required double amount,
    required String currencyCode,
    required String methodName,
  }) async {
    final list = await getLocalPendingTransactions();
    final exists = list.any(
      (item) =>
          item.depositId == depositId || item.id == 'local_deposit_$depositId',
    );
    if (exists) return;

    final pending = WalletTransaction.localPendingDeposit(
      depositId: depositId,
      coins: coins,
      amount: amount,
      currencyCode: currencyCode,
      methodName: methodName,
    );
    list.insert(0, pending);
    await _saveLocalPendingTransactions(list);
  }

  Future<List<WalletTransaction>> getLocalPendingTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList =
        prefs.getStringList(_localPendingDepositsKey) ?? const <String>[];
    final transactions = <WalletTransaction>[];

    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          transactions.add(
            WalletTransaction.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore malformed local pending entries.
      }
    }

    return transactions;
  }

  Future<List<WalletTransaction>> getMergedTransactions({
    int limit = 20,
  }) async {
    List<WalletTransaction> remote = <WalletTransaction>[];
    try {
      remote = await getTransactions(limit: limit);
    } catch (_) {
      remote = <WalletTransaction>[];
    }

    final local = await getLocalPendingTransactions();
    if (local.isEmpty) {
      final sortedRemote = [...remote]..sort(_compareByNewest);
      return sortedRemote.take(limit).toList();
    }

    final remoteIds = remote
        .map((e) => e.id)
        .where((e) => e.isNotEmpty)
        .toSet();
    final remoteDepositIds = remote
        .map((e) => e.depositId)
        .whereType<int>()
        .toSet();

    final stillPending = <WalletTransaction>[];
    final merged = <WalletTransaction>[...remote];

    for (final pending in local) {
      final matchedByDeposit =
          pending.depositId != null &&
          remoteDepositIds.contains(pending.depositId);
      final matchedById =
          pending.id.isNotEmpty && remoteIds.contains(pending.id);

      if (matchedByDeposit || matchedById) {
        continue;
      }

      stillPending.add(pending);
      merged.add(pending);
    }

    if (stillPending.length != local.length) {
      await _saveLocalPendingTransactions(stillPending);
    }

    merged.sort(_compareByNewest);
    return merged.take(limit).toList();
  }

  Future<void> setPendingInstallReferralCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInstallReferralCodeKey, clean);
  }

  Future<String?> getPendingInstallReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingInstallReferralCodeKey)?.trim();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  Future<void> clearPendingInstallReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInstallReferralCodeKey);
  }

  Future<ReferralActionResult> updateReferralCode({
    required String referralCode,
  }) async {
    final clean = referralCode.trim().toUpperCase();
    if (clean.isEmpty) {
      return const ReferralActionResult(
        success: false,
        message: 'Please enter referral code',
      );
    }

    final dio = await _apiService.getDioClient();
    final actions = <String>[
      'update_referral_code',
      'set_referral_code',
      'referral_update',
    ];

    bool hadTransportFailure = false;

    for (final action in actions) {
      try {
        final response = await dio.post(
          '/wallet.php',
          queryParameters: {'action': action},
          data: {'referral_code': clean, 'code': clean},
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );

        final payload = _decodeMap(response.data);
        final status = payload['status']?.toString().toLowerCase() ?? '';
        final message = payload['message']?.toString() ?? '';

        if (status == 'success') {
          return ReferralActionResult(
            success: true,
            message: message.isNotEmpty ? message : 'Referral code updated',
          );
        }

        final loweredMessage = message.toLowerCase();
        final endpointMissing =
            loweredMessage.contains('unknown action') ||
            loweredMessage.contains('not found') ||
            loweredMessage.contains('invalid action');

        if (!endpointMissing) {
          return ReferralActionResult(
            success: false,
            message: message.isNotEmpty
                ? message
                : 'Unable to update referral code',
          );
        }
      } on DioException {
        hadTransportFailure = true;
      } on FormatException {
        hadTransportFailure = true;
      }
    }

    return ReferralActionResult(
      success: false,
      message: hadTransportFailure
          ? 'Wallet API error'
          : 'Referral update endpoint not available',
      endpointUnavailable: !hadTransportFailure,
    );
  }

  Future<ReferralActionResult> applyReferralCode({
    required String referralCode,
    String source = 'install_referrer',
  }) async {
    final clean = referralCode.trim();
    if (clean.isEmpty) {
      return const ReferralActionResult(
        success: false,
        message: 'Invalid referral code',
      );
    }

    final dio = await _apiService.getDioClient();

    try {
      final response = await dio.post(
        '/api_referral.php',
        queryParameters: {'action': 'apply'},
        data: {'code': clean, 'referral_code': clean, 'source': source},
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final payload = _decodeMap(response.data);
      final status  = payload['status']?.toString().toLowerCase() ?? '';
      final message = payload['message']?.toString() ?? '';

      return ReferralActionResult(
        success: status == 'success',
        message: message.isNotEmpty
            ? message
            : (status == 'success' ? 'Referral applied' : 'Unable to apply referral'),
      );
    } on DioException catch (e) {
      try {
        final payload = _decodeMap(e.response?.data);
        final msg = payload['message']?.toString() ?? '';
        if (msg.isNotEmpty) {
          return ReferralActionResult(success: false, message: msg);
        }
      } catch (_) {}
      return const ReferralActionResult(
        success: false,
        message: 'Network error. Please try again.',
      );
    } on FormatException {
      return const ReferralActionResult(
        success: false,
        message: 'Server response error. Please try again.',
      );
    }
  }

  Future<void> applyPendingInstallReferralIfAny() async {
    final pendingCode = await getPendingInstallReferralCode();
    if (pendingCode == null || pendingCode.isEmpty) return;

    final result = await applyReferralCode(
      referralCode: pendingCode,
      source: 'install_referrer',
    );

    if (result.success || result.endpointUnavailable) {
      await clearPendingInstallReferralCode();
    }
  }

  Map<String, dynamic> _decodeMap(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      value = jsonDecode(value);
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw const FormatException('Invalid wallet response');
  }

  String _normalizeQr(String? raw, String baseUrl) {
    final normalized = normalizeMediaUrl(raw, baseUrl: baseUrl, folder: '');
    return normalized;
  }

  Future<void> _saveLocalPendingTransactions(
    List<WalletTransaction> transactions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = transactions.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_localPendingDepositsKey, encoded);
  }

  int _compareByNewest(WalletTransaction a, WalletTransaction b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  // Log one app-open per day for referral activity requirements.
  Future<void> logDailyActivity({int seconds = 0}) async {
    try {
      final dio = await _apiService.getDioClient();
      await dio.post(
        '/api_referral.php',
        queryParameters: {'action': 'log_activity'},
        data: {'seconds': seconds.toString()},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
    } catch (_) {}
  }
}
