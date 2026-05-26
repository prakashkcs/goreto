import 'package:flutter/material.dart';
import 'video_call_provider.dart';

class DyteProvider implements VideoCallProvider {
  @override
  String get name => 'dyte';

  String _meetingId = '';
  String _authToken = '';
  bool _isInitialized = false;

  @override
  Future<void> initialize({
    required Map<String, dynamic> config,
    required String currentUserId,
    required String currentUserName,
  }) async {
    _meetingId = config['meeting_id']?.toString() ?? '';
    _authToken = config['auth_token']?.toString() ?? '';
    _isInitialized = true;
  }

  @override
  Future<void> joinCall(String callId) async {
    _meetingId = callId;
  }

  @override
  Future<void> leaveCall() async {}

  @override
  void switchCamera() {}

  @override
  void toggleMic(bool isMuted) {}

  @override
  void toggleVideo(bool isVideoOff) {}

  @override
  Widget buildCallView({
    required String remoteUserId,
    required String remoteUserName,
    bool isVideoCall = true,
    VoidCallback? onCallEnded,
    void Function(String errorMessage)? onProviderError,
  }) {
    if (!_isInitialized || _meetingId.isEmpty) {
      return const Center(
        child: Text(
          'Dyte not configured.\nCheck Admin → Video Providers.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }
    // Dyte uses a WebView-based SDK. When the SDK package is added,
    // replace this with DyteMeetingView(meetingId: _meetingId, authToken: _authToken).
    return _DyteCallPlaceholder(
      remoteUserName: remoteUserName,
      onCallEnded: onCallEnded,
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
    return const Center(
      child: Text(
        'Dyte live streaming not supported.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}

/// Placeholder call UI for Dyte until the native SDK is wired up.
class _DyteCallPlaceholder extends StatelessWidget {
  final String remoteUserName;
  final VoidCallback? onCallEnded;

  const _DyteCallPlaceholder({
    required this.remoteUserName,
    this.onCallEnded,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              'In call with $remoteUserName',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dyte SDK — connect your meeting view here',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: onCallEnded,
              icon: const Icon(Icons.call_end),
              label: const Text('End Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
