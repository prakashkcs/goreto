import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android 14+ blocks full-screen notifications for apps that are not phone
/// or alarm apps unless the user turns them on. Without it the incoming-call
/// screen and the "someone is nearby" page never open — Android shows only a
/// small banner (seen on the test Samsung: the alert was rejected).
///
/// [maybeAsk] explains this once and opens the exact Settings switch. It asks
/// again at most every 3 days while the switch stays off.
class FullScreenAlertPermission {
  static const _channel = MethodChannel('com.nex.ekloapp/call');
  static const _lastAskKey = 'fsi_prompt_last_ms';

  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> maybeAsk(BuildContext context) async {
    if (!Platform.isAndroid) return;
    if (await isGranted()) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastAskKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(days: 3).inMilliseconds) return;
    await prefs.setInt(_lastAskKey, now);
    if (!context.mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF12101C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x88D946EF)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFFFF007F), Color(0xFF06B6D4)]),
                ),
                child: const Icon(Icons.notifications_active_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              const Text('Turn on full-screen alerts',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'So incoming calls and "someone is nearby" alerts open full '
                'screen, even when your phone is locked. Without it Android '
                'only shows a small banner.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                  ),
                  child: const Text('Turn on',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
    if (go == true) {
      try {
        await _channel.invokeMethod('openFullScreenIntentSettings');
      } catch (_) {}
    }
  }
}
