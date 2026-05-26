import 'package:love_vibe_pro/utils/date_util.dart';

class WalletInfo {
  final int coins;

  const WalletInfo({required this.coins});

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['coins'] ?? json['balance_coins'] ?? json['balance'] ?? 0;
    return WalletInfo(coins: int.tryParse(raw.toString()) ?? 0);
  }
}

class WalletSettingsModel {
  final double coinsPerCurrency;
  final String currencySymbol;
  final String currencyCode;
  final int minDepositCoins;

  const WalletSettingsModel({
    required this.coinsPerCurrency,
    required this.currencySymbol,
    required this.currencyCode,
    required this.minDepositCoins,
  });

  factory WalletSettingsModel.fromJson(Map<String, dynamic> json) {
    final rawCoinsPerCurrency =
        json['coins_per_currency'] ?? json['coin_per_currency'] ?? 100;
    final rawMinDeposit = json['min_deposit_coins'] ?? 0;

    return WalletSettingsModel(
      coinsPerCurrency: double.tryParse(rawCoinsPerCurrency.toString()) ?? 100,
      currencySymbol: (json['currency_symbol'] ?? '₨').toString(),
      currencyCode: (json['currency_code'] ?? 'NPR').toString(),
      minDepositCoins: int.tryParse(rawMinDeposit.toString()) ?? 0,
    );
  }
}

class ReferralActionResult {
  final bool success;
  final String message;
  final bool endpointUnavailable;

  const ReferralActionResult({
    required this.success,
    required this.message,
    this.endpointUnavailable = false,
  });
}

class GiftItem {
  final int id;
  final String name;
  final String? image;
  final int coinPrice;
  final int ownedCount;
  // New fields for animated gift shop
  final String? emoji;
  final String? category;
  final String? animationType;

  const GiftItem({
    required this.id,
    required this.name,
    required this.image,
    required this.coinPrice,
    this.ownedCount = 0,
    this.emoji,
    this.category,
    this.animationType,
  });

  factory GiftItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      return int.tryParse((value ?? fallback).toString()) ?? fallback;
    }

    String? parseNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return text;
    }

    return GiftItem(
      id: parseInt(json['id']),
      name: (json['name'] ?? 'Gift').toString(),
      image: parseNullableString(
        json['image'] ?? json['icon'] ?? json['image_url'] ?? json['icon_url'],
      ),
      coinPrice: parseInt(
        json['coin_price'] ??
            json['price_coins'] ??
            json['price'] ??
            json['coins_cost'],
      ),
      ownedCount: parseInt(
        json['owned_count'] ?? json['quantity'] ?? json['owned'],
      ),
      emoji: parseNullableString(json['emoji']),
      category: parseNullableString(json['category']),
      animationType: parseNullableString(json['animation_type']),
    );
  }
}

class GiftActionResult {
  final bool success;
  final String message;
  final bool endpointUnavailable;

  const GiftActionResult({
    required this.success,
    required this.message,
    this.endpointUnavailable = false,
  });
}

class SubscriptionItem {
  final String id;
  final String modelName;
  final String planName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;

  const SubscriptionItem({
    required this.id,
    required this.modelName,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateUtil.parseServerTime(value.toString());
    }

    final endDate = parseDate(json['end_date'] ?? json['expires_at']);
    String rawStatus = (json['status'] ?? 'inactive').toString().toLowerCase();

    // If the server says "active" but the end_date is in the past, treat it
    // as expired so the UI doesn't show a misleading green "ACTIVE" badge.
    if (rawStatus == 'active' &&
        endDate != null &&
        endDate.isBefore(DateTime.now())) {
      rawStatus = 'expired';
    }

    return SubscriptionItem(
      id: (json['id'] ?? json['subscription_id'] ?? '').toString(),
      modelName: (json['model_name'] ??
              json['creator_name'] ??
              json['target_name'] ??
              'Model')
          .toString(),
      planName:
          (json['plan_name'] ?? json['plan'] ?? 'Subscription').toString(),
      startDate: parseDate(json['start_date'] ?? json['started_at']),
      endDate: endDate,
      status: rawStatus,
    );
  }
}

class SubscriptionActionResult {
  final bool success;
  final String message;
  final bool endpointUnavailable;

  const SubscriptionActionResult({
    required this.success,
    required this.message,
    this.endpointUnavailable = false,
  });
}

