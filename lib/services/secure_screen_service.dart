import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reference-counted FLAG_SECURE toggle. Multiple subscriber-only widgets
/// can be on screen at once (e.g. two video items partially visible in a
/// feed scroll); each calls [acquire] when it becomes the active subscriber
/// view and [release] when it leaves. The window stays secure as long as at
/// least one acquirer is active.
class SecureScreenService {
  SecureScreenService._();
  static final SecureScreenService instance = SecureScreenService._();

  static const _channel = MethodChannel('com.nex.ekloapp/secure');

  int _count = 0;
  bool _native = false;

  Future<void> acquire() async {
    _count++;
    if (_count > 0 && !_native) {
      _native = true;
      await _setNative(true);
    }
  }

  Future<void> release() async {
    if (_count > 0) _count--;
    if (_count == 0 && _native) {
      _native = false;
      await _setNative(false);
    }
  }

  /// Force-clear the secure state. Useful from app-lifecycle paused/detached
  /// hooks so a crash inside a subscriber view doesn't leave FLAG_SECURE on
  /// the next launch (it wouldn't, since it's a per-window flag, but safer).
  Future<void> reset() async {
    _count = 0;
    if (_native) {
      _native = false;
      await _setNative(false);
    }
  }

  Future<void> _setNative(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'enabled': enabled});
    } catch (_) {
      // Channel may not be wired up on iOS / web / desktop — silently ignore.
    }
  }

  bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
