import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:love_vibe_pro/services/signaling_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/nearby_block_service.dart';
import 'package:love_vibe_pro/main.dart';
import 'package:love_vibe_pro/screens/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/chat/chat_list_screen.dart';
import 'package:love_vibe_pro/screens/chat/call/webrtc_call_screen.dart';
import 'package:love_vibe_pro/screens/settings/kyc_screen.dart';
import 'package:love_vibe_pro/screens/settings/wallet_screen.dart';
import 'package:love_vibe_pro/screens/gifts/gifts_notification_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/screens/match/nearby_alert_screen.dart';
import 'package:love_vibe_pro/screens/match/nearby_screen.dart';
import 'package:love_vibe_pro/screens/match/proposal_alert_screen.dart';
import 'package:love_vibe_pro/screens/match/proposals_screen.dart';
import 'package:love_vibe_pro/screens/live/live_room_screen.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';

/// Checks call status from the background isolate (no app context available).
/// Returns true if the call is still ringing/accepted, false if already ended.
Future<bool> _bgCheckCallRinging(int callId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var baseUrl = prefs.getString('api_base_url') ??
        'https://goreto.org/ekloadmin/api/v1/';
    if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';
    final token =
        prefs.getString('app_token') ?? prefs.getString('auth_token');
    if (token == null || token.isEmpty) return true; // can't check — allow ring
    final resp = await http
        .get(
          Uri.parse(
              '${baseUrl}signaling.php?action=call_status&call_id=$callId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 4));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final status = data['call']?['status']?.toString();
      if (status != null && status != 'ringing' && status != 'accepted') {
        return false;
      }
    }
  } catch (_) {}
  return true; // on any error, allow the ring (safe default)
}

/// Background message handler — must be a top-level function with this pragma.
/// Registered in main() BEFORE runApp() so it works when the app is killed.
@pragma('vm:entry-point')
Future<void> fcmBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data.isEmpty) return;

  // Block nearby from blocked users even in background.
  final type = message.data['type']?.toString();
  if (type == 'nearby') {
    final senderId = message.data['sender_id']?.toString() ?? '';
    if (senderId.isNotEmpty &&
        await NearbyBlockService.instance.isBlocked(senderId)) {
      return;
    }
  }

  // For call notifications: verify the call is still ringing before showing the
  // tray. FCM can arrive late on OEM devices (Xiaomi/Oppo/Samsung battery kill).
  final action = message.data['action']?.toString();
  final isCall = (action == 'incoming_call' || type == 'incoming_call');
  if (isCall) {
    final callId = int.tryParse(message.data['call_id']?.toString() ?? '0') ?? 0;
    if (callId > 0) {
      final stillRinging = await _bgCheckCallRinging(callId);
      if (!stillRinging) return; // Call already ended — don't ring
    }
  }

  // All messages are now data-only from the server — always show tray manually.
  // This is more reliable than relying on Android's auto-display of notification
  // payloads, which many OEM devices (Xiaomi, Oppo, etc.) silently suppress.
  await FCMService.createChannels();
  await FCMService._ensureLocalNotificationsReady();
  await FCMService.showTray(message.data);
  // NOTE: Do NOT call _handleNotificationData here — navigator/UI context does
  // not exist in a background isolate. Routing happens via onMessageOpenedApp.
}

/// Tracks when a nearby alert was last shown for a given sender ID to prevent spam.
final Map<String, DateTime> _lastNearbyAlerts = {};

/// Tracks the currently visible nearby alert route so new ones replace it.
Route<dynamic>? _currentNearbyRoute;

/// Tracks viewed gift notification IDs so we don't auto-navigate again.
const String _viewedGiftIdsKey = 'viewed_gift_notification_ids';

/// Check if a gift notification was already viewed.
Future<bool> _wasGiftViewed(String giftId) async {
  if (giftId.isEmpty) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final viewed = prefs.getStringList(_viewedGiftIdsKey) ?? [];
    return viewed.contains(giftId);
  } catch (_) {
    return false;
  }
}

