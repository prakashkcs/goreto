import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'video_call_provider.dart';

class AgoraProvider implements VideoCallProvider {
  @override
  String get name => 'agora';

  String _appId = '';
  String _appCertificate = '';  // stored in server_secret column
  String _baseUrl = '';
  String _authToken = '';
  String _currentUserId = '';
  String _channelId = '';
  bool _isInitialized = false;

  @override
  Future<void> initialize({
    required Map<String, dynamic> config,
    required String currentUserId,
    required String currentUserName,
  }) async {
    _appId          = config['app_id']?.toString() ?? '';
    _appCertificate = config['server_secret']?.toString() ?? '';
    _currentUserId  = currentUserId;

    final prefs = await SharedPreferences.getInstance();
    _baseUrl    = prefs.getString('api_base_url') ?? 'https://goreto.org/ekloadmin/api/v1/';
    if (!_baseUrl.endsWith('/')) _baseUrl = '$_baseUrl/';
    _authToken  = prefs.getString('app_token') ?? prefs.getString('auth_token') ?? '';

    _isInitialized = _appId.isNotEmpty;
  }

  @override
  Future<void> joinCall(String callId) async {
    _channelId = callId;
  }

  @override
  Future<void> leaveCall() async {}

  @override
  void switchCamera() {}

  @override
  void toggleMic(bool isMuted) {}

  @override
  void toggleVideo(bool isVideoOff) {}

  /// Fetch a short-lived RTC token from the PHP backend.
  /// Falls back to empty string (trial / no-certificate mode) on any error.
  Future<String> _fetchToken(String channelName, int uid) async {
    // If no App Certificate configured, Agora runs in trial mode (no token needed)
    if (_appCertificate.isEmpty) return '';
    try {
      final uri = Uri.parse('${_baseUrl}agora_token.php');
      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({'channel': channelName, 'uid': uid, 'expire': 86400}),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['status'] == 'success') return data['token']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget buildCallView({
    required String remoteUserId,
    required String remoteUserName,
    bool isVideoCall = true,
    VoidCallback? onCallEnded,
    void Function(String errorMessage)? onProviderError,
  }) {
    if (!_isInitialized || _appId.isEmpty) {
      return _notConfiguredWidget('Agora not configured.\nCheck Admin → Video Providers.');
    }
    return _AgoraCallView(
      appId: _appId,
      channelId: _channelId,
      isVideoCall: isVideoCall,
      isAudience: false,
      tokenFetcher: _fetchToken,
      onCallEnded: onCallEnded,
      onProviderError: onProviderError,
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
    if (!_isInitialized || _appId.isEmpty) {
      return _notConfiguredWidget(
          'Live streaming not configured.\nGo to Admin → Video Providers and enter your Agora App ID.');
    }

    // Determine role: if the channel is live_<userId> and userId == currentUserId → host
    final isHost = _channelId == 'live_$_currentUserId';

    return _AgoraCallView(
      appId: _appId,
      channelId: _channelId,
      isVideoCall: isVideoCall,
      isAudience: !isHost,
      tokenFetcher: _fetchToken,
      onCallEnded: onLeaveCall,
      onProviderError: onProviderError != null ? (_) => onProviderError() : null,
      onLiveStarted: onLiveStarted,
      foreground: foreground,
    );
  }

  Widget _notConfiguredWidget(String msg) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white38, size: 56),
              const SizedBox(height: 16),
              Text(
                msg,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Agora call/live view widget ───────────────────────────────────────────────

class _AgoraCallView extends StatefulWidget {
  final String appId;
  final String channelId;
  final bool isVideoCall;
  final bool isAudience;  // false = broadcaster (host/caller), true = viewer
  final Future<String> Function(String channel, int uid) tokenFetcher;
  final VoidCallback? onCallEnded;
  final VoidCallback? onLiveStarted;
  final void Function(String)? onProviderError;
  final Widget? foreground;

  const _AgoraCallView({
    required this.appId,
    required this.channelId,
    required this.isVideoCall,
    required this.isAudience,
    required this.tokenFetcher,
    this.onCallEnded,
    this.onLiveStarted,
    this.onProviderError,
    this.foreground,
  });

  @override
  State<_AgoraCallView> createState() => _AgoraCallViewState();
}

class _AgoraCallViewState extends State<_AgoraCallView> {
  RtcEngine? _engine;
  int? _remoteUid;
  bool _localJoined = false;
  bool _micMuted = false;
  bool _videoOff = false;
  bool _switchedCamera = false;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<void> _initAgora() async {
    try {
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(RtcEngineContext(appId: widget.appId));

      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (_, __) {
          if (!mounted) return;
          setState(() => _localJoined = true);
          widget.onLiveStarted?.call();
        },
        onUserJoined: (_, int uid, __) {
          if (!mounted) return;
          setState(() => _remoteUid = uid);
        },
        onUserOffline: (_, int uid, UserOfflineReasonType reason) {
          if (!mounted) return;
          setState(() => _remoteUid = null);
          if (reason != UserOfflineReasonType.userOfflineDropped) {
            widget.onCallEnded?.call();
          }
        },
        onError: (ErrorCodeType code, String msg) {
          if (!mounted) return;
          if (code == ErrorCodeType.errInvalidToken ||
              code == ErrorCodeType.errTokenExpired ||
              code == ErrorCodeType.errInvalidAppId) {
            widget.onProviderError?.call('Agora auth error: $msg');
          }
        },
        onLeaveChannel: (_, __) {
          if (!mounted) return;
          setState(() {
            _localJoined = false;
            _remoteUid = null;
          });
        },
      ));

      final role = widget.isAudience
          ? ClientRoleType.clientRoleAudience
          : ClientRoleType.clientRoleBroadcaster;

      await engine.setClientRole(role: role);

      if (widget.isVideoCall) {
        await engine.enableVideo();
        if (!widget.isAudience) await engine.startPreview();
      } else {
        await engine.enableAudio();
      }

      // Fetch token from PHP backend
      final rtcToken = await widget.tokenFetcher(widget.channelId, 0);

      await engine.joinChannel(
        token: rtcToken,
        channelId: widget.channelId,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: role,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          publishCameraTrack: !widget.isAudience && widget.isVideoCall,
          publishMicrophoneTrack: !widget.isAudience,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideoCall,
        ),
      );
    } catch (e) {
      widget.onProviderError?.call('Agora init error: $e');
    }
  }

