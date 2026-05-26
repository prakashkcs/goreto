import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gradient_borders/gradient_borders.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/widgets/video_feed_item.dart';
import 'package:love_vibe_pro/widgets/photo_feed_item.dart';
import 'package:love_vibe_pro/screens/live/live_preview_screen.dart';
import 'package:love_vibe_pro/screens/live/live_room_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/reels_screen.dart';
import 'package:love_vibe_pro/screens/story_view_screen.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:simple_gradient_text/simple_gradient_text.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:love_vibe_pro/screens/publish_post_screen.dart';
import 'package:love_vibe_pro/screens/match_tab.dart';
import 'package:love_vibe_pro/screens/story/story_editor_screen.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/settings/settings_screen.dart';
import 'package:love_vibe_pro/screens/chat/chat_list_screen.dart';
import 'package:love_vibe_pro/widgets/login_required_sheet.dart';
import 'package:love_vibe_pro/widgets/gift_preview_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/post_call_bottom_sheet.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/controllers/feed_controller.dart';

import 'package:love_vibe_pro/services/signaling_service.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/chat/call/webrtc_call_screen.dart';
import 'package:love_vibe_pro/screens/notifications/notifications_screen.dart';
import 'package:love_vibe_pro/services/notification_service.dart';
import 'package:love_vibe_pro/services/permission_service.dart';
import 'package:love_vibe_pro/screens/search_screen.dart';
import 'package:love_vibe_pro/screens/video_recorder_screen.dart';
import 'package:love_vibe_pro/services/ad_service.dart';
import 'package:love_vibe_pro/widgets/ads/feed_ad_card.dart';
import 'package:love_vibe_pro/services/eye_blink_service.dart';
import 'package:love_vibe_pro/services/settings_store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Feed widgets call this to jump to the Profile tab instead of pushing a
  /// new route for the current user's own profile.
  static void Function()? switchToProfileTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _storyPlaceholderAsset =
      'assets/placeholders/story_placeholder.svg';

  // Static card decorations — created once, reused for every feed item
  static final BoxDecoration _videoCardDecoration = BoxDecoration(
    borderRadius: const BorderRadius.all(Radius.circular(20)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF3B82F6).withValues(alpha: 0.18),
        const Color(0xFFD946EF).withValues(alpha: 0.10),
      ],
    ),
    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static final BoxDecoration _photoCardDecoration = BoxDecoration(
    borderRadius: const BorderRadius.all(Radius.circular(20)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFD946EF).withValues(alpha: 0.12),
        const Color(0xFF06B6D4).withValues(alpha: 0.08),
      ],
    ),
    border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.20)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFD946EF).withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  final AudioPlayer _preloadPlayer = AudioPlayer();
  final ScrollController _feedScrollController = ScrollController();
  int _currentIndex = 0;
  List<dynamic> _stories = [];
  List<dynamic> _homeLiveUsers = [];
  final ApiService _apiService = ApiService();
  final FeedController _feedController = FeedController.instance;
  final ProfileService _profileService = ProfileService.instance;
  final ImagePicker _picker = ImagePicker();
  late Future<UserProfile?> _currentUserProfileFuture;

  Timer? _pollingTimer;
  Timer? _locationTimer;

  List<Map<String, dynamic>> get _feed => _feedController.items;
  bool get _isLoading => _feedController.isLoading;
  bool _permissionsGranted = false;
  bool _locationUpdatesStarted = false;
  bool _blinkEnabled = false;

  // Persistent tab screens — never recreated on tab switch
  late final Widget _profileScreen;
  late final Widget _chatListScreen;

  Future<void> _openReelsTab() async {
    SoundService().playReact();
    EyeBlinkService.instance.stop();
    if (mounted) setState(() => _blinkEnabled = false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (p1_0) => ReelsScreen(
          onBack: () {
            if (mounted) {
              setState(() => _currentIndex = 0);
            }
          },
        ),
      ),
    );
  }

  // Removed _openLiveReelsTab from home_screen

  @override
  void initState() {
    super.initState();
    _profileScreen = const ProfileScreen();
    _chatListScreen = const ChatListScreen();
    HomeScreen.switchToProfileTab = () {
      if (mounted) _onTabTapped(4);
    };
    _checkPermissions();
    _currentUserProfileFuture = _profileService.getCachedOrFetchCurrentUser();

    // Priority: render feed ASAP
    _fetchData(force: false);

    // Defer non-critical services to avoid blocking the first frame
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _preloadPlayer.setSource(AssetSource('notify.mp3'));
      _startLivePolling();
      _startIncomingCallPolling();
      _processOfflineGiftNotifications();
    });

    // â”€â”€ Global location update (nearby notifications on ALL tabs) â”€â”€
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _startGlobalLocationUpdates();
    });

    _initBlinkService();
  }

  Future<void> _initBlinkService() async {
    final store = await SettingsStore.getInstance();
    if (!await store.getEyeBlinkScrollEnabled() || !mounted) return;

    final svc = EyeBlinkService.instance;
    svc.closedThreshold = await store.getBlinkClosedThreshold();
    svc.openThreshold   = await store.getBlinkOpenThreshold();
    svc.cooldownMs      = await store.getBlinkCooldownMs();
    svc.doubleWindowMs  = await store.getBlinkDoubleWindowMs();

    final started = await svc.start(onSingleBlink: _scrollFeedNext);
    if (mounted) setState(() => _blinkEnabled = started);
  }

  Future<void> _checkPermissions() async {
    try {
      // Always request permissions on first open
      final status =
          await PermissionService.instance.requestEssentialPermissions();
      final hasPermissions =
          status.isNotEmpty && status.values.every((s) => s.isGranted);

      final hasNearby = await PermissionService.instance.hasNearbyPermissions();

      if (mounted) {
        setState(() {
          _permissionsGranted = hasPermissions;
        });

        if (hasNearby && !_locationUpdatesStarted) {
          _locationUpdatesStarted = true;
          _startGlobalLocationUpdates();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _permissionsGranted = true;
        });
      }
    }
  }

  void _startGlobalLocationUpdates() {
    _doLocationUpdate();
    _locationTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted) {
        _locationTimer?.cancel();
        return;
      }
      _doLocationUpdate();
    });
  }

  Future<void> _doLocationUpdate() async {
    if (!mounted) return;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (!auth.isAuthenticated || auth.isGuest) {
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      await _apiService.updateUserLocation(pos.latitude, pos.longitude);
    } catch (e) {}
  }

  Future<void> _fetchHomeLiveUsers() async {
    try {
      final lives = await _apiService.getLiveUsers();
      if (!mounted) return;
      setState(() => _homeLiveUsers = lives);
    } catch (_) {}
  }

  void _startLivePolling() {
    // Let FCMService trigger an immediate badge refresh when a foreground
    // notification arrives, so the badge updates without waiting for the poll.
    FCMService.onNotificationReceived = _fetchLiveAppNotifications;

    _processOfflineGiftNotifications();
    _fetchLiveAppNotifications();
    _fetchHomeLiveUsers();

    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) {
        _pollingTimer?.cancel();
        return;
      }
      _processOfflineGiftNotifications();
      _fetchLiveAppNotifications();
      _fetchHomeLiveUsers();
    });
  }

  int? _handledCallId; // Guard against duplicate incoming call dialogs
  Route<dynamic>? _activeCallDialogRoute;

  void _startIncomingCallPolling() {
    final signaling = SignalingService.instance;

    signaling.dismissActiveCallDialog = () {
      if (_activeCallDialogRoute != null && _activeCallDialogRoute!.isActive) {
        Navigator.of(context).removeRoute(_activeCallDialogRoute!);
        _activeCallDialogRoute = null;
        _handledCallId = null; // Reset it so future calls can ring again
      }
    };

    signaling.onIncomingCall = (call) {
      if (!mounted) return;
      final callId = int.tryParse(call['call_id'].toString()) ?? 0;
      final callUuid = call['call_uuid']?.toString() ?? '';

      // Prevent showing the same call dialog multiple times
      if (_handledCallId == callId) return;
      _handledCallId = callId;

      final callerName = call['caller_full_name']?.toString() ??
          call['caller_name']?.toString() ??
          'Unknown';
      final callerAvatar = call['caller_avatar']?.toString();
      final callType =
          call['type'] == 'video' ? CallType.video : CallType.audio;
      final isRandom = call['is_random'] == true;

      final session = CallSession(
        id: callUuid, // Use the call_uuid so receiver joins the same Zego room
        callerId: call['caller_id'].toString(),
        callerName: callerName,
        callerAvatar: callerAvatar,
        receiverId: '',
        receiverName: 'You',
        type: callType,
        state: CallState.incoming,
        isRandomCall: isRandom,
      );

      final autoAccept = call['auto_accept'] == true;

      // Haptic feedback for incoming call

      if (autoAccept) {
        // User tapped notification directly, auto-accept
        _navigateToCallScreen(session, callId);
        return;
      }

      // Show incoming call notification overlay
      bool isDialogVisible = true;
      Timer? statusTimer;

      // Capture the route so we can dismiss it from startIncomingCallPolling
      _activeCallDialogRoute = RawDialogRoute(
        barrierDismissible: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, __) {
          // Poll call status to auto-dismiss if caller hangs up
          statusTimer = Timer.periodic(const Duration(seconds: 3), (
            timer,
          ) async {
            if (!isDialogVisible) {
              timer.cancel();
              return;
            }
            final status = await signaling.checkCallStatus(callId);
            if (status == 'ended' ||
                status == 'missed' ||
                status == 'declined') {
              isDialogVisible = false;
              timer.cancel();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                if (mounted) {
                  NeonToast.error(context, 'Missed call from $callerName');
                }
              }
            }
          });

          // Auto-dismiss after 30 seconds
          Future.delayed(const Duration(seconds: 30), () {
            if (isDialogVisible && ctx.mounted) {
              isDialogVisible = false;
              statusTimer?.cancel();
              signaling.declineCall(callId);
              Navigator.of(ctx).pop();
              if (mounted) {
                NeonToast.error(context, 'Missed call from $callerName');
              }
            }
          });

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 60,
            ),
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isRandom
                      ? const [
                          Color(0xFF2E1E3E),
                          Color(0xFF1C122C),
                        ] // Purple tint for random
                      : const [Color(0xFF1E1E2E), Color(0xFF12121C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: (isRandom
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFFD946EF))
                      .withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isRandom
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFFD946EF))
                        .withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Label
                  Row(
                    children: [
                      Icon(
                        isRandom
                            ? Icons.shuffle
                            : (callType == CallType.video
                                ? Icons.videocam
                                : Icons.call),
                        color: isRandom
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFF22C55E),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRandom
                            ? 'Incoming Random Call'
                            : (callType == CallType.video
                                ? 'Incoming Video Call'
                                : 'Incoming Audio Call'),
                        style: TextStyle(
                          color: isRandom
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF22C55E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Caller info row
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFD946EF),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: callerAvatar != null && callerAvatar.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: callerAvatar,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: const Color(0xFF2A2A2A),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white38,
                                      size: 24,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: const Color(0xFF2A2A2A),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white38,
                                      size: 24,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: const Color(0xFF2A2A2A),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white38,
                                    size: 24,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name
                      Expanded(
                        child: Text(
                          callerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Buttons
                  Row(
                    children: [
                      // Decline
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            isDialogVisible = false;
                            statusTimer?.cancel();
                            signaling.declineCall(callId);
                            Navigator.of(ctx).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.call_end,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Decline',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Accept
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            isDialogVisible = false;
                            statusTimer?.cancel();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _navigateToCallScreen(session, callId);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF22C55E,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.call, color: Colors.white, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'Accept',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (mounted) {
        Navigator.of(context).push(_activeCallDialogRoute!);
      }
    };
    signaling.startIncomingCallPolling();
  }

  Future<void> _navigateToCallScreen(CallSession session, int callId) async {
    // 1. Check status one last time to prevent entry into ended/canceled calls
    final status = await SignalingService.instance.checkCallStatus(callId);
    if (status != 'ringing') {
      if (mounted) {
        NeonToast.error(context, 'This call has already ended');
      }
      // If we are coming from a dialog, it will be auto-dismissed by statusTimer eventually,
      // but we should reset handledCallId so it can be re-triggered if needed.
      _handledCallId = null;
      return;
    }

    // 2. Clear active dialog if any
    SignalingService.instance.dismissActiveCallDialog?.call();

    if (!mounted) return;

    final duration = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (p2_0) => WebRTCCallScreen(
          callSession: session,
          isOutgoing: false,
          serverCallId: callId,
          autoAcceptCall:
              true, // User already accepted from dialog/notification
        ),
      ),
    );

    if (duration != null && duration is int && duration >= 0) {
      final m = duration ~/ 60;
      final s = duration % 60;
      if (mounted) {
        NeonToast.success(
          context,
          'Call ended â€¢ $m:${s.toString().padLeft(2, '0')}',
        );

        if (session.isRandomCall) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              PostCallBottomSheet.show(
                context,
                session,
                Duration(seconds: duration),
              );
            }
          });
        }
      }
    }
  }

  int _unreadNotificationCount = 0;

  Future<void> _fetchLiveAppNotifications() async {
    if (!mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated || auth.isGuest) return;

    try {
      final count = await NotificationService().getUnreadCount();
      if (mounted && count != _unreadNotificationCount) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (e) {}
  }

  Future<void> _processOfflineGiftNotifications() async {
    if (!mounted) return;

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (!auth.isAuthenticated || auth.isGuest) return;

      final notifications = await _apiService.fetchGiftNotifications();
      if (notifications.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final shownIds = prefs.getStringList('shown_gift_ids') ?? [];

      for (final notif in notifications) {
        final giftId = notif['id']?.toString() ?? '';
        if (giftId.isEmpty || shownIds.contains(giftId)) continue;

        shownIds.add(giftId);
        // Save immediately to prevent duplicate fetches in fast loops
        await prefs.setStringList('shown_gift_ids', shownIds);

        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          GiftPreviewOverlay.show(context, notif);
          // Wait to show the next one
          await Future.delayed(const Duration(seconds: 4));
        }
      }
    } catch (e) {}
  }

  // Purged dead Eye-blink init.

  @override
  void dispose() {
    HomeScreen.switchToProfileTab = null;
    _pollingTimer?.cancel();
    _locationTimer?.cancel();
    _feedScrollController.dispose();
    _preloadPlayer.dispose();
    EyeBlinkService.instance.stop();
    super.dispose();
  }

  Map<String, dynamic>? _currentFeedPost() {
    if (_feed.isEmpty) return null;
    final offset =
        _feedScrollController.hasClients ? _feedScrollController.offset : 0.0;
    final index = ((offset / 560).round()).clamp(0, _feed.length - 1).toInt();
    return _feed[index];
  }

  bool _isVideoPost(Map<String, dynamic>? post) {
    if (post == null) return false;
    final type = (post['type'] ?? '').toString().toLowerCase();
    final fileUrl =
        (post['video_url'] ?? post['file_url'] ?? '').toString().toLowerCase();
    return type == 'video' ||
        type == 'reel' ||
        fileUrl.endsWith('.mp4') ||
        fileUrl.endsWith('.mov') ||
        fileUrl.endsWith('.webm');
  }

  Future<void> _scrollFeedNext() async {
    if (!_feedScrollController.hasClients) return;
    final position = _feedScrollController.position;
    final screenHeight = MediaQuery.of(context).size.height;
    // Estimate each post card height (including margins)
    final postHeight = screenHeight * 0.72;
    // Calculate current post index
    final currentIndex = (position.pixels / postHeight).round();
    final nextIndex = currentIndex + 1;
    // Target: center the next post in the viewport
    final target = (nextIndex * postHeight).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 2) return;
    await _feedScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // â”€â”€ Story Grouping (Task 1) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Groups the flat stories list by user_id â†’ one entry per user in the bar.
  Map<String, List<dynamic>> _groupStoriesByUser(List<dynamic> stories) {
    final map = <String, List<dynamic>>{};
    for (final story in stories) {
      final uid =
          (story['user_id'] ?? story['userId'] ?? story['id'] ?? '').toString();
      map.putIfAbsent(uid, () => []).add(story);
    }
    return map;
  }

  void _openLivePreview() {
    final userId = UserPrefsCache.instance.userId ?? '';
    final profile = _profileService.currentProfileNotifier.value;
    final profileName = profile?.name;
    final userName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (profile?.username ?? 'User');
    final profileAvatar = profile?.avatar;
    final userAvatar = (profileAvatar != null && profileAvatar.isNotEmpty)
        ? profileAvatar
        : (profile?.profilePicUrl ?? '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePreviewScreen(
          userId: userId,
          userName: userName,
          userAvatar: userAvatar.isNotEmpty ? userAvatar : null,
        ),
      ),
    );
  }

  /// Opens the story viewer with ALL stories for a user, played in sequence.
  void _openStoryViewer(List<dynamic> userStories) {
    if (userStories.isEmpty) return;
    final first = userStories.first;
    final username = (first['author_name'] ??
            first['user_name'] ??
            first['username'] ??
            first['name'] ??
            'Story')
        .toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (p4_0) =>
            StoryViewScreen(stories: userStories, username: username),
      ),
    );
  }

  Future<void> _fetchData({bool force = false}) async {
    try {
      final results = await Future.wait([
        _apiService.getActiveStories(),
        _feedController.loadFeed(force: force),
      ]);
      if (mounted) {
        setState(() {
          _stories = results[0] as List;
        });
      }
    } catch (_) {}
  }

  bool _postNeedsMedia(Map<String, dynamic> post) {
    final type = (post['type'] ?? 'image').toString().toLowerCase();
    return type == 'image' || type == 'video' || type == 'reel';
  }

  String _resolvePostMediaUrl(Map<String, dynamic> post) {
    return normalizeMediaUrl(
      post['media_url'] ??
          post['file_url'] ??
          post['image_url'] ??
          post['image'] ??
          post['photo'] ??
          post['raw_file_url'],
      baseUrl: AppEnv.baseUrl,
      folder: '',
    );
  }

  bool _isRenderableFeedPost(Map<String, dynamic> post) {
    if (post['is_locked'] == 1 || post['is_locked'] == true) return true;
    if (!_postNeedsMedia(post)) return true;
    return _resolvePostMediaUrl(post).isNotEmpty;
  }

  Future<dynamic> _openPublishPostScreen(PublishPostScreen screen) async {
    return Navigator.push(
        context, MaterialPageRoute(builder: (p5_0) => screen));
  }

  Future<void> _refreshFeedAndScrollTop() async {
    await FeedController.instance.loadFeed(force: true);
    if (!mounted) return;
    if (_feedScrollController.hasClients) {
      await _feedScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Remove a post from the feed after deletion
  void _removePost(Map<String, dynamic> post) {
    final postId = post['id'] ?? post['post_id'];
    if (postId == null) return;

    _feedController.removePostById(postId);
  }

  Future<void> _handleUpload(String type) async {
    if (type == 'video' || type == 'reel') {
      // Offer camera recorder or gallery for reels/videos
      await _showReelCreateSheet();
      return;
    }
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null && mounted) {
        // Enforce 4:5 crop for photo posts
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 5),
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: const Color(0xFF0D0B14),
              toolbarWidgetColor: Colors.white,
              backgroundColor: const Color(0xFF0D0B14),
              activeControlsWidgetColor: const Color(0xFFD946EF),
              lockAspectRatio: true,
              hideBottomControls: false,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              aspectRatioPickerButtonHidden: true,
            ),
          ],
        );
        if (croppedFile == null) return; // User cancelled crop

        final result = await _openPublishPostScreen(
          PublishPostScreen(mediaType: type, mediaPath: croppedFile.path),
        );
        if (result == true) await _refreshFeedAndScrollTop();
      }
    } catch (e) {
      if (!mounted) return;
      NeonToast.error(context, 'Error: $e');
    }
  }

  Future<void> _showReelCreateSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Create Reel',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
            const SizedBox(height: 20),
            // Record with camera
            _createOption(
              icon: Icons.videocam_rounded,
              color: const Color(0xFFFF007F),
              title: 'Record Now',
              subtitle: 'Camera with filters & sounds',
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VideoRecorderScreen()),
                );
                if (mounted) await _refreshFeedAndScrollTop();
              },
            ),
            const SizedBox(height: 12),
            // Upload from gallery
            _createOption(
              icon: Icons.photo_library_rounded,
              color: const Color(0xFF06B6D4),
              title: 'Upload from Gallery',
              subtitle: 'Pick an existing video',
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final file =
                      await _picker.pickVideo(source: ImageSource.gallery);
                  if (file != null && mounted) {
                    final result = await _openPublishPostScreen(
                      PublishPostScreen(
                          mediaType: 'reel', mediaPath: file.path),
                    );
                    if (result == true) await _refreshFeedAndScrollTop();
                  }
                } catch (_) {}
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _createOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: color.withValues(alpha: 0.6), size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCreateStory() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1625),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Create Story',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _storySourceTile(ctx, Icons.camera_alt_outlined, 'Camera', 'Take a photo', 'camera'),
              _storySourceTile(ctx, Icons.photo_outlined, 'Gallery Photo', 'Choose from photos', 'photo'),
              _storySourceTile(ctx, Icons.videocam_outlined, 'Gallery Video', 'Choose a video', 'video'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    try {
      if (choice == 'video') {
        final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked == null || !mounted) return;
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoryEditorScreen(mediaFile: File(picked.path), type: 'video'),
          ),
        );
        if (result == true && mounted) _fetchData();
        return;
      }

      final XFile? picked = await _picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (picked == null || !mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Story',
            toolbarColor: const Color(0xFF0D0B14),
            toolbarWidgetColor: Colors.white,
            backgroundColor: const Color(0xFF0D0B14),
            activeControlsWidgetColor: const Color(0xFFD946EF),
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Story',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );
      if (croppedFile == null || !mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryEditorScreen(mediaFile: File(croppedFile.path), type: 'image'),
        ),
      );
      if (result == true && mounted) _fetchData();
    } catch (e) {
      if (!mounted) return;
      NeonToast.error(context, 'Story upload failed: $e');
    }
  }

  Widget _storySourceTile(BuildContext ctx, IconData icon, String title, String subtitle, String value) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD946EF), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  Future<void> _openNotifications() async {
    await SoundService().playNotification();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (p6_0) => const NotificationsScreen()),
    ).then((_) {
      if (mounted) {
        _fetchLiveAppNotifications();
      }
    });
  }

  void _showCreatePostOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFFD946EF), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Create Post",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.text_fields, color: Color(0xFFD946EF)),
              title: const Text(
                "Post Text",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await _openPublishPostScreen(
                  const PublishPostScreen(mediaType: 'text'),
                );
                if (result == true) {
                  await _refreshFeedAndScrollTop();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Color(0xFF00E5FF)),
              title: const Text(
                "Post Photo",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleUpload('image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_filter, color: Color(0xFF3B82F6)),
              title: const Text(
                "Post Reel",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleUpload('reel');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      extendBody: true,
      body: AnimatedBuilder(
        animation: _feedController,
        builder: (context, _) {
          // MatchTab manages its own top padding (status bar + header)
          if (_currentIndex == 2) {
            return _buildBody();
          }
          return Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Stack(
              children: [
                if (_isLoading && _feed.isEmpty && _currentIndex == 0)
                  const Center(
                    child: CircularProgressIndicator(
                      color: GalacticTheme.laserPink,
                    ),
                  )
                else
                  _buildBody(),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: 48,
          right: 48,
          bottom: MediaQuery.of(context).padding.bottom + 2,
        ),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: const Color(0xFFFF295C).withValues(alpha: 0.15),
              width: 0.8,
            ),
          ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildNavItem(Icons.home_rounded, "Home", 0),
                  _buildNavItemTap(
                    Icons.play_circle_outline_rounded,
                    "Reels",
                    _openReelsTab,
                  ),
                  // Center Match button — slightly raised
                  GestureDetector(
                    onTap: () => _onTabTapped(2),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF295C), Color(0xFFBF5AF2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF295C).withValues(alpha: 0.45),
                            blurRadius: 14,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_fire_department_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  _buildNavItem(Icons.chat_bubble_outline_rounded, "Chat", 3),
                  _buildNavItem(Icons.person_outline_rounded, "Profile", 4),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildNavItemTap(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 19),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 8.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? GalacticTheme.laserPink.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? GalacticTheme.laserPink
                  : const Color(0xCCFFFFFF),
              size: 20,
            ),
            const SizedBox(height: 1),
            if (isSelected)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: GalacticTheme.laserPink,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: GalacticTheme.laserPink.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              )
            else
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onTabTapped(int index) {
    if (index == 1) {
      _openReelsTab();
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Guest Gating
    if (auth.isGuest) {
      // Allow Home(0)
      // Block Match(2), Message(3), Profile(4)
      if (index == 2 || index == 3 || index == 4) {
        LoginRequiredSheet.show(
          context,
          feature: index == 2
              ? 'find matches'
              : (index == 3 ? 'chat' : 'view profile'),
        );
        return;
      }
    }

    SoundService().playTap();
    setState(() => _currentIndex = index);
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const SizedBox.shrink(); // Reels opens immersive route
      case 2:
        return const MatchTab(); // ← Full Match Tab with carousel + Random Call
      case 3:
        return _chatListScreen; // persistent — keeps polling timer alive
      case 4:
        return _profileScreen; // single persistent instance
      default:
        return _buildHomeContent();
    }
  }

  // --- HELPER: NEON CIRCLE BUTTON (For Header) ---
  Widget _buildNeonCircleBtn(
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: const Color(0xFF151515), // Dark BG
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.8),
            width: 1.5,
          ), // Neon Border
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ), // Neon Glow
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (badgeCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : badgeCount.toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onRefreshFeed() async {
    await _feedController.loadFeed(force: true);
  }

  Widget _buildHomeContent() {
    final filteredFeed =
        _feedController.items.where(_isRenderableFeedPost).toList();

    return RefreshIndicator(
      onRefresh: _onRefreshFeed,
      color: const Color(0xFFD946EF),
      backgroundColor: const Color(0xFF1A1A2E),
      displacement: 60,
      child: CustomScrollView(
        controller: _feedScrollController,
        cacheExtent: 500,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // App Bar / Header (Updated)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 8,
                left: 16,
                right: 16,
                bottom: 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo
                  GradientText(
                    'Goreto',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    colors: const [
                      Color(0xFFD946EF),
                      Color(0xFF06B6D4),
                    ], // Pink to Cyan
                  ),
                  // Neon Header Buttons
                  Row(
                    children: [
                      if (_blinkEnabled) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD946EF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.remove_red_eye_outlined, color: Color(0xFFD946EF), size: 12),
                              SizedBox(width: 4),
                              Text('Blink', style: TextStyle(color: Color(0xFFD946EF), fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _buildNeonCircleBtn(
                        Icons.search,
                        const Color(0xFFD946EF),
                        onTap: _openSearch,
                      ), // Purple
                      const SizedBox(width: 10),
                      _buildNeonCircleBtn(
                        Icons.notifications,
                        const Color(0xFF06B6D4),
                        onTap: _openNotifications,
                        badgeCount: _unreadNotificationCount,
                      ), // Cyan
                      const SizedBox(width: 10),
                      _buildNeonCircleBtn(
                        Icons.settings,
                        const Color(0xFFF97316),
                        onTap: () {
                          EyeBlinkService.instance.stop();
                          setState(() => _blinkEnabled = false);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (p7_0) => const SettingsScreen(),
                            ),
                          ).then((_) => _initBlinkService());
                        },
                      ), // Orange
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 1. Create Post Area (Cyberpunk/Neon)
          SliverToBoxAdapter(child: _buildCreatePostArea()),

          // 2. Stories Area
          SliverToBoxAdapter(child: _buildStoriesArea(_stories)),

          // 2b. Live Strip (only shown when someone is live)
          SliverToBoxAdapter(child: _buildLiveStrip()),

          // 3. Main Feed — pre-filtered, with RepaintBoundary + ad slots
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final adService = AdService.instance;
                final adEnabled = adService.settings.adsEnabled;
                final adFreq = adService.settings.feedFrequency;
                // Every (adFreq+1)th slot is an ad when ads are enabled
                if (adEnabled && adFreq > 0 && (index + 1) % (adFreq + 1) == 0) {
                  return const FeedAdCard();
                }
                // Map visual index back to post index (subtract ad slots before this index)
                final adSlotsBefore = adEnabled && adFreq > 0
                    ? (index + 1) ~/ (adFreq + 1)
                    : 0;
                final postIndex = index - adSlotsBefore;
                if (postIndex < 0 || postIndex >= filteredFeed.length) {
                  return const SizedBox.shrink();
                }
                final post = filteredFeed[postIndex];
                final rawPostId =
                    (post['id'] ?? post['post_id'] ?? '').toString();
                final stablePostKey = rawPostId.isNotEmpty
                    ? rawPostId
                    : (post['created_at'] ??
                            post['timestamp'] ??
                            post['file_url'] ??
                            post['media_url'] ??
                            post['caption'] ??
                            post.hashCode)
                        .toString();
                final type = (post['type'] ?? 'image').toString().toLowerCase();

                final fileUrl = (post['video_url'] ?? post['file_url'] ?? '')
                    .toString()
                    .toLowerCase();
                final isVideo = type == 'video' ||
                    type == 'reel' ||
                    fileUrl.endsWith('.mp4') ||
                    fileUrl.endsWith('.mov');

                Null uiOnSubscribe() {
                  final authorId = (post['user_id'] ??
                          post['user']?['id'] ??
                          post['author_id'])
                      ?.toString();
                  if (authorId == null) return;
                  setState(() {
                    for (var p in _feedController.items) {
                      final pAuthorId =
                          (p['user_id'] ?? p['user']?['id'] ?? p['author_id'])
                              ?.toString();
                      if (pAuthorId == authorId) {
                        final wasFollowing = p['is_following'] == true ||
                            p['is_following'] == 1 ||
                            p['is_following'] == '1';
                        p['is_following'] = !wasFollowing;
                      }
                    }
                  });
                }

                final Widget feedCard = isVideo
                    ? VideoFeedItem(
                        key: ValueKey('feed_$stablePostKey'),
                        post: post,
                        onLike: () {},
                        onComment: () {},
                        onShare: () => _feedController.loadFeed(force: true),
                        onSubscribe: uiOnSubscribe,
                        onDeleted: () => _removePost(post),
                      )
                    : PhotoFeedItem(
                        key: ValueKey('feed_$stablePostKey'),
                        post: post,
                        onLike: () {},
                        onComment: () {},
                        onShare: () => _feedController.loadFeed(force: true),
                        onSubscribe: uiOnSubscribe,
                        onDeleted: () => _removePost(post),
                      );

                // Attractive card wrapper with neon accent border + shadow
                return RepaintBoundary(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: isVideo ? _videoCardDecoration : _photoCardDecoration,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(20)),
                      child: feedCard,
                    ),
                  ),
                );
              },
              childCount: () {
                final adService = AdService.instance;
                if (!adService.settings.adsEnabled || adService.settings.feedFrequency <= 0) {
                  return filteredFeed.length;
                }
                final freq = adService.settings.feedFrequency;
                final adCount = filteredFeed.length ~/ freq;
                return filteredFeed.length + adCount;
              }(),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),

// Bottom Padding for Nav Bar
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ), // end CustomScrollView
    ); // end RefreshIndicator
  }


  // --- 1. NEON / CYBERPUNK CREATE POST AREA (Refined) ---
  Widget _buildCreatePostArea() {
    final user = Provider.of<AuthProvider>(context);
    final firstName = user.name?.split(' ').first ?? 'User';

    return ValueListenableBuilder<UserProfile?>(
      valueListenable: _profileService.currentProfileNotifier,
      builder: (context, currentProfile, _) {
        return FutureBuilder<UserProfile?>(
          future: _currentUserProfileFuture,
          builder: (context, snapshot) {
            final profile = currentProfile ?? snapshot.data;
            final photoUrl = (profile?.avatar.isNotEmpty == true)
                ? profile!.avatar
                : (profile?.profilePicUrl ?? '');

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(
                children: [
                  // --- 1. NEON INPUT ROW ---
                  Row(
                    children: [
                      // --- UPDATED PROFILE PIC WITH NEON BORDER ---
                      GestureDetector(
                        onTap: () => _onTabTapped(4),
                        child: Container(
                          padding: const EdgeInsets.all(
                            3,
                          ), // Space between border and image
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.9),
                              width: 2,
                            ), // Neon Border
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ), // Neon Glow
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF1A1A1A),
                            backgroundImage: photoUrl.isNotEmpty &&
                                    photoUrl.startsWith('http')
                                ? CachedNetworkImageProvider(photoUrl)
                                : (photoUrl.isNotEmpty
                                    ? FileImage(File(photoUrl)) as ImageProvider
                                    : null),
                            child: photoUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white70,
                                  )
                                : null,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Input Field (Existing Neon Style)
                      Expanded(
                        child: GestureDetector(
                          onTap: _showCreatePostOptions,
                          child: Container(
                            height: 58,
                            margin: const EdgeInsets.only(right: 36),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF151515),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFD946EF,
                                  ).withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "What's on your mind, $firstName?",
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- 2. NEON BUTTONS ROW ---
                  // Photos â†’ instant picker, Video â†’ picker, Live â†’ options menu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          // Task 2: Skip menu â€” open image picker immediately
                          onTap: () => _handleUpload('image'),
                          child: _buildNeonBtn(
                            Icons.photo_library,
                            "Photos",
                            const Color(0xFF22C55E),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _handleUpload('reel'),
                          child: _buildNeonBtn(
                            Icons.movie_filter,
                            "Reels",
                            const Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openLivePreview,
                          child: _buildNeonBtn(
                            Icons.wifi_tethering,
                            "Live",
                            const Color(0xFFF43F5E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- UPDATED CREATE STORY CARD (Pink Neon) ---
  Widget _buildCreateStoryCard() {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: _profileService.currentProfileNotifier,
      builder: (context, currentProfile, _) {
        return FutureBuilder<UserProfile?>(
          future: _currentUserProfileFuture,
          builder: (context, snapshot) {
            final profile = currentProfile ?? snapshot.data;
            final photoUrl = (profile?.avatar.isNotEmpty == true)
                ? profile!.avatar
                : (profile?.profilePicUrl ?? '');

            return GestureDetector(
              onTap: _handleCreateStory,
              child: Container(
                width: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD946EF),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFFD946EF),
                      blurRadius: 14,
                      spreadRadius: -1,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      children: [
                        Expanded(
                          flex: 65,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                            child: Container(
                              color: const Color(0xFF0D0D0D),
                              child: _safeStoryImage(
                                photoUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 220,
                                memCacheHeight: 220,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 35,
                          child: Container(
                            width: double.infinity,
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.only(bottom: 12),
                            child: const Text(
                              "Create story",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 50,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF151515),
                          shape: BoxShape.circle,
                        ),
                        child: Container(
                          height: 32,
                          width: 32,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF43F5E),
                              width: 2,
                            ), // Red Ring
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Color(0xFFF43F5E),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helper Widget for Neon Buttons (Refined)
  Widget _buildNeonBtn(IconData icon, String label, Color neonColor) {
    return Container(
      height: 45,
      decoration: BoxDecoration(
        color: const Color(0xFF121212), // Very Dark
        borderRadius: BorderRadius.circular(50), // Perfect Pill/Stadium
        border: Border.all(color: neonColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: neonColor, // Inner Glow (Tight)
            blurRadius: 4,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: neonColor.withValues(alpha: 0.5), // Outer Glow (Wide)
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: neonColor, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // --- LIVE STRIP (shown above filter chips when anyone is live) ---
  Widget _buildLiveStrip() {
    if (_homeLiveUsers.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '\u25cf LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _fetchHomeLiveUsers,
                  child: const Icon(Icons.refresh_rounded,
                      color: Color(0xFF8E8E93), size: 18),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _homeLiveUsers.length,
              itemBuilder: (context, index) {
                final u = _homeLiveUsers[index];
                final name = (u['name'] ?? u['user_name'] ?? 'User').toString();
                final avatar =
                    (u['avatar'] ?? u['profile_pic'] ?? '').toString();
                final viewers =
                    int.tryParse((u['viewers'] ?? 0).toString()) ?? 0;
                final userId = (u['user_id'] ?? u['id'] ?? '').toString();
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveRoomScreen(
                        userId: userId,
                        userName: name,
                        userAvatar: avatar.isNotEmpty ? avatar : null,
                        viewerCount: viewers,
                      ),
                    ),
                  ),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 10),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF007F),
                                    Color(0xFFD946EF)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF007F)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: CircleAvatar(
                                backgroundColor: const Color(0xFF1A1A1A),
                                backgroundImage: avatar.isNotEmpty &&
                                        avatar.startsWith('http')
                                    ? CachedNetworkImageProvider(avatar)
                                    : null,
                                child:
                                    avatar.isEmpty || !avatar.startsWith('http')
                                        ? Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          )
                                        : null,
                              ),
                            ),
                            Positioned(
                              bottom: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFF0A0A0F),
                                      width: 1.5),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. STORIES AREA â€” grouped by user (Task 1) ---
  Widget _buildStoriesArea(List<dynamic> stories) {
    // Group flat list â†’ one circle per user
    final grouped = _groupStoriesByUser(stories);
    final userIds = grouped.keys.toList();

    return Container(
      height: 190,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: userIds.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildCreateStoryCard();
          final uid = userIds[index - 1];
          final userStories = grouped[uid]!;
          return Padding(
            padding: const EdgeInsets.only(left: 10),
            // Pass the FULL list for this user â€” one circle, all stories
            child: _buildUserStoryCard(userStories),
          );
        },
      ),
    );
  }

  String _normalizeStoryUrl(dynamic raw) {
    if (raw == null) return '';
    String value = raw.toString().trim();
    if (value.isEmpty) return '';
    if (value.startsWith('[')) {
      try {
        final cleaned = value.replaceAll(RegExp(r'[\[\]"\s]'), '');
        final first = cleaned.split(',').first.trim();
        if (first.isNotEmpty) value = first;
      } catch (_) {}
    }
    return value;
  }

  bool _isVideoStory(Map<String, dynamic> story) {
    final type = (story['type'] ?? '').toString().toLowerCase();
    final mediaUrl = _normalizeStoryUrl(
      story['file_url'] ??
          story['media_url'] ??
          story['image'] ??
          story['image_url'],
    ).toLowerCase();
    return type == 'video' ||
        mediaUrl.endsWith('.mp4') ||
        mediaUrl.endsWith('.mov') ||
        mediaUrl.endsWith('.m4v') ||
        mediaUrl.endsWith('.webm');
  }

  String _resolveStoryPreviewMediaUrl(Map<String, dynamic> story) {
    final thumb = _normalizeStoryUrl(
      story['thumbnail_url'] ?? story['thumb_url'] ?? story['image_url'],
    );
    if (thumb.isNotEmpty) return thumb;

    final media = _normalizeStoryUrl(
      story['file_url'] ?? story['media_url'] ?? story['image'],
    );

    // For video stories without thumbnail, return empty so placeholder asset is used.
    if (_isVideoStory(story) && media.isNotEmpty) return '';
    return media;
  }

  Widget _storyPlaceholder({bool showPlay = false}) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.asset(_storyPlaceholderAsset, fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.25)),
          if (showPlay)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 34,
              ),
            ),
        ],
      ),
    );
  }

  Widget _safeStoryImage(
    String url, {
    bool showPlay = false,
    int memCacheWidth = 400,
    int memCacheHeight = 400,
    BoxFit fit = BoxFit.cover,
  }) {
    if (url.isEmpty) {
      return _storyPlaceholder(showPlay: showPlay);
    }

    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: (_, __) => _storyPlaceholder(showPlay: showPlay),
        errorWidget: (_, __, ___) => _storyPlaceholder(showPlay: showPlay),
      );
    }

    return Image.file(
      File(url),
      fit: fit,
      errorBuilder: (_, __, ___) => _storyPlaceholder(showPlay: showPlay),
    );
  }

  Widget _safeStoryAvatar(String avatarUrl, {double size = 28}) {
    Widget img;
    if (avatarUrl.isEmpty) {
      img = _storyPlaceholder();
    } else if (avatarUrl.startsWith('http')) {
      img = CachedNetworkImage(
        imageUrl: avatarUrl,
        fit: BoxFit.cover,
        memCacheWidth: 200,
        memCacheHeight: 200,
        placeholder: (_, __) => _storyPlaceholder(),
        errorWidget: (_, __, ___) => _storyPlaceholder(),
      );
    } else {
      img = Image.file(
        File(avatarUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _storyPlaceholder(),
      );
    }
    // SizedBox enforces a perfect square so ClipOval always clips to a circle.
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: img),
    );
  }

  // --- UPDATED USER STORY CARD â€” receives ALL stories for one user ---
  Widget _buildUserStoryCard(List<dynamic> userStories) {
    // Use the LATEST story (last in list) as the thumbnail
    final storyRaw = userStories.last;
    final story = storyRaw is Map
        ? Map<String, dynamic>.from(storyRaw)
        : <String, dynamic>{};
    final imageUrl = _resolveStoryPreviewMediaUrl(story);
    final name =
        (story['author_name'] ?? story['username'] ?? story['name'] ?? 'User')
            .toString();
    final userAvatar = _normalizeStoryUrl(
      story['author_avatar'] ??
          story['avatar_url'] ??
          story['userImage'] ??
          story['user_avatar'] ??
          story['profile_pic'] ??
          story['user_profile_pic'],
    );
    final isVideoStory = _isVideoStory(story);
    final storyCount = userStories.length;

    return GestureDetector(
      onTap: () => _openStoryViewer(userStories),
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD946EF), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFFD946EF),
              blurRadius: 14,
              spreadRadius: -1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            children: [
              Positioned.fill(
                child: _safeStoryImage(
                  imageUrl,
                  showPlay: isVideoStory && imageUrl.isEmpty,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.5, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    border: GradientBoxBorder(
                      gradient: LinearGradient(
                        colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
                      ),
                      width: 2,
                    ),
                  ),
                  child: _safeStoryAvatar(userAvatar),
                ),
              ),
              // Username label
              Positioned(
                bottom: 8,
                left: 10,
                right: 4,
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Story count badge (only shown when user has >1 story)
              if (storyCount > 1)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      '$storyCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
