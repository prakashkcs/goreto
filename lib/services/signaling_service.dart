import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SignalingService - HTTP-polling signaling for WebRTC calls.
///
/// Uses the PHP signaling.php backend to exchange SDP offers/answers
/// and ICE candidates between two users.
class SignalingService {
  SignalingService._();
  static final SignalingService _instance = SignalingService._();
  static SignalingService get instance => _instance;

  // Callbacks
  Function(Map<String, dynamic> call)? onIncomingCall;
  Function()? dismissActiveCallDialog;
  Function()? onCallAccepted;
  Function()? onCallDeclined;
  Function()? onCallEnded;
  Function(String sdp, String type)? onRemoteDescription;
  Function(Map<String, dynamic> candidate)? onRemoteIceCandidate;

  // Polling timers
  Timer? _incomingPollTimer;
  Timer? _signalPollTimer;
  bool _isPollingIncoming = false;
  int _lastSignalId = 0;
  int? _activeCallId;
  bool _callAcceptedNotified = false;

  Future<Dio> _getDio() async {
    final prefs = await SharedPreferences.getInstance();
    var baseUrl = prefs.getString('api_base_url') ??
        'https://goreto.org/ekloadmin/api/v1/';
    // Always ensure trailing slash to avoid URL concatenation bugs
    if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token =
              prefs.getString('app_token') ?? prefs.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Accept'] = 'application/json';
          return handler.next(options);
        },
      ),
    );
    return dio;
  }

  // â”€â”€ Start polling for incoming calls (run in background) â”€â”€
  void startIncomingCallPolling() {
    _incomingPollTimer?.cancel();
    _incomingPollTimer = Timer.periodic(const Duration(milliseconds: 800), (
      _,
    ) {
      _pollIncomingCall();
    });
  }

  void stopIncomingCallPolling() {
    _incomingPollTimer?.cancel();
    _incomingPollTimer = null;
  }

  Future<void> _pollIncomingCall() async {
    if (_isPollingIncoming) return;
    _isPollingIncoming = true;
    try {
      final dio = await _getDio();
      final response = await dio.get(
        'signaling.php',
        queryParameters: {'action': 'poll_incoming'},
        options: Options(validateStatus: (_) => true),
      );
      // Ignore non-200 responses silently (e.g. 403 when not logged in)
      if ((response.statusCode ?? 0) != 200) return;
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success') {
        if (data['has_call'] == true) {
          final call = data['call'];
          onIncomingCall?.call(call);
        } else {
          // If there is no incoming call but we were ringing, dismiss the dialog
          dismissActiveCallDialog?.call();
        }
      }
    } catch (_) {
      // Silently ignore poll errors (network issues, auth errors, etc.)
    } finally {
      _isPollingIncoming = false;
    }
  }

  // â”€â”€ Initiate a call â”€â”€
  Future<Map<String, dynamic>?> initiateCall({
    required String receiverId,
    required String type,
    required String callUuid,
  }) async {
    try {
      final dio = await _getDio();

      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({
          'action': 'initiate_call',
          'receiver_id': receiverId,
          'type': type,
          'call_uuid': callUuid,
        }),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success') {
        _activeCallId = data['call_id'];
        return data;
      }
    } catch (_) {}
    return null;
  }

  // â”€â”€ Accept a call â”€â”€
  Future<bool> acceptCall(int callId) async {
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'accept_call', 'call_id': callId}),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      _activeCallId = callId;
      return data['status'] == 'success';
    } catch (_) {}
    return false;
  }

  // â”€â”€ Decline a call â”€â”€
  Future<bool> declineCall(int callId) async {
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'decline_call', 'call_id': callId}),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      return data['status'] == 'success';
    } catch (_) {}
    return false;
  }

  // â”€â”€ End a call â”€â”€
  Future<bool> endCall(int callId) async {
    _stopSignalPolling();
    _activeCallId = null;
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'end_call', 'call_id': callId}),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      return data['status'] == 'success';
    } catch (_) {}
    return false;
  }

  // â”€â”€ Check Call Status (for polling during incoming) â”€â”€
  Future<String?> checkCallStatus(int callId) async {
    try {
      final dio = await _getDio();
      final response = await dio.get(
        'signaling.php',
        queryParameters: {'action': 'call_status', 'call_id': callId},
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success' && data['call'] != null) {
        return data['call']['status']?.toString();
      }
    } catch (_) {}
    return null;
  }

  // â”€â”€ Send a signal (offer, answer, or ICE candidate) â”€â”€
  Future<bool> sendSignal({
    required int callId,
    required String signalType,
    required String payload,
  }) async {
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({
          'action': 'send_signal',
          'call_id': callId,
          'signal_type': signalType,
          'payload': payload,
        }),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      return data['status'] == 'success';
    } catch (e) {}
    return false;
  }

  // â”€â”€ Start polling for signals from the other party â”€â”€
  void startSignalPolling(int callId) {
    _lastSignalId = 0;
    _callAcceptedNotified = false;
    _activeCallId = callId;
    _signalPollTimer?.cancel();
    _signalPollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _pollSignals(callId),
    );
  }

  void _stopSignalPolling() {
    _signalPollTimer?.cancel();
    _signalPollTimer = null;
  }

  Future<void> _pollSignals(int callId) async {
    try {
      final dio = await _getDio();
      final response = await dio.get(
        'signaling.php',
        queryParameters: {
          'action': 'poll_signals',
          'call_id': callId,
          'after_id': _lastSignalId,
        },
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success') {
        final List signals = data['signals'] ?? [];
        for (var signal in signals) {
          final id = int.tryParse(signal['id'].toString()) ?? 0;
          if (id > _lastSignalId) _lastSignalId = id;

          final type = signal['signal_type'] ?? '';
          final payload = signal['payload'] ?? '';

          if (type == 'offer' || type == 'answer') {
            try {
              final parsed = jsonDecode(payload);
              onRemoteDescription?.call(parsed['sdp'] ?? '', type);
            } catch (_) {
              onRemoteDescription?.call(payload, type);
            }
          } else if (type == 'ice') {
            try {
              final parsed = jsonDecode(payload);
              onRemoteIceCandidate?.call(parsed);
            } catch (_) {}
          }
        }
      }

      // Also check call status
      final statusResp = await dio.get(
        'signaling.php',
        queryParameters: {'action': 'call_status', 'call_id': callId},
      );
      dynamic statusData = statusResp.data;
      if (statusData is String) statusData = jsonDecode(statusData);

      if (statusData['status'] == 'success') {
        final callStatus = statusData['call']?['status'] ?? '';
        if (callStatus == 'accepted') {
          if (!_callAcceptedNotified) {
            _callAcceptedNotified = true;
            onCallAccepted?.call();
          }
        } else if (callStatus == 'declined') {
          _stopSignalPolling();
          onCallDeclined?.call();
        } else if (callStatus == 'ended' || callStatus == 'missed') {
          _stopSignalPolling();
          onCallEnded?.call();
        }
      }
    } catch (_) {}
  }

  // â”€â”€ Get call status â”€â”€
  Future<String?> getCallStatus(int callId) async {
    try {
      final dio = await _getDio();
      final response = await dio.get(
        'signaling.php',
        queryParameters: {'action': 'call_status', 'call_id': callId},
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      return data['call']?['status'] as String?;
    } catch (_) {}
    return null;
  }

  // â”€â”€ Random call match â€” find real user â”€â”€
  Future<Map<String, dynamic>?> randomCallMatch({String type = 'video'}) async {
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'random_call_match', 'type': type}),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success') {
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> pollRandomMatch() async {
    try {
      final dio = await _getDio();
      final response = await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'poll_random_match'}),
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data['status'] == 'success') {
        if (data['matched'] == true && data['call_id'] != null) {
          _activeCallId = data['call_id'];
        }
        return data;
      }
    } catch (e) {}
    return null;
  }

  Future<void> cancelRandomMatch() async {
    try {
      final dio = await _getDio();
      await dio.post(
        'signaling.php',
        data: FormData.fromMap({'action': 'cancel_random_match'}),
      );
    } catch (e) {}
  }

  /// Clean up
  void dispose() {
    _incomingPollTimer?.cancel();
    _signalPollTimer?.cancel();
  }
}

/// ICE Candidate data wrapper for callbacks
class IceCandidateData {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  IceCandidateData({required this.candidate, this.sdpMid, this.sdpMLineIndex});
}