/// Mark a gift notification as viewed.
Future<void> _markGiftViewed(String giftId) async {
  if (giftId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final viewed = prefs.getStringList(_viewedGiftIdsKey) ?? [];
    if (!viewed.contains(giftId)) {
      viewed.add(giftId);
      // Keep only last 100 to avoid unbounded growth
      if (viewed.length > 100) viewed.removeAt(0);
      await prefs.setStringList(_viewedGiftIdsKey, viewed);
    }
  } catch (_) {}
}

/// Public entry point so OneSignal (and other services) can reuse the same routing.
void handleNotificationData(
  Map<String, dynamic> data, {
  bool autoAccept = false,
  bool isFromTap = false,
}) =>
    _handleNotificationData(data, autoAccept: autoAccept, isFromTap: isFromTap);

/// Helper to parse and route the notification data
void _handleNotificationData(
  Map<String, dynamic> data, {
  bool autoAccept = false,
  bool isFromTap = false,
}) {
  final action = data['action']?.toString();
  final type = data['type']?.toString();

  bool isCall = (action == 'incoming_call' || type == 'incoming_call');

  // 1. Handle Calling logic (Zego/Signaling)
  if (isCall) {
    final callerName = data['caller_full_name']?.toString() ??
        data['caller_name']?.toString() ??
        'Unknown';
    final callId = int.tryParse(data['call_id']?.toString() ?? '0') ?? 0;
    final callUuid = data['call_uuid']?.toString() ?? '';

    final callData = {
      'call_id': callId,
      'call_uuid': callUuid,
      'caller_id': data['caller_id'],
      'caller_name': callerName,
      'caller_full_name': callerName,
      'caller_avatar': data['caller_avatar'] ?? '',
      'type': data['type'] ?? 'video',
      'is_random': data['is_random'] == 'true' || data['is_random'] == true,
      'auto_accept': autoAccept,
    };

    // If app is foreground and listener is active, verify call is still ringing first
    if (SignalingService.instance.onIncomingCall != null && !isFromTap) {
      if (callId > 0) {
        SignalingService.instance.checkCallStatus(callId).then((status) {
          if (status != null && status != 'ringing' && status != 'accepted') return;
          SignalingService.instance.onIncomingCall?.call(callData);
        });
      } else {
        SignalingService.instance.onIncomingCall?.call(callData);
      }
      return;
    }

    // Otherwise (Background/Killed or from Tap), navigate directly
    _navigateToCallWithRetry(callId, callUuid, callerName, data, autoAccept);
    return;
  }

  // 2. Handle Navigation/Routing if from a Tray Tap (Non-Call)
  if (type == 'nearby') {
    final senderId = data['sender_id']?.toString() ?? '';
    final senderName = data['sender_name']?.toString() ??
        data['title']?.toString() ??
        'Nearby User';
    final senderAvatar = data['sender_avatar']?.toString() ?? '';
    final senderDistance = data['sender_distance']?.toString() ?? '';
    final senderAge = data['sender_age']?.toString() ?? '';
    final senderGender = data['sender_gender']?.toString().toLowerCase() ?? '';

    if (senderId.isEmpty) return;

    if (isFromTap) {
      _navigateToScreenWithRetry(type, action,
          senderId: senderId, customData: data);
      return;
    }

    // Block-check runs async; navigation happens inside the callback.
    NearbyBlockService.instance.isBlocked(senderId).then((blocked) {
      if (blocked) return;

      // Gender filter: skip same-gender alerts when sender_gender is provided.
      if (senderGender.isNotEmpty) {
        SharedPreferences.getInstance().then((prefs) {
          final myGender =
              (prefs.getString('user_gender') ?? '').toLowerCase();
          if (myGender.isNotEmpty && myGender == senderGender) return;
          _showNearbyAlert(
              senderId, senderName, senderAvatar, senderDistance, senderAge);
        });
        return;
      }

      _showNearbyAlert(
          senderId, senderName, senderAvatar, senderDistance, senderAge);
    });
  } else if (type == 'proposal_accepted') {
    // Show "It's a Match!" toast and navigate to chat on tap
    final senderName = data['sender_name']?.toString() ??
        data['title']?.toString() ??
        'Someone';
    try {
      final context = navigatorKey.currentState?.context;
      if (context != null && context.mounted) {
        NeonToast.success(
          context,
          '💕 $senderName accepted your proposal! Tap to chat.',
          onTap: () => _navigateToScreenWithRetry(type, action,
              senderId: data['sender_id']?.toString()),
        );
      }
    } catch (_) {}

    if (isFromTap) {
      _navigateToScreenWithRetry(type, action,
          senderId: data['sender_id']?.toString());
    }
  } else if (type == 'proposal') {
    // Someone sent us a new proposal â€“ show toast if they want to tap it
    final senderName = data['sender_name']?.toString() ??
        data['title']?.toString() ??
        'Someone';
    final senderAvatar = data['sender_avatar']?.toString() ?? '';
    final senderId = data['sender_id']?.toString() ?? '';

    try {
      final context = navigatorKey.currentState?.context;
      if (context != null && context.mounted) {
        NeonToast.info(
          context,
          'â¤ï¸ $senderName sent you a proposal!',
          onTap: () => _navigateToScreenWithRetry(type, action,
              senderId: senderId, customData: data),
        );
      }
    } catch (_) {}

    // Automatically push the alert screen if foreground/tapped
    if (senderId.isNotEmpty) {
      if (isFromTap) {
        _navigateToScreenWithRetry(type, action,
            senderId: senderId, customData: data);
        return;
      }

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => ProposalAlertScreen(
              senderId: senderId,
              senderName: senderName,
              senderAvatar: senderAvatar,
            ),
          ),
        );
      }
    }
  } else if (type == 'gift') {
    // Gift notification: skip auto-navigate if already viewed
    final giftId = data['gift_id']?.toString() ??
        data['notification_id']?.toString() ??
        data['sender_id']?.toString() ??
        '';
    if (giftId.isNotEmpty) {
      _wasGiftViewed(giftId).then((viewed) {
        if (!viewed) {
          _navigateToScreenWithRetry(
            type,
            action,
            senderId: data['sender_id']?.toString(),
          );
        }
      });
    }
  } else if (isFromTap) {
    _navigateToScreenWithRetry(
      type,
      action,
      senderId: data['sender_id']?.toString(),
      customData: data,
    );
  }
}

