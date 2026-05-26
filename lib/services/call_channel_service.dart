import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/main.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/chat/call/webrtc_call_screen.dart';
import 'package:love_vibe_pro/screens/match/nearby_alert_screen.dart';
import 'package:love_vibe_pro/services/signaling_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Listens on the native MethodChannel for accept/decline actions
/// triggered by IncomingCallActivity (when app is background/killed).
class CallChannelService {
  static const _channel = MethodChannel('com.nex.ekloapp/call');
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallAction') {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _handleCallAction(data);
      }
    });

    // Poll native for any intent that arrived before the handler was registered
    _checkPendingCallIntent();
  }

  static void _checkPendingCallIntent() async {
    try {
      final result = await _channel.invokeMethod<Map>('getPendingCallIntent');
      if (result != null) {
        _handleCallAction(Map<String, dynamic>.from(result));
      }
    } catch (_) {}
  }

  static void _handleCallAction(Map<String, dynamic> data) {
    final action = data['action']?.toString();

    // Nearby alert: open NearbyAlertScreen
    if (action == 'open_nearby_alert') {
      _navigateToNearbyAlert(
        senderId:     data['sender_id']?.toString()     ?? '',
        senderName:   data['sender_name']?.toString()   ?? 'Someone',
        senderAvatar: data['sender_avatar']?.toString() ?? '',
      );
      return;
    }

    final callId = int.tryParse(data['call_id']?.toString() ?? '0') ?? 0;
    final callUuid = data['call_uuid']?.toString() ?? '';
    final callerName = data['caller_name']?.toString() ?? 'Unknown';
    final callerAvatar = data['caller_avatar']?.toString() ?? '';
    final callerId = data['caller_id']?.toString() ?? '';
    final callType = data['type']?.toString() ?? 'video';
    final isRandom = data['is_random'] == 'true' || data['is_random'] == true;

    if (action == 'decline_call') {
      if (callId > 0) {
        SignalingService.instance.declineCall(callId);
      }
      return;
    }

    if (action == 'accept_call') {
      _navigateToCall(
        callId: callId,
        callUuid: callUuid,
        callerName: callerName,
        callerAvatar: callerAvatar,
        callerId: callerId,
        callType: callType,
        isRandom: isRandom,
        autoAccept: true,
      );
    }
  }

  static void _navigateToNearbyAlert({
    required String senderId,
    required String senderName,
    required String senderAvatar,
    int attempts = 0,
  }) {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => NearbyAlertScreen(
            senderId: senderId,
            senderName: senderName,
            senderAvatar: senderAvatar,
          ),
        ),
      );
    } else if (attempts < 10) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _navigateToNearbyAlert(
          senderId: senderId,
          senderName: senderName,
          senderAvatar: senderAvatar,
          attempts: attempts + 1,
        ),
      );
    }
  }

  static void _navigateToCall({
    required int callId,
    required String callUuid,
    required String callerName,
    required String callerAvatar,
    required String callerId,
    required String callType,
    required bool isRandom,
    required bool autoAccept,
    int attempts = 0,
  }) {
    if (navigatorKey.currentState != null) {
      SignalingService.instance.checkCallStatus(callId).then((status) {
        // null = network error — attempt anyway; 'ended'/'declined'/'missed' = skip
        if (status != null && status != 'ringing' && status != 'accepted') {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            NeonToast.error(ctx, 'This call has already ended');
          }
          return;
        }

        final session = CallSession(
          id: callUuid,
          callerId: callerId,
          callerName: callerName,
          callerAvatar: callerAvatar,
          receiverId: '',
          receiverName: 'You',
          type: callType == 'audio' ? CallType.audio : CallType.video,
          state: CallState.incoming,
          isRandomCall: isRandom,
        );

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => WebRTCCallScreen(
              callSession: session,
              isOutgoing: false,
              serverCallId: callId,
              autoAcceptCall: autoAccept,
            ),
          ),
        );
      });
    } else if (attempts < 10) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _navigateToCall(
          callId: callId,
          callUuid: callUuid,
          callerName: callerName,
          callerAvatar: callerAvatar,
          callerId: callerId,
          callType: callType,
          isRandom: isRandom,
          autoAccept: autoAccept,
          attempts: attempts + 1,
        ),
      );
    }
  }
}
