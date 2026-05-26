import 'package:flutter/material.dart';

abstract class VideoCallProvider {
  /// The provider's name (e.g., 'zego', 'agora', 'dyte', 'twilio')
  String get name;

  /// Initialize the provider with app credentials and the current user info
  Future<void> initialize({
    required Map<String, dynamic> config,
    required String currentUserId,
    required String currentUserName,
  });

  /// Join a video call by call ID/UUID
  Future<void> joinCall(String callId);

  /// Leave the active call
  Future<void> leaveCall();

  /// Switch the front/back camera
  void switchCamera();

  /// Toggle microphone mute
  void toggleMic(bool isMuted);

  /// Toggle local video on/off
  void toggleVideo(bool isVideoOff);

  /// Build a 1-on-1 call UI (video or audio call between two users).
  /// This is used for direct calls and random video calls.
  /// Every provider MUST implement this — it is the primary call surface.
  Widget buildCallView({
    required String remoteUserId,
    required String remoteUserName,
    bool isVideoCall = true,
    VoidCallback? onCallEnded,
    void Function(String errorMessage)? onProviderError,
  });

  /// Build the live-streaming UI (host + audience).
  /// Used for live rooms. Providers that don't support live streaming
  /// should return a "not supported" placeholder.
  Widget buildVideoView({
    bool isVideoCall = true,
    VoidCallback? onLeaveCall,
    VoidCallback? onLiveStarted,
    VoidCallback? onProviderError,
    Widget? foreground,
  });
}
