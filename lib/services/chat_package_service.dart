import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:love_vibe_pro/services/api_service.dart';

class ChatPackage {
  final int id;
  final int creatorId;
  final String name;
  final int minutes;
  final int priceCoins;
  final bool isFree;

  const ChatPackage({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.minutes,
    required this.priceCoins,
    required this.isFree,
  });

  factory ChatPackage.fromJson(Map<String, dynamic> j) => ChatPackage(
        id: _i(j['id']),
        creatorId: _i(j['creator_id']),
        name: j['name']?.toString() ?? '',
        minutes: _i(j['minutes']),
        priceCoins: _i(j['price_coins']),
        isFree: j['is_free'] == 1 || j['is_free'] == true,
      );

  static int _i(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
}

class ChatSessionState {
  final int sessionId;
  final int sellerId;
  final int minutesTotal;
  final int coinsPaid;
  final DateTime expiresAt;
  final int secondsLeft;
  final bool active;

  const ChatSessionState({
    required this.sessionId,
    required this.sellerId,
    required this.minutesTotal,
    required this.coinsPaid,
    required this.expiresAt,
    required this.secondsLeft,
    required this.active,
  });

  double get progressFraction {
    if (minutesTotal <= 0) return 0;
    final total = minutesTotal * 60;
    return (secondsLeft / total).clamp(0.0, 1.0);
  }

  String get timeDisplay {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  ChatSessionState copyWith({int? secondsLeft, bool? active}) =>
      ChatSessionState(
        sessionId: sessionId,
        sellerId: sellerId,
        minutesTotal: minutesTotal,
        coinsPaid: coinsPaid,
        expiresAt: expiresAt,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        active: active ?? this.active,
      );
}

/// Manages the active chat time session for the current conversation.
/// The timer ticks every second (Dart-side) for smooth UI.
/// Authoritative state is always the server-side expiry time — we
/// sync on start and on every app resume to prevent drift.
class ChatPackageService {
  ChatPackageService._();
  static final ChatPackageService instance = ChatPackageService._();

  final ValueNotifier<ChatSessionState?> sessionNotifier =
      ValueNotifier<ChatSessionState?>(null);

  // Fires once with coinsPaid when a new session is bought — chat_screen
  // listens to trigger the coin-fly animation.
  final ValueNotifier<int> coinDeductedNotifier = ValueNotifier<int>(0);

  Timer? _ticker;

  ChatSessionState? get current => sessionNotifier.value;

  // ── Query server for active session ──────────────────────────────────────
  Future<ChatSessionState?> checkSession(int sellerId) async {
    try {
      final dio = await ApiService().getDioClient();
      final res = await dio.get(
        'chat_packages.php?action=session_status',
        queryParameters: {'seller_id': sellerId},
      );
      final body = _map(res.data);
      if (body['active'] == true) {
        final state = _sessionFromBody(body, sellerId);
        if (state != null) {
          _setState(state);
          return state;
        }
      } else {
        _clearIfSeller(sellerId);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch packages offered by a creator plus free-time remaining.
  Future<({List<ChatPackage> packages, int freeMinLeft})> listPackages(
      int creatorId) async {
    try {
      final dio = await ApiService().getDioClient();
      final res = await dio.get(
        'chat_packages.php',
        queryParameters: {'action': 'list', 'creator_id': creatorId},
      );
      final body = _map(res.data);
      final pkgs = (body['packages'] as List? ?? [])
          .map((e) => ChatPackage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final freeLeft = int.tryParse(body['free_min_left']?.toString() ?? '') ?? 0;
      return (packages: pkgs, freeMinLeft: freeLeft);
    } catch (_) {}
    return (packages: <ChatPackage>[], freeMinLeft: 0);
  }

  /// Buy a package (or use the free package id=0). Starts the countdown.
  /// Returns the new session state.
  Future<ChatSessionState> buyPackage({
    required int sellerId,
    required int packageId,
  }) async {
    final dio = await ApiService().getDioClient();
    final res = await dio.post(
      'chat_packages.php?action=buy',
      data: {'seller_id': sellerId, 'package_id': packageId},
    );
    final body = _map(res.data);
    if (body['status'] != 'success') {
      throw Exception(body['message']?.toString() ?? 'Could not start session');
    }

    final coinsPaid = int.tryParse(body['coins_paid']?.toString() ?? '') ?? 0;
    final minutes = int.tryParse(body['minutes']?.toString() ?? '') ?? 5;
    final expiresAt = DateTime.parse(body['expires_at'].toString());
    final sessionId = int.tryParse(body['session_id']?.toString() ?? '') ?? 0;

    final state = ChatSessionState(
      sessionId: sessionId,
      sellerId: sellerId,
      minutesTotal: minutes,
      coinsPaid: coinsPaid,
      expiresAt: expiresAt,
      secondsLeft: expiresAt.difference(DateTime.now()).inSeconds.clamp(0, minutes * 60),
      active: true,
    );
    _setState(state);

    if (coinsPaid > 0) {
      // Notify listeners for coin-fly animation.
      coinDeductedNotifier.value = coinsPaid;
      // Reset after one frame so the animation can re-trigger next time.
      Future.delayed(const Duration(milliseconds: 100), () {
        coinDeductedNotifier.value = 0;
      });
    }

    return state;
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _setState(ChatSessionState state) {
    sessionNotifier.value = state;
    _startTicker();
  }

  void _clearIfSeller(int sellerId) {
    if (sessionNotifier.value?.sellerId == sellerId) {
      sessionNotifier.value = null;
      _ticker?.cancel();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = sessionNotifier.value;
      if (s == null || !s.active) {
        _ticker?.cancel();
        return;
      }
      final left = s.expiresAt.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        sessionNotifier.value = s.copyWith(secondsLeft: 0, active: false);
        _ticker?.cancel();
        return;
      }
      sessionNotifier.value = s.copyWith(secondsLeft: left);
    });
  }

  ChatSessionState? _sessionFromBody(Map<String, dynamic> body, int sellerId) {
    try {
      final expiresAt = DateTime.parse(body['expires_at'].toString());
      return ChatSessionState(
        sessionId: int.tryParse(body['session_id']?.toString() ?? '') ?? 0,
        sellerId: sellerId,
        minutesTotal: int.tryParse(body['minutes_total']?.toString() ?? '') ?? 5,
        coinsPaid: int.tryParse(body['coins_paid']?.toString() ?? '') ?? 0,
        expiresAt: expiresAt,
        secondsLeft: expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 9999),
        active: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return {};
  }
}
