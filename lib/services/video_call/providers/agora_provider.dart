import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'video_call_provider.dart';
import '../video_call_manager.dart';

class AgoraProvider implements VideoCallProvider {
  @override
  String get name => 'agora';

  String _appId = '';
  String _appCertificate = '';  // stored in server_secret column
  String _baseUrl = '';
  String _authToken = '';
  String _currentUserId = '';

  /// Agora needs a numeric uid, and the *same* value must be used when minting
  /// the token and when joining -- a mismatch is rejected as an invalid token.
  /// The account id is that value; 0 ("let Agora assign one") can't be used
  /// because the token has to be bound to a concrete uid.
  int get _agoraUid => int.tryParse(_currentUserId) ?? 0;
  String _channelId = '';
  String _serviceType = 'call';
  bool _isInitialized = false;

  // Bridges to the currently-mounted _AgoraCallViewState's real engine calls --
  // registered by the view in initState() and cleared in dispose(), since this
  // provider object outlives any single view instance across rebuilds.
  void Function(bool isMuted)? _micHandler;
  void Function(bool isVideoOff)? _videoHandler;
  VoidCallback? _switchCameraHandler;

  @override
  Future<void> initialize({
    required Map<String, dynamic> config,
    required String currentUserId,
    required String currentUserName,
  }) async {
    _appId          = config['app_id']?.toString() ?? '';
    _appCertificate = config['server_secret']?.toString() ?? '';
    _currentUserId  = currentUserId;
    _serviceType    = config['service_type']?.toString() ?? 'call';

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
  void switchCamera() => _switchCameraHandler?.call();

  @override
  void toggleMic(bool isMuted) => _micHandler?.call(isMuted);

  @override
  void toggleVideo(bool isVideoOff) => _videoHandler?.call(isVideoOff);

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
        body: jsonEncode({'channel': channelName, 'uid': uid, 'expire': 86400, 'service_type': _serviceType}),
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
      owner: this,
      appId: _appId,
      channelId: _channelId,
      isVideoCall: isVideoCall,
      isAudience: false,
      uid: _agoraUid,
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
      owner: this,
      appId: _appId,
      channelId: _channelId,
      isVideoCall: isVideoCall,
      isAudience: !isHost,
      uid: _agoraUid,
      tokenFetcher: _fetchToken,
      onCallEnded: onLeaveCall,
      // Keep the SDK's own text — the live callback takes no argument, so
      // without this the real reason never reaches the server.
      onProviderError: onProviderError != null
          ? (msg) {
              VideoCallManager().lastProviderError = 'Agora: $msg';
              onProviderError();
            }
          : null,
      onLiveStarted: onLiveStarted,
      foreground: foreground,
      isLiveMode: true,
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
  final AgoraProvider owner;
  final String appId;
  final String channelId;
  final bool isVideoCall;
  final bool isAudience;  // false = broadcaster (host/caller), true = viewer
  final int uid;          // numeric Agora uid; must match the token's uid
  final Future<String> Function(String channel, int uid) tokenFetcher;
  final VoidCallback? onCallEnded;
  final VoidCallback? onLiveStarted;
  final void Function(String)? onProviderError;
  final Widget? foreground;
  // true when rendered via buildVideoView() for the live-room screen, which
  // has its own outer mic/camera/flip bar and a separate close button --
  // this view's internal call-style control bar is only needed for 1:1 calls
  // (buildCallView(), webrtc_call_screen.dart) which have no controls of
  // their own.
  final bool isLiveMode;

  const _AgoraCallView({
    required this.owner,
    required this.appId,
    required this.channelId,
    required this.isVideoCall,
    required this.isAudience,
    required this.uid,
    required this.tokenFetcher,
    this.onCallEnded,
    this.onLiveStarted,
    this.onProviderError,
    this.foreground,
    this.isLiveMode = false,
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
    // Let the owning AgoraProvider forward VideoCallProvider interface calls
    // (from the live-room screen's own control buttons) to this view's real
    // engine actions.
    widget.owner._micHandler = _setMic;
    widget.owner._videoHandler = _setVideo;
    widget.owner._switchCameraHandler = _switchCamera;
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
            // Agora usually sends an empty msg here, so the code itself is the
            // only thing that says which of the three went wrong — keep it.
            widget.onProviderError?.call(
                'Agora auth error: ${code.name}${msg.isEmpty ? '' : ' — $msg'}');
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

      // The token is minted for this exact uid, and joinChannel must use the
      // same one -- otherwise Agora rejects it as an invalid token.
      final rtcToken = await widget.tokenFetcher(widget.channelId, widget.uid);

      await engine.joinChannel(
        token: rtcToken,
        channelId: widget.channelId,
        uid: widget.uid,
        options: ChannelMediaOptions(
          clientRoleType: role,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          publishCameraTrack: !widget.isAudience && widget.isVideoCall,
          publishMicrophoneTrack: !widget.isAudience,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideoCall,
        ),
      );
    } catch (e, st) {
      widget.onProviderError?.call('Agora init error: $e');
    }
  }

  @override
  void dispose() {
    // Unregister so the provider never calls back into a disposed State.
    if (identical(widget.owner._micHandler, _setMic)) widget.owner._micHandler = null;
    if (identical(widget.owner._videoHandler, _setVideo)) widget.owner._videoHandler = null;
    if (identical(widget.owner._switchCameraHandler, _switchCamera)) {
      widget.owner._switchCameraHandler = null;
    }
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  void _toggleMic() => _setMic(!_micMuted);
  void _toggleVideo() => _setVideo(!_videoOff);

  void _setMic(bool isMuted) {
    if (!mounted) return;
    setState(() => _micMuted = isMuted);
    _engine?.muteLocalAudioStream(isMuted);
  }

  void _setVideo(bool isOff) {
    if (!mounted) return;
    setState(() => _videoOff = isOff);
    _engine?.muteLocalVideoStream(isOff);
  }

  void _switchCamera() {
    if (!mounted) return;
    setState(() => _switchedCamera = !_switchedCamera);
    _engine?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    // Live streaming, not a 1:1 call: the host IS the broadcast, so their own
    // camera is the full-screen main content -- never a tiny corner preview.
    // A remote feed only exists once a co-host actually joins, at which point
    // it takes the main spot and the host's own camera becomes the small
    // preview instead (same convention as Zego's prebuilt live UI).
    final hasCoHost = _remoteUid != null && widget.isVideoCall;
    final showLocalFullScreen =
        !widget.isAudience && widget.isVideoCall && !hasCoHost;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Main content: co-host's feed once one joins, otherwise the host's
        // own camera (broadcaster) or a waiting message (audience).
        if (hasCoHost)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine!,
              canvas: VideoCanvas(uid: _remoteUid),
              connection: RtcConnection(channelId: widget.channelId),
            ),
          )
        else if (showLocalFullScreen)
          _localJoined
              ? (_videoOff
                  // muteLocalVideoStream() only stops what's SENT to remote
                  // viewers -- the local capture keeps running, so without this
                  // the host's own full-screen preview would look unchanged
                  // when they tap "Camera off", making the button look broken.
                  ? Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.videocam_off,
                            color: Colors.white38, size: 56),
                      ),
                    )
                  : AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ))
              : Container(color: Colors.black)
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

        // Host's own camera as a small corner preview -- only needed once a
        // co-host is on screen and occupying the main area instead.
        if (!widget.isAudience && widget.isVideoCall && hasCoHost && _engine != null)
          Positioned(
            top: 60,
            left: 16,
            width: 110,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _localJoined
                  ? (_videoOff
                      ? Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(Icons.videocam_off,
                                color: Colors.white38, size: 28),
                          ),
                        )
                      : AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: _engine!,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        ))
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

        // Controls bar (broadcaster only, and only for 1:1 calls -- the
        // live-room screen renders its own outer mic/camera/flip bar plus a
        // separate close button, so this would just be a redundant, call-
        // styled duplicate there).
        if (!widget.isAudience && !widget.isLiveMode)
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
