import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zego_uikit_prebuilt_live_streaming/zego_uikit_prebuilt_live_streaming.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'video_call_provider.dart';

class ZegoProvider implements VideoCallProvider {
  @override
  String get name => 'zego';

  late int _appIdInt;
  late String _appSign;
  late String _currentUserId;
  late String _currentUserName;
  late String _callId;
  bool _isInitialized = false;

  // Store avatar URLs for the avatar builder
  String _hostAvatarUrl = '';
  String _viewerAvatarUrl = '';

  // Shared avatar cache — populated at build time and updated via broadcasts
  final Map<String, String> _avatarCache = {};

  // Callback for end-live notification
  VoidCallback? _onEndLiveCallback;

  @override
  Future<void> initialize({
    required Map<String, dynamic> config,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final appIdStr = config['app_id']?.toString() ?? '';
    _appIdInt = int.tryParse(appIdStr) ?? 0;
    _appSign = config['app_sign']?.toString() ?? '';
    _currentUserId = currentUserId;
    _currentUserName = currentUserName;

    if (_appIdInt == 0 || _appSign.isEmpty) {
      return;
    }

    _isInitialized = true;
  }

  /// Set the host avatar URL for display in the top bar
  void setHostAvatar(String url) {
    _hostAvatarUrl = url;
  }

  /// Set the current viewer's avatar URL for display in chat
  void setViewerAvatar(String url) {
    _viewerAvatarUrl = url;
  }

  /// Set callback for when live stream ends (so host can notify backend)
  void setOnEndLiveCallback(VoidCallback? callback) {
    _onEndLiveCallback = callback;
  }

  @override
  Future<void> joinCall(String callId) async {
    _callId = callId;
    _streamEverStarted = false;
    _errorFired = false;
  }

  @override
  Future<void> leaveCall() async {}

  @override
  void switchCamera() {}

  @override
  void toggleMic(bool isMuted) {}

  @override
  void toggleVideo(bool isVideoOff) {}

  bool _streamEverStarted = false;
  bool _errorFired = false;

  /// Allow external callers (e.g. live_room_screen) to cache another user's avatar URL
  void cacheUserAvatar(String userId, String url) {
    if (userId.isNotEmpty && url.isNotEmpty) _avatarCache[userId] = url;
  }

  // ── CALL VIEW (ZegoUIKitPrebuiltCall) ──────────────────────────────────────
  /// Builds a proper 1-on-1 video/audio call UI using the Call SDK.
  /// This is what random video calls should use — NOT the live-streaming widget.
  Widget buildCallView({
    required String remoteUserId,
    required String remoteUserName,
    bool isVideoCall = true,
    VoidCallback? onCallEnded,
    void Function(String errorMessage)? onProviderError,
  }) {
    if (!_isInitialized || _appIdInt == 0 || _appSign.isEmpty) {
      return const Center(
        child: Text(
          'Video call not configured.\nCheck Admin → Video Providers.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    final config = ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall();
    config.video = ZegoUIKitVideoConfig.preset720P();
    config.turnOnCameraWhenJoining = isVideoCall;
    config.turnOnMicrophoneWhenJoining = true;
    config.useSpeakerWhenJoining = true;
    config.topMenuBar.isVisible = false;
    config.bottomMenuBar.buttons = isVideoCall
        ? [
            ZegoCallMenuBarButtonName.toggleCameraButton,
            ZegoCallMenuBarButtonName.hangUpButton,
            ZegoCallMenuBarButtonName.toggleMicrophoneButton,
            ZegoCallMenuBarButtonName.switchCameraButton,
          ]
        : [
            ZegoCallMenuBarButtonName.toggleMicrophoneButton,
            ZegoCallMenuBarButtonName.hangUpButton,
            ZegoCallMenuBarButtonName.switchAudioOutputButton,
          ];

    return ZegoUIKitPrebuiltCall(
      appID: _appIdInt,
      appSign: _appSign,
      userID: _currentUserId,
      userName: _currentUserName,
      callID: _callId,
      config: config,
      events: ZegoUIKitPrebuiltCallEvents(
        onCallEnd: (event, defaultAction) {
          onCallEnded?.call();
        },
        onError: (error) {
          // Room login failures (wrong credentials, expired account, etc.)
          onProviderError?.call('code:${error.code} ${error.message}');
        },
      ),
    );
  }

  @override
  Widget buildVideoView({
    bool isVideoCall = true,
    VoidCallback? onLeaveCall,
    VoidCallback? onLiveStarted,
    VoidCallback? onProviderError,
    Widget? foreground,
  }) {
    if (!_isInitialized || _appIdInt == 0 || _appSign.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: Colors.white38, size: 56),
              SizedBox(height: 16),
              Text(
                'Live streaming not configured',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                'Go to Admin Panel → Video Providers and enter your ZegoCloud App ID and App Sign.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_callId.isEmpty) {
      return const Center(
        child: Text(
          'Error: Live ID is empty.\nStream setup failed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    final hostId = _callId.replaceAll('live_', '');
    final isHost = _currentUserId == hostId;
    final config = isHost
        ? ZegoUIKitPrebuiltLiveStreamingConfig.host()
        : ZegoUIKitPrebuiltLiveStreamingConfig.audience();

    // Video quality — 1080p for host broadcast, 720p for audience receive
    config.video = isHost
        ? ZegoUIKitVideoConfig.preset1080P()
        : ZegoUIKitVideoConfig.preset720P();

    // 1. Disable host preview (we have our own LivePreviewScreen)
    config.preview.showPreviewForHost = false;

    // 2. Ensure audience cannot talk/video by default
    if (!isHost) {
      config.role = ZegoLiveStreamingRole.audience;
      config.turnOnCameraWhenJoining = false;
      config.turnOnMicrophoneWhenJoining = false;
    }

    // 3. Hide Zego's default bottom bar and built-in message list entirely
    config.bottomMenuBar.showInRoomMessageButton = false;
    config.bottomMenuBar.hostButtons = [];
    config.bottomMenuBar.height = 0;
    config.inRoomMessage.visible = false;

    // 4. Avatar builder — pre-populate cache with known avatars
    if (_hostAvatarUrl.isNotEmpty) _avatarCache[hostId] = _hostAvatarUrl;
    if (_viewerAvatarUrl.isNotEmpty) {
      _avatarCache[_currentUserId] = _viewerAvatarUrl;
    }

    config.avatarBuilder = (
      BuildContext context,
      Size size,
      ZegoUIKitUser? user,
      Map<String, dynamic> extraInfo,
    ) {
      final userId = user?.id ?? '';
      String? avatarUrl;

      if (userId == hostId && _hostAvatarUrl.isNotEmpty) {
        avatarUrl = _hostAvatarUrl;
      } else if (userId == _currentUserId && _viewerAvatarUrl.isNotEmpty) {
        avatarUrl = _viewerAvatarUrl;
      } else if (_avatarCache.containsKey(userId)) {
        avatarUrl = _avatarCache[userId];
      }

      // Check Zego's in-room attributes (populated when ZIM plugin is active)
      if (avatarUrl == null || avatarUrl.isEmpty) {
        final inRoomUrl = user?.inRoomAttributes.value['avatar'] ?? '';
        if (inRoomUrl.isNotEmpty) {
          avatarUrl = inRoomUrl;
          _avatarCache[userId] = inRoomUrl;
        }
      }

      // Check extraInfo passed by caller
      if ((avatarUrl == null || avatarUrl.isEmpty) &&
          extraInfo.containsKey('avatar')) {
        avatarUrl = extraInfo['avatar']?.toString();
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          _avatarCache[userId] = avatarUrl;
        }
      }

      // If we have a valid avatar URL, show the profile pic
      if (avatarUrl != null &&
          avatarUrl.isNotEmpty &&
          avatarUrl.startsWith('http')) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: CachedNetworkImageProvider(avatarUrl),
              fit: BoxFit.cover,
            ),
          ),
        );
      }

      // Default avatar with user initial
      final initial =
          (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : '?';

      // Generate a color based on user ID or name hash
      final colorHash = (user?.id ?? '1').hashCode.abs() % 5;
      const gradients = [
        [Color(0xFFFF007F), Color(0xFFD946EF)], // Pink
        [Color(0xFF00C6FF), Color(0xFF0072FF)], // Blue
        [Color(0xFFF09819), Color(0xFFEDDE5D)], // Yellow
        [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Purple
        [Color(0xFF11998E), Color(0xFF38EF7D)], // Green
      ];
      final color = gradients[colorHash];

      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: color),
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: size.width * 0.4,
            ),
          ),
        ),
      );
    };

