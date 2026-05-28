import 'package:flutter/widgets.dart';
import 'package:love_vibe_pro/services/secure_screen_service.dart';

/// Wrap any widget that contains subscriber-only content the subscriber is
/// allowed to view. While this widget is mounted, FLAG_SECURE is on, so
/// screenshots and screen recording are blocked for the whole window.
///
/// Pair this with the existing SubscriberLockOverlay: the overlay blurs the
/// content for non-subscribers (no need to protect what they can't see), and
/// this wrapper protects the content from the subscriber who CAN see it.
///
/// Reference-counted via SecureScreenService so multiple instances on screen
/// (e.g. a feed scroll showing two subscriber posts at once) keep FLAG_SECURE
/// on until all of them are gone.
class SecureContentArea extends StatefulWidget {
  final Widget child;

  /// When false the widget renders the child unchanged without engaging
  /// FLAG_SECURE — convenient for conditional usage in feed items.
  final bool enabled;

  const SecureContentArea({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<SecureContentArea> createState() => _SecureContentAreaState();
}

class _SecureContentAreaState extends State<SecureContentArea> {
  bool _acquired = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _acquire();
  }

  @override
  void didUpdateWidget(covariant SecureContentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _acquire();
      } else {
        _release();
      }
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _acquire() {
    if (_acquired) return;
    _acquired = true;
    SecureScreenService.instance.acquire();
  }

  void _release() {
    if (!_acquired) return;
    _acquired = false;
    SecureScreenService.instance.release();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
