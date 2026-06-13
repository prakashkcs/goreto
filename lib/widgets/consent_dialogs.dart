import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prominent in-app disclosure dialogs.
///
/// Google Play's Personal & Sensitive Information policy requires a clear,
/// in-context disclosure of sensitive data collection (location, camera,
/// microphone, photos) shown BEFORE the runtime permission prompt — not buried
/// in the Terms or Privacy Policy. These dialogs satisfy that requirement.
///
/// The disclosure is shown once and the acknowledgement is persisted so the
/// user isn't repeatedly interrupted.
class ConsentDialogs {
  static const _ackKey = 'prominent_disclosure_ack_v1';

  static const _bg = Color(0xFF15121E);
  static const _accent = Color(0xFFD946EF);

  /// Shows the combined data-use disclosure once. Returns true once the user
  /// has acknowledged it (or had already acknowledged it previously). Call this
  /// immediately BEFORE requesting location/camera/microphone permissions.
  static Future<bool> ensureDataDisclosure(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_ackKey) == true) return true;
    if (!context.mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _accent.withValues(alpha: 0.5), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: _accent),
            SizedBox(width: 8),
            Expanded(
              child: Text('Before you continue',
                  style: TextStyle(color: Colors.white, fontSize: 17)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To make Goreto work, we ask for permission to use:',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(height: 14),
              _row(Icons.location_on_outlined, 'Location',
                  'To show people and matches near you and your approximate distance. Your exact location is never shown to others. Background location keeps nearby discovery current and can be turned off anytime.'),
              _row(Icons.videocam_outlined, 'Camera & microphone',
                  'For video and audio calls, live streams and voice messages.'),
              _row(Icons.photo_library_outlined, 'Photos',
                  'To set a profile picture and share posts you choose.'),
              const SizedBox(height: 10),
              Text(
                'You can review or change these anytime in Settings → Privacy. See our Privacy Policy for full details.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Not now', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await prefs.setBool(_ackKey, true);
      return true;
    }
    return false;
  }

  static Widget _row(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