/// Shows the NearbyAlertScreen with spam-prevention (once per sender per 12 h).
void _showNearbyAlert(String senderId, String senderName, String senderAvatar,
    String senderDistance, String senderAge,
    [int attempts = 0]) {
  final now = DateTime.now();
  final last = _lastNearbyAlerts[senderId];
  if (last != null && now.difference(last).inHours < 12) return;

  if (navigatorKey.currentState != null) {
    _lastNearbyAlerts[senderId] = now;

    // Remove the previous nearby alert if one is still on screen
    if (_currentNearbyRoute != null) {
      navigatorKey.currentState!.removeRoute(_currentNearbyRoute!);
      _currentNearbyRoute = null;
    }

    final route = MaterialPageRoute(
      builder: (_) => NearbyAlertScreen(
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        senderDistance: senderDistance,
        senderAge: senderAge,
      ),
    );
    _currentNearbyRoute = route;
    navigatorKey.currentState!.push(route).then((_) {
      if (_currentNearbyRoute == route) _currentNearbyRoute = null;
    });
  } else if (attempts < 10) {
    // Navigator not ready yet (app just launched) — retry up to 5 s.
    Future.delayed(
      const Duration(milliseconds: 500),
      () => _showNearbyAlert(
          senderId, senderName, senderAvatar, senderDistance, senderAge, attempts + 1),
    );
  }
}

