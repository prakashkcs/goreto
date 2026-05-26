import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/services/signaling_service.dart';
import 'package:love_vibe_pro/services/video_call/video_call_manager.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/screens/chat/call/post_call_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:uuid/uuid.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/services/sound_service.dart';

class WebRTCCallScreen extends StatefulWidget {
  final CallSession callSession;
  final bool isOutgoing;
  final int? serverCallId;
  final bool autoAcceptCall;
  final bool isTargetOnline;

  const WebRTCCallScreen({
    super.key,
    required this.callSession,
    this.isOutgoing = true,
    this.serverCallId,
    this.autoAcceptCall = false,
    this.isTargetOnline = false,
  });

  @override
  State<WebRTCCallScreen> createState() => _WebRTCCallScreenState();
}

class _WebRTCCallScreenState extends State<WebRTCCallScreen> {
  final SignalingService _signaling = SignalingService.instance;
  final VideoCallManager _videoManager = VideoCallManager();

  CallState _callState = CallState.idle;
  int? _serverCallId;
  String _callUuid = '';

  String _currentUserId = '';
  String _currentUserName = '';
  bool _endedByOther = false;
  bool _callEnded = false;
  bool _hideCallerName = false;
  Widget? _cachedCallView;

  Timer? _callDurationTimer;
  int _callDurationSeconds = 0;
  Timer? _incomingStatusTimer;

  void _startDurationTimer() {
    if (_callDurationTimer != null) return;
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _serverCallId = widget.serverCallId;
    _callUuid = widget.callSession.id; // Use the call UUID from session
    _callState =
        widget.isOutgoing ? CallState.outgoing : widget.callSession.state;
    _initVideoManagerAndCall();
  }

  Future<void> _initVideoManagerAndCall() async {
    // userId: sync from cache
    _currentUserId = UserPrefsCache.instance.userId ??
        (widget.isOutgoing
            ? widget.callSession.callerId
            : widget.callSession.receiverId);

    // userName: try cached profile first, fall back to session data
    final profileName =
        ProfileService.instance.currentProfileNotifier.value?.name;
    _currentUserName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (widget.isOutgoing
            ? widget.callSession.callerName
            : widget.callSession.receiverName);

    // privacy_allow_direct_call: still needs SharedPreferences (not in UserPrefsCache)
    if (!widget.isOutgoing && widget.callSession.isRandomCall) {
      final prefs = await SharedPreferences.getInstance();
      final showName = prefs.getBool('privacy_allow_direct_call') ?? true;
      if (!showName) setState(() => _hideCallerName = true);
    }

    // Initialize the manager which hits the backend to find active provider (Zego, Agora, etc)
    final success = await _videoManager.initialize(
      currentUserId: _currentUserId,
      currentUserName: _currentUserName,
    );

    if (mounted) {
      if (!success) {
        setState(() => _callState = CallState.failed);
        _endCall();
        return;
      }

      if (widget.isOutgoing) {
        _startOutgoingCall();
      } else if (widget.autoAcceptCall) {
        _acceptCall();
      } else {
        _startIncomingCall();
      }
    }
  }