  @override
  void dispose() {
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  void _toggleMic() {
    setState(() => _micMuted = !_micMuted);
    _engine?.muteLocalAudioStream(_micMuted);
  }

  void _toggleVideo() {
    setState(() => _videoOff = !_videoOff);
    _engine?.muteLocalVideoStream(_videoOff);
  }

  void _switchCamera() {
    setState(() => _switchedCamera = !_switchedCamera);
    _engine?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Remote video (full screen)
        if (_remoteUid != null && widget.isVideoCall)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine!,
              canvas: VideoCanvas(uid: _remoteUid),
              connection: RtcConnection(channelId: widget.channelId),
            ),
          )
        else if (widget.isAudience)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white38),
                SizedBox(height: 14),
                Text('Waiting for host...', style: TextStyle(color: Colors.white54)),
              ],
            ),
          )
        else
          Container(color: Colors.black),

        // Local preview (broadcaster only, top-left)
        if (!widget.isAudience && widget.isVideoCall && _engine != null)
          Positioned(
            top: 60,
            left: 16,
            width: 110,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _localJoined
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white38, strokeWidth: 2),
                      ),
                    ),
            ),
          ),

        // Foreground overlay (chat, gifts, etc.)
        if (widget.foreground != null) widget.foreground!,

        // Controls bar (broadcaster only)
        if (!widget.isAudience)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlBtn(
                  icon: _micMuted ? Icons.mic_off : Icons.mic,
                  color: _micMuted ? Colors.red : Colors.white24,
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 20),
                _ControlBtn(
                  icon: Icons.call_end,
                  color: Colors.red,
                  onTap: () => widget.onCallEnded?.call(),
                  size: 64,
                ),
                if (widget.isVideoCall) ...[
                  const SizedBox(width: 20),
                  _ControlBtn(
                    icon: _videoOff ? Icons.videocam_off : Icons.videocam,
                    color: _videoOff ? Colors.red : Colors.white24,
                    onTap: _toggleVideo,
                  ),
                  const SizedBox(width: 20),
                  _ControlBtn(
                    icon: Icons.flip_camera_ios,
                    color: Colors.white24,
                    onTap: _switchCamera,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const _ControlBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}