/// Helper to wait for Navigator to be ready before pushing
void _navigateToCallWithRetry(int callId, String callUuid, String callerName,
    Map<String, dynamic> data, bool autoAccept,
    [int attempts = 0]) {
  if (navigatorKey.currentState != null) {
    final session = CallSession(
      id: callUuid,
      callerId: data['caller_id']?.toString() ?? '',
      callerName: callerName,
      callerAvatar: data['caller_avatar'] ?? '',
      receiverId: '',
      receiverName: 'You',
      type: (data['type'] == 'audio') ? CallType.audio : CallType.video,
      state: CallState.incoming,
      isRandomCall: data['is_random'] == 'true' || data['is_random'] == true,
    );

    // â”€â”€ CHECK STATUS BEFORE NAV â”€â”€
    SignalingService.instance.checkCallStatus(callId).then((status) {
      // null = network error — attempt anyway; only block definitively ended calls
      if (status != null && status != 'ringing' && status != 'accepted') {
        if (navigatorKey.currentContext != null) {
          NeonToast.error(
              navigatorKey.currentContext!, 'This call has already ended');
        }
        return;
      }

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => WebRTCCallScreen(
              callSession: session,
              isOutgoing: false,
              serverCallId: callId,
              autoAcceptCall: autoAccept,
            ),
          ),
        );
      }
    });
  } else if (attempts < 10) {
    Future.delayed(
        const Duration(milliseconds: 500),
        () => _navigateToCallWithRetry(
            callId, callUuid, callerName, data, autoAccept, attempts + 1));
  }
}