  @override
  void dispose() {
    _callDurationTimer?.cancel();
    _incomingStatusTimer?.cancel();
    _signaling.onCallAccepted = null;
    _signaling.onCallDeclined = null;
    _signaling.onCallEnded = null;
    // If the screen was popped without going through _endCall (e.g. system back),
    // clean up the server-side call record so it doesn't stay ringing.
    if (!_callEnded && _serverCallId != null) {
      _signaling.endCall(_serverCallId!);
    }
    super.dispose();
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  // â”€â”€ OUTGOING CALL â”€â”€
  Future<void> _startOutgoingCall() async {
    setState(() => _callState = CallState.outgoing);
    await SoundService().startOutgoingCallRingLoop();

    try {
      if (_serverCallId == null) {
        _callUuid = const Uuid().v4();

        final result = await _signaling.initiateCall(
          receiverId: widget.callSession.receiverId,
          type: widget.callSession.type == CallType.video ? 'video' : 'audio',
          callUuid: _callUuid,
        );

        if (result != null) {
          _serverCallId = result['call_id'];
        } else {}
      }

      if (_serverCallId != null) {
        _setupSignalCallbacks();
        _signaling.startSignalPolling(_serverCallId!);
      }

      // Join the Zego room and render inline (don't navigate away)
      if (mounted && _videoManager.activeProvider != null) {
        await _videoManager.activeProvider!.joinCall(_callUuid);
        // Do NOT set _callState to connected here. The custom UI should remain
        // until the signaling server confirms the recipient has answered via onCallAccepted!
      } else {}
    } catch (e) {
      _endCall();
    }
  }

  // â”€â”€ INCOMING CALL â”€â”€
  Future<void> _startIncomingCall() async {
    setState(() => _callState = CallState.incoming);
    SoundService().startIncomingCallRingLoop();
    // Poll every 2 s — auto-dismiss if the caller cancels before user answers
    final id = _serverCallId;
    if (id == null) return;
    _incomingStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final status = await _signaling.checkCallStatus(id);
      if (!mounted) {
        _incomingStatusTimer?.cancel();
        return;
      }
      if (status != null && status != 'ringing' && status != 'accepted') {
        _incomingStatusTimer?.cancel();
        FCMService.dismissCallNotification();
        _endCall();
      }
    });
  }

  // â”€â”€ ACCEPT INCOMING â”€â”€
  Future<void> _acceptCall() async {
    _hapticFeedback();
    SoundService().stopIncomingCallRing();
    setState(() => _callState = CallState.connecting);

    try {
      if (_serverCallId != null) {
        _setupSignalCallbacks();
        final success = await _signaling.acceptCall(_serverCallId!);
        if (!success) {
          if (mounted) {
            NeonToast.error(context, 'Call no longer available');
            _endCall();
          }
          return;
        }
        _signaling.startSignalPolling(_serverCallId!);
      }

      // Use the call_uuid from the session (passed from server via incoming call polling)
      _callUuid = widget.callSession.id;

      if (mounted) {
        if (_videoManager.activeProvider != null) {
          await _videoManager.activeProvider!.joinCall(_callUuid);
          if (mounted) {
            setState(() {
              _callState = CallState.connected;
              _startDurationTimer();
            });
          }
        } else {
          // Provider unavailable — call cannot connect
          NeonToast.error(context, 'Call service unavailable');
          _endCall();
        }
      }
    } catch (e) {
      if (mounted) _endCall();
    }
  }

  Future<void> _declineCall() async {
    _hapticFeedback();
    SoundService().stopIncomingCallRing();
    if (_serverCallId != null) {
      await _signaling.declineCall(_serverCallId!);
    }
    FCMService.dismissCallNotification();
    _endCall();
  }

  void _setupSignalCallbacks() {
    _signaling.onCallAccepted = () {
      SoundService().stopOutgoingCallRing();
      if (mounted) {
        setState(() {
          _callState = CallState.connected;
          _startDurationTimer();
        });
      }
    };

    _signaling.onCallDeclined = () {
      SoundService().stopOutgoingCallRing();
      if (mounted) {
        setState(() => _callState = CallState.declined);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _endCall();
        });
      }
    };

    _signaling.onCallEnded = () {
      if (mounted) _endCallByOther();
    };
  }

  void _endCallByOther() {
    _endedByOther = true;
    _endCall(showEnded: true);
  }

  void _endCall({bool showEnded = false}) {
    _callEnded = true;
    SoundService().stopOutgoingCallRing();
    SoundService().stopIncomingCallRing();
    _hapticFeedback();
    _cachedCallView = null;
    _callDurationTimer?.cancel();
    if (_serverCallId != null) {
      _signaling.endCall(_serverCallId!);
    }
    _videoManager.activeProvider?.leaveCall();

    // Dismiss the call tray notification so it doesn't persist
    FCMService.dismissCallNotification();

    if (!mounted) return;

    if (showEnded) {
      setState(() => _callState = CallState.ended);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _navigateAfterCall();
      });
      return;
    }

    _navigateAfterCall();
  }

  void _navigateAfterCall() {
    if (!mounted) return;
    // For random calls that actually connected, show the post-call profile screen
    if (widget.callSession.isRandomCall && _callDurationSeconds > 0) {
      final otherUserId = widget.isOutgoing
          ? widget.callSession.receiverId
          : widget.callSession.callerId;
      final otherName = widget.isOutgoing
          ? widget.callSession.receiverName
          : widget.callSession.callerName;
      final otherAvatar = widget.isOutgoing
          ? widget.callSession.receiverAvatar
          : widget.callSession.callerAvatar;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PostCallScreen(
            myUserId: _currentUserId,
            myName: _currentUserName,
            otherUserId: otherUserId,
            otherName: otherName,
            otherAvatar: otherAvatar,
            callDurationSeconds: _callDurationSeconds,
          ),
        ),
      );
    } else {
      Navigator.pop(context, _callDurationSeconds);
    }
  }

  Widget _buildCachedCallView() {
    return _cachedCallView ??= _videoManager.activeProvider!.buildCallView(
      remoteUserId: widget.isOutgoing
          ? widget.callSession.receiverId
          : widget.callSession.callerId,
      remoteUserName: widget.isOutgoing
          ? widget.callSession.receiverName
          : widget.callSession.callerName,
      isVideoCall: widget.callSession.type == CallType.video,
      onCallEnded: () {
        if (mounted) _endCall();
      },
      onProviderError: (errorMsg) {
        _videoManager.reportProviderError(error: errorMsg);
        if (mounted) {
          NeonToast.error(context, 'Call connection failed. Please try again.');
          _endCall();
        }
      },
    );
  }

  Widget _buildEndedOverlay(String otherName) {
    final who = _endedByOther ? '$otherName ended the call' : 'Call ended';
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_end, color: Colors.red, size: 64),
            const SizedBox(height: 20),
            Text(
              who,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String otherName = widget.isOutgoing
        ? widget.callSession.receiverName
        : (_hideCallerName && _callState != CallState.connected
            ? 'Stranger'
            : widget.callSession.callerName);
    final String? otherAvatar = widget.isOutgoing
        ? widget.callSession.receiverAvatar
        : (_hideCallerName && _callState != CallState.connected
            ? null
            : widget.callSession.callerAvatar);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Render the provider's call UI once connected.
          // All providers implement buildCallView() on the interface —
          // no type-checking needed.
          if (_callState == CallState.ended)
            _buildEndedOverlay(otherName)
          else if (_callState == CallState.connected &&
              _videoManager.activeProvider != null)
            _buildCachedCallView()
          else ...[
            // Background Profile Image blurred
            if (otherAvatar != null && otherAvatar.isNotEmpty) ...[
              Opacity(
                opacity: 0.4,
                child: CachedNetworkImage(
                  imageUrl: otherAvatar,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox(),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(color: Colors.transparent),
              ),
            ] else ...[
              // Subtle gradient if no avatar
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2C0B3E), Color(0xFF0A0A0A)],
                  ),
                ),
              ),
            ],

            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Avatar Circle
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: (otherAvatar != null && otherAvatar.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: otherAvatar,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[900]),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[800],
                                child: const Icon(
                                  Icons.person,
                                  size: 70,
                                  color: Colors.white54,
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.person,
                                size: 70,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Name
                  Text(
                    otherName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Status text
                  Text(
                    _callState == CallState.incoming
                        ? 'Incoming ${widget.callSession.type == CallType.video ? 'video' : 'voice'} call'
                        : _callState == CallState.connecting
                            ? 'Connecting...'
                            : _callState == CallState.declined
                                ? 'Call declined'
                                : (widget.isOutgoing && widget.isTargetOnline)
                                    ? 'Ringing...'
                                    : 'Calling...',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 18,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const Spacer(flex: 3),

                  if (_callState == CallState.incoming)
                    _buildIncomingCallButtons()
                  else
                    _buildOutgoingCallButtons(),

                  const SizedBox(height: 60),
                ],
              ),
            ),
          ], // End of else ...[
        ], // End of Stack children
      ),
    );
  }

  Widget _buildIncomingCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _declineCall,
          child: Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 50),
        GestureDetector(
          onTap: _acceptCall,
          child: Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildOutgoingCallButtons() {
    return GestureDetector(
      onTap: _endCall,
      child: Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
      ),
    );
  }
}