class WalletTransaction {
  final String id;
  final String type;
  final int coins;
  final String status;
  final String note;
  final String direction;
  final double? currencyAmount;
  final String currencyCode;
  final DateTime? createdAt;
  final bool isLocalPending;
  final int? depositId;
  final String? methodName;
  final String? rejectReason;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.coins,
    required this.status,
    required this.note,
    required this.direction,
    required this.currencyAmount,
    required this.currencyCode,
    required this.createdAt,
    this.isLocalPending = false,
    this.depositId,
    this.methodName,
    this.rejectReason,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(List<dynamic> candidates) {
      for (final candidate in candidates) {
        if (candidate == null) continue;
        final text = candidate.toString().trim();
        if (text.isEmpty) continue;
        final parsed = DateUtil.parseServerTime(text);
        if (parsed.year > 2000) return parsed;
      }
      return null;
    }

    int parseInt(List<dynamic> candidates, {int fallback = 0}) {
      for (final candidate in candidates) {
        if (candidate == null) continue;
        final parsed = int.tryParse(candidate.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    double? parseDouble(List<dynamic> candidates) {
      for (final candidate in candidates) {
        if (candidate == null) continue;
        final parsed = double.tryParse(candidate.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    String parseString(List<dynamic> candidates, {String fallback = ''}) {
      for (final candidate in candidates) {
        if (candidate == null) continue;
        final text = candidate.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    final type = parseString([
      json['type'],
      json['transaction_type'],
      json['category'],
      json['action'],
    ], fallback: 'unknown');

    final direction = parseString([
      json['direction'],
      json['flow'],
    ], fallback: type.toLowerCase().contains('withdraw') ? 'debit' : 'credit');

    return WalletTransaction(
      id: parseString([
        json['id'],
        json['tx_id'],
        json['transaction_id'],
        json['local_id'],
        json['deposit_id'],
      ]),
      type: type,
      coins: parseInt([
        json['coins'],
        json['amount_coins'],
        json['coin_amount'],
      ]),
      status: parseString([
        json['status'],
        json['payment_status'],
        json['state'],
      ], fallback: 'pending'),
      note: parseString([json['note'], json['message'], json['description']]),
      direction: direction,
      currencyAmount: parseDouble([
        json['currency_amount'],
        json['amount_currency'],
        json['amount'],
      ]),
      currencyCode: parseString([
        json['currency_code'],
        json['currency'],
      ], fallback: 'NPR'),
      createdAt: parseDate([
        json['created_at'],
        json['date'],
        json['updated_at'],
      ]),
      isLocalPending: json['is_local_pending'] == true,
      depositId: int.tryParse((json['deposit_id'] ?? '').toString()),
      methodName: parseString([json['method_name'], json['method']]),
      rejectReason: parseString([
        json['reject_reason'],
        json['rejection_reason'],
        json['reason'],
      ]),
    );
  }

  factory WalletTransaction.localPendingDeposit({
    required int depositId,
    required int coins,
    required double amount,
    required String currencyCode,
    required String methodName,
    DateTime? createdAt,
  }) {
    return WalletTransaction(
      id: 'local_deposit_$depositId',
      type: 'deposit',
      coins: coins,
      status: 'reviewing',
      note: 'Deposit submitted via $methodName',
      direction: 'credit',
      currencyAmount: amount,
      currencyCode: currencyCode,
      createdAt: createdAt ?? DateTime.now(),
      isLocalPending: true,
      depositId: depositId,
      methodName: methodName,
      rejectReason: null,
    );
  }

  WalletTransaction copyWith({String? status, bool? isLocalPending}) {
    return WalletTransaction(
      id: id,
      type: type,
      coins: coins,
      status: status ?? this.status,
      note: note,
      direction: direction,
      currencyAmount: currencyAmount,
      currencyCode: currencyCode,
      createdAt: createdAt,
      isLocalPending: isLocalPending ?? this.isLocalPending,
      depositId: depositId,
      methodName: methodName,
      rejectReason: rejectReason,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'coins': coins,
      'status': status,
      'note': note,
      'direction': direction,
      'currency_amount': currencyAmount,
      'currency_code': currencyCode,
      'created_at': createdAt?.toIso8601String(),
      'is_local_pending': isLocalPending,
      'deposit_id': depositId,
      'method_name': methodName,
      'reject_reason': rejectReason,
    };
  }
}
