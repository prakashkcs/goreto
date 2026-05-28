import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// State of an active pay-per-minute paid chat. Mutates as the timer ticks
/// and the server bills the buyer. Listened to by chat_screen so the
/// composer can show the running total + balance.
class PpmSessionState {
  final int sessionId;
  final int sellerId;
  final int ratePerMin;
  final int minutesCharged;
  final int totalCoinsCharged;
  final int balance;
  final bool active;
  final String? endReason;

  const PpmSessionState({
    required this.sessionId,
    required this.sellerId,
    required this.ratePerMin,
    required this.minutesCharged,
    required this.totalCoinsCharged,
    required this.balance,
    required this.active,
    this.endReason,
  });

  PpmSessionState copyWith({
    int? minutesCharged,
    int? totalCoinsCharged,
    int? balance,
    bool? active,
    String? endReason,
  }) {
    return PpmSessionState(
      sessionId: sessionId,
      sellerId: sellerId,
      ratePerMin: ratePerMin,
      minutesCharged: minutesCharged ?? this.minutesCharged,
      totalCoinsCharged: totalCoinsCharged ?? this.totalCoinsCharged,
      balance: balance ?? this.balance,
      active: active ?? this.active,
      endReason: endReason ?? this.endReason,
    );
  }
}

/// Manages exactly one active PPM session (we don't allow multiple in
/// parallel — there's no UI for it). chat_screen starts/stops via this and
/// listens to [stateNotifier] for the running minute counter.
class PpmSessionService {
  PpmSessionService._();
  static final PpmSessionService instance = PpmSessionService._();

  final ValueNotifier<PpmSessionState?> stateNotifier =
      ValueNotifier<PpmSessionState?>(null);

  Timer? _timer;
  bool _tickInFlight = false;

  PpmSessionState? get current => stateNotifier.value;

  /// Start a paid chat with [sellerId]. Returns the new state on success.
  /// Throws an [Exception] with a user-facing message on any failure (so
  /// chat_screen can NeonToast it directly).
  Future<PpmSessionState> start(int sellerId) async {
    final dio = await ApiService().getDioClient();
    final res = await dio.post(
      'chat.php?action=ppm_start',
      data: {'seller_id': sellerId},
      options: Options(responseType: ResponseType.plain),
    );
    final body = _decode(res.data);
    if (body['status'] != 'success') {
      throw Exception(body['message']?.toString() ?? 'Could not start paid chat');
    }
    final state = PpmSessionState(
      sessionId: (body['session_id'] as num).toInt(),
      sellerId: sellerId,
      ratePerMin: (body['rate_per_min'] as num).toInt(),
      minutesCharged: (body['minutes_charged'] as num).toInt(),
      totalCoinsCharged: (body['rate_per_min'] as num).toInt(),
      balance: (body['balance'] as num).toInt(),
      active: true,
    );
    stateNotifier.value = state;
    _startTicking();
    return state;
  }

  /// User-initiated stop. Best-effort: even if the network call fails the
  /// local state is cleared so the UI returns to the gate immediately.
  Future<void> stop({String reason = 'user_stop'}) async {
    final s = stateNotifier.value;
    _stopTicking();
    stateNotifier.value = null;
    if (s == null) return;
    try {
      final dio = await ApiService().getDioClient();
      await dio.post(
        'chat.php?action=ppm_end',
        data: {'session_id': s.sessionId, 'reason': reason},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (_) {
      // Already cleared locally; server will end the session on next tick
      // anyway because the buyer is no longer ticking.
    }
  }

  void _startTicking() {
    _timer?.cancel();
    // First server tick at +60s; we don't need sub-minute precision because
    // the server enforces the 60s window itself.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final s = stateNotifier.value;
    if (s == null || !s.active || _tickInFlight) return;
    _tickInFlight = true;
    try {
      final dio = await ApiService().getDioClient();
      final res = await dio.post(
        'chat.php?action=ppm_tick',
        data: {'session_id': s.sessionId},
        options: Options(responseType: ResponseType.plain),
      );
      final body = _decode(res.data);
      if (body['status'] != 'success') return;
      final newStatus = body['session_status']?.toString() ?? 'active';
      final ended = newStatus != 'active';
      stateNotifier.value = s.copyWith(
        minutesCharged: (body['minutes_charged'] as num?)?.toInt(),
        totalCoinsCharged: (body['total_coins_charged'] as num?)?.toInt(),
        balance: (body['balance'] as num?)?.toInt(),
        active: !ended,
        endReason: ended ? body['end_reason']?.toString() : null,
      );
      if (ended) {
        _stopTicking();
        // Clear after a short delay so the UI can show the "session ended"
        // toast/summary before disappearing.
        Future.delayed(const Duration(seconds: 4), () {
          if (stateNotifier.value?.sessionId == s.sessionId) {
            stateNotifier.value = null;
          }
        });
      }
    } catch (_) {
      // Network blip — keep the local state, next tick will retry.
    } finally {
      _tickInFlight = false;
    }
  }

  Map<String, dynamic> _decode(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }
}