    // 5. Hide Zego's built-in top bar — we render our own header in a Stack above this widget
    config.topMenuBar.height = 0;
    config.topMenuBar.showCloseButton = false;
    config.topMenuBar.hostAvatarBuilder = (_) => const SizedBox.shrink();

    // 6. Custom foreground overlay (chat, gifts, etc.)
    if (foreground != null) config.foreground = foreground;

    // 7. Leave callback
    config.confirmDialogInfo = isHost
        ? ZegoLiveStreamingDialogInfo(
            title: 'End Live Stream?',
            message: 'Are you sure you want to stop broadcasting?',
            cancelButtonName: 'Cancel',
            confirmButtonName: 'End Live',
          )
        : null;

    return ZegoUIKitPrebuiltLiveStreaming(
      appID: _appIdInt,
      appSign: _appSign,
      userID: _currentUserId,
      userName: _currentUserName,
      liveID: _callId,
      events: ZegoUIKitPrebuiltLiveStreamingEvents(
        onError: (error) {
          // Room-login failures (wrong app_id / app_sign, expired account)
          // fire here immediately — trigger provider fallback right away.
          debugPrint('Zego live error: code=${error.code} msg=${error.message}');
          if (!_streamEverStarted && !_errorFired) {
            _errorFired = true;
            onProviderError?.call();
          }
        },
        onStateUpdated: (ZegoLiveStreamingState state) {
          if (state == ZegoLiveStreamingState.living) {
            _streamEverStarted = true;
            onLiveStarted?.call();
          }
        },
        onEnded: (event, defaultAction) {
          if (!_streamEverStarted && !_errorFired) {
            // Stream ended without ever starting and no error event fired —
            // still treat this as a credential/auth failure.
            _errorFired = true;
            onProviderError?.call();
          } else if (_streamEverStarted) {
            if (isHost) _onEndLiveCallback?.call();
            onLeaveCall?.call();
          }
        },
      ),
      config: config,
    );
  }
}