void _navigateToScreenWithRetry(String? type, String? action,
    {String? senderId, Map<String, dynamic>? customData, int attempts = 0}) {
  if (navigatorKey.currentState != null) {
    Widget target;
    switch (type) {
      case 'chat':
        target = const ChatListScreen();
        break;
      case 'gift':
        // If we have a senderId, redirect to profile as requested
        if (senderId != null && senderId.isNotEmpty && senderId != '0') {
          target = ProfileScreen(userId: senderId);
        } else {
          // Check if gift notification was already viewed — skip auto-navigate
          // This prevents the gift page from showing again after the user already saw it.
          // The actual check is async, so we navigate anyway but the screen itself
          // will handle the "already viewed" state. However, for push-notification
          // auto-navigate we want to suppress it entirely.
          target = const GiftsNotificationScreen();
        }
        break;
      case 'like':
      case 'comment':
      case 'comment_reply':
        final postId = customData?['reference_id']?.toString() ??
            customData?['post_id']?.toString() ?? '';
        if (postId.isNotEmpty && postId != '0') {
          target = PostDetailScreen(postId: postId);
        } else if (senderId != null && senderId.isNotEmpty && senderId != '0') {
          target = ProfileScreen(userId: senderId);
        } else {
          target = const NotificationsScreen();
        }
        break;
      case 'follow':
        if (senderId != null && senderId.isNotEmpty && senderId != '0') {
          target = ProfileScreen(userId: senderId);
        } else {
          target = const NotificationsScreen();
        }
        break;
      case 'nearby':
        // Show the alert popup with sender info when available, else the map.
        final nearbySenderId = senderId ?? customData?['sender_id']?.toString() ?? '';
        if (nearbySenderId.isNotEmpty) {
          target = NearbyAlertScreen(
            senderId: nearbySenderId,
            senderName: customData?['sender_name']?.toString() ??
                customData?['title']?.toString() ??
                'Nearby User',
            senderAvatar: customData?['sender_avatar']?.toString() ?? '',
            senderDistance: customData?['sender_distance']?.toString() ?? '',
            senderAge: customData?['sender_age']?.toString() ?? '',
          );
        } else {
          target = const NearbyScreen();
        }
        break;
      case 'proposal':
        // Someone sent us a proposal â€” redirect to the alert screen
        if (senderId != null && senderId.isNotEmpty) {
          final senderName = customData?['sender_name']?.toString() ??
              customData?['title']?.toString() ??
              'Someone';
          final senderAvatar = customData?['sender_avatar']?.toString() ?? '';
          target = ProposalAlertScreen(
            senderId: senderId,
            senderName: senderName,
            senderAvatar: senderAvatar,
          );
        } else {
          target = const ProposalsScreen();
        }
        break;
      case 'proposal_accepted':
        // Our proposal was accepted â€” redirect to the proposals screen (Accepted tab visible)
        target = const ProposalsScreen();
        break;
      case 'live_invite':
        final hostId = senderId ?? customData?['sender_id']?.toString() ?? '';
        final hostName = customData?['sender_name']?.toString() ?? 'Host';
        final hostAvatar = customData?['sender_avatar']?.toString() ?? '';
        target = hostId.isNotEmpty
            ? LiveRoomScreen(userId: hostId, userName: hostName, userAvatar: hostAvatar)
            : const NotificationsScreen();
        break;
      case 'kyc_accept':
      case 'kyc_reject':
        target = const KycScreen();
        break;
      case 'wallet_accept':
      case 'wallet_reject':
      case 'deposit_accept':
      case 'deposit_reject':
        target = const WalletScreen();
        break;
      default:
        target = const NotificationsScreen();
    }
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => target));
  } else if (attempts < 10) {
    Future.delayed(
        const Duration(milliseconds: 500),
        () => _navigateToScreenWithRetry(type, action,
            senderId: senderId,
            customData: customData,
            attempts: attempts + 1));
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  static FCMService get instance => _instance;

  FCMService._internal();

  bool _setupComplete = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  // Tracks whether _localNotifications.initialize() has been called in THIS isolate.
  // Background isolates have their own memory, so this starts false there too —
  // showTray initializes on first call in any isolate.
  static bool _localNotificationsReady = false;

  /// Called by home_screen so FCM can trigger an immediate badge refresh
  /// when a foreground notification arrives (instead of waiting for the poll).
  static VoidCallback? onNotificationReceived;

  static Future<void> _ensureLocalNotificationsReady() async {
    if (_localNotificationsReady) return;
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    await _localNotifications.initialize(
      const InitializationSettings(android: initAndroid),
    );
    _localNotificationsReady = true;
  }

  static Future<void> showTray(Map<String, dynamic> data) async {
    try {
      await _ensureLocalNotificationsReady();
      final type = data['type']?.toString() ?? '';
      final action = data['action']?.toString() ?? '';

      final settings = await SettingsStore.getInstance();
      final enabled = await settings.getNotificationsEnabled();
      if (!enabled && type != 'nearby') return;

      bool isCall = (action == 'incoming_call' || type == 'incoming_call');

      // --- Build title / body ---
      final senderName = (data['sender_name'] ?? '').toString().trim();
      final rawTitle = (data['title'] ?? 'Goreto').toString().trim();
      final rawBody = (data['body'] ?? 'You have a new notification').toString().trim();

      // Use sender name as the headline when present (feels personal)
      String notifTitle = senderName.isNotEmpty ? senderName : rawTitle;
      // Body = the action text; strip sender name prefix if backend already put it there
      String notifBody = rawBody;
      if (senderName.isNotEmpty && notifBody.toLowerCase().startsWith(senderName.toLowerCase())) {
        notifBody = notifBody.substring(senderName.length).replaceFirst(RegExp(r'^[\s,]+'), '');
      }
      if (notifBody.isEmpty) notifBody = rawTitle;

      // Stable notification ID so same-type alerts overwrite instead of stack
      final int notifId = isCall
          ? 999999
          : type == 'nearby'
              ? 888888
              : ((type + (data['sender_id'] ?? '') + (data['reference_id'] ?? '')).hashCode.abs() % 100000) + 1;

      // --- Load sender avatar as large icon ---
      final avatarUrl = (data['sender_avatar'] ?? '').toString().trim();
      AndroidBitmap<Object>? largeIcon;
      if (avatarUrl.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(avatarUrl))
              .timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            largeIcon = ByteArrayAndroidBitmap(resp.bodyBytes);
          }
        } catch (_) {}
      }

      // --- Style: BigText so the full message shows on expand ---
      final styleInfo = BigTextStyleInformation(
        notifBody,
        htmlFormatBigText: false,
        contentTitle: notifTitle,
        htmlFormatContentTitle: false,
        summaryText: 'Goreto',
        htmlFormatSummaryText: false,
      );

      final String channelId = isCall
          ? 'call_v1'
          : (type == 'nearby' ? 'nearby_v1' : 'general_v1');
      final String channelName = isCall
          ? 'Incoming Calls'
          : (type == 'nearby' ? 'Nearby Alerts' : 'Notifications');
      final RawResourceAndroidNotificationSound channelSound = isCall
          ? const RawResourceAndroidNotificationSound('ringtone')
          : (type == 'nearby'
              ? const RawResourceAndroidNotificationSound('nearby')
              : const RawResourceAndroidNotificationSound('notify'));

      await _localNotifications.show(
        notifId,
        notifTitle,
        notifBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: isCall
                ? 'Incoming call ringtone alerts'
                : (type == 'nearby'
                    ? 'Alerts when someone is nearby'
                    : 'General Goreto notifications'),
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            when: DateTime.now().millisecondsSinceEpoch,
            enableVibration: true,
            playSound: true,
            autoCancel: !isCall,
            ongoing: isCall,
            sound: channelSound,
            fullScreenIntent: isCall || type == 'nearby',
            category: isCall
                ? AndroidNotificationCategory.call
                : AndroidNotificationCategory.social,
            color: const Color(0xFFEC4899),
            icon: 'ic_stat_goreto',
            largeIcon: largeIcon,
            styleInformation: styleInfo,
            subText: senderName.isNotEmpty ? rawTitle : null,
            actions: isCall
                ? [
                    const AndroidNotificationAction(
                      'accept_call',
                      'Accept',
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                    const AndroidNotificationAction(
                      'decline_call',
                      'Decline',
                      showsUserInterface: false,
                      cancelNotification: true,
                    ),
                  ]
                : null,
          ),
        ),
        payload: jsonEncode(data),
      );
    } catch (e) {}
  }

  /// Dismiss the call tray notification (fixed ID 999999)
  static Future<void> dismissCallNotification() async {
    try {
      await _localNotifications.cancel(999999);
    } catch (e) {}
  }

  static Future<void> createChannels() async {
    const AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
      'general_v1',
      'Notifications',
      description: 'General Goreto notifications.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notify'),
      enableVibration: true,
    );

    const AndroidNotificationChannel nearbyChannel = AndroidNotificationChannel(
      'nearby_v1',
      'Nearby Alerts',
      description: 'Alerts when someone is nearby.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('nearby'),
      enableVibration: true,
    );

    final AndroidNotificationChannel callChannel = AndroidNotificationChannel(
      'call_v1',
      'Incoming Calls',
      description: 'Incoming call ringtone alerts.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('ringtone'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
    );

    final plugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await plugin?.createNotificationChannel(generalChannel);
    await plugin?.createNotificationChannel(nearbyChannel);
    await plugin?.createNotificationChannel(callChannel);
  }

  Future<void> init() async {
    if (_setupComplete) {
      await triggerTokenSync();
      return;
    }

    try {
      final status = await Permission.notification.request();

      if (status.isDenied || status.isPermanentlyDenied) {
        Future.delayed(const Duration(seconds: 3), () {
          final context = navigatorKey.currentState?.context;
          if (context != null && context.mounted) {
            NeonToast.error(
              context,
              'System Tray is DISABLED. Please enable Notifications in Settings to see alerts outside the app.',
            );
          }
        });
      }

      await createChannels();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      try {
        await _localNotifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse details) {
            Map<String, dynamic> data = {};
            if (details.payload != null && details.payload!.isNotEmpty) {
              try {
                data = Map<String, dynamic>.from(jsonDecode(details.payload!));
              } catch (e) {}
            }

            if (details.actionId == 'accept_call') {
              _handleNotificationData(data, autoAccept: true, isFromTap: true);
            } else if (details.actionId == 'decline_call') {
              final callId = int.tryParse(data['call_id']?.toString() ?? '');
              if (callId != null) {
                SignalingService.instance.declineCall(callId);
              }
            } else {
              _handleNotificationData(data, isFromTap: true);
            }
          },
        );
        _localNotificationsReady = true;
      } catch (e) {}

      FirebaseMessaging messaging = FirebaseMessaging.instance;
      messaging.onTokenRefresh.listen(syncTokenToServer);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final data = message.data;

        final type = data['type']?.toString();
        final action = data['action']?.toString();

        // Suppress nearby notifications for blocked users before showing tray or alert.
        if (type == 'nearby') {
          final senderId = data['sender_id']?.toString() ?? '';
          if (senderId.isNotEmpty) {
            final blocked =
                await NearbyBlockService.instance.isBlocked(senderId);
            if (blocked) return;
          }
        }

        bool isCall = (action == 'incoming_call' || type == 'incoming_call');
        bool hasForegroundReceiver =
            SignalingService.instance.onIncomingCall != null;

        // Only show system tray if it's NOT a call OR if there's no active foreground receiver
        if (!isCall || !hasForegroundReceiver) {
          showTray(data);
        }

        _handleNotificationData(data, autoAccept: false);

        // Immediately refresh the notification badge count in home_screen
        if (!isCall) onNotificationReceived?.call();

        // Global settings check for in-app Toast
        final settings = await SettingsStore.getInstance();
        final enabled = await settings.getNotificationsEnabled();
        if (!enabled && type != 'nearby') {
          return;
        }

        // Handle chat_session_started — receiver sees a coin animation toast.
        if (type == 'chat_session' ||
            action == 'chat_session_started' ||
            data['action'] == 'chat_session_started') {
          final coinsPaid = data['coins_paid']?.toString() ?? '0';
          final buyerName = data['buyer_name']?.toString() ?? 'Someone';
          final mins = data['minutes']?.toString() ?? '?';
          final ctx = navigatorKey.currentState?.context;
          if (ctx != null && ctx.mounted) {
            NeonToast.success(
              ctx,
              coinsPaid != '0'
                  ? '$buyerName started a $mins-min chat • +$coinsPaid coins'
                  : '$buyerName started a $mins-min free chat',
            );
          }
          return;
        }

        // Skip generic toast for types that are handled specifically in _handleNotificationData
        if (type == 'nearby' ||
            type == 'incoming_call' ||
            type == 'proposal' ||
            type == 'proposal_accepted') {
          return;
        }

        final title =
            message.notification?.title ?? data['title'] ?? 'New Alert';
        String body = message.notification?.body ??
            data['body'] ??
            'You have a new notification';

        // Show in-app Toast (Safely)
        try {
          final context = navigatorKey.currentState?.context;
          if (context != null && context.mounted) {
            NeonToast.info(
              context,
              '$title\n$body',
              imageUrl: message.data['sender_avatar']?.toString(),
              onTap: () => _handleNotificationData(data, isFromTap: true),
            );
          }
        } catch (e) {}
      });

      // Request FCM permissions (extra layer for iOS/Android 13+)
      NotificationSettings fcmSettings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Initial message open from killed state — user tapped the notification.
      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && initialMessage.data.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), () {
          _handleNotificationData(initialMessage.data,
              autoAccept: true, isFromTap: true);
        });
      }

      // Background message open handler
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data.isNotEmpty) {
          _handleNotificationData(
            message.data,
            autoAccept: true,
            isFromTap: true,
          );
        }
      });

      // Background handler is registered in main() before runApp() — do not re-register here.

      _setupComplete = true;
      await triggerTokenSync();
    } catch (e) {}
  }

  /// Public wrapper to mark a gift notification as viewed.
  static Future<void> markGiftViewed(String giftId) => _markGiftViewed(giftId);

  /// Public wrapper to check if a gift notification was already viewed.
  static Future<bool> wasGiftViewed(String giftId) => _wasGiftViewed(giftId);

  Future<void> triggerTokenSync() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await syncTokenToServer(token);
      }
    } catch (e) {}
  }

  Future<void> syncTokenToServer(String token) async {
    try {
      final dio = await ApiService().getDioClient();

      // Forcefully fetch token from SharedPreferences to avoid interceptor race/cache issues
      final prefs = await SharedPreferences.getInstance();
      final authToken =
          prefs.getString('auth_token') ?? prefs.getString('app_token');

      if (authToken == null || authToken.isEmpty) {
        return;
      }

      final response = await dio.post(
        'api_auth.php',
        data: {'action': 'update_fcm_token', 'fcm_token': token},
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );
    } on DioException catch (_) {
    } catch (_) {}
  }
}

int min(int a, int b) => a < b ? a : b;
