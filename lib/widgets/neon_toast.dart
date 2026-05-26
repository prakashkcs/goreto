import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum NeonToastType { success, error, info, warning }

/// Strips "Exception: " / "DioException: " prefixes from raw exception strings
/// so users never see debug noise.
String _cleanMessage(String raw) {
  String s = raw;
  for (final prefix in [
    'DioException [bad response]: ',
    'DioException: ',
    'Exception: ',
    'Error: ',
    'FormatException: ',
    'HttpException: ',
  ]) {
    if (s.startsWith(prefix)) {
      s = s.substring(prefix.length);
      break;
    }
  }
  // Cap length for display
  if (s.length > 120) s = '${s.substring(0, 118)}…';
  return s.trim();
}

class NeonToast {
  static OverlayEntry? _currentEntry;
  static bool _isRemoving = false;

  static void show(
    BuildContext context,
    String message, {
    NeonToastType type = NeonToastType.info,
    String? title,
    String? imageUrl,
    Duration duration = const Duration(milliseconds: 3000),
    VoidCallback? onTap,
  }) {
    _dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);
    final cleanedMsg = _cleanMessage(message);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NeonToastWidget(
        message: cleanedMsg,
        title: title,
        type: type,
        imageUrl: imageUrl,
        duration: duration,
        onDismiss: () => _removeEntry(entry),
        onTap: onTap,
      ),
    );

    _currentEntry = entry;
    _isRemoving = false;
    overlay.insert(entry);

    // Haptic feedback
    switch (type) {
      case NeonToastType.success:
        HapticFeedback.lightImpact();
        break;
      case NeonToastType.error:
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.selectionClick();
    }
  }

  static void _dismiss() {
    if (_currentEntry != null && !_isRemoving) {
      _removeEntry(_currentEntry!);
    }
  }

  static void _removeEntry(OverlayEntry entry) {
    _isRemoving = true;
    try {
      entry.remove();
    } catch (_) {}
    if (_currentEntry == entry) _currentEntry = null;
    _isRemoving = false;
  }

  static void success(BuildContext context, String message,
          {String? title, String? imageUrl, VoidCallback? onTap}) =>
      show(context, message,
          type: NeonToastType.success,
          title: title ?? 'Success',
          imageUrl: imageUrl,
          onTap: onTap);

  static void error(BuildContext context, String message,
          {String? title, String? imageUrl, VoidCallback? onTap}) =>
      show(context, message,
          type: NeonToastType.error,
          title: title ?? 'Oops!',
          imageUrl: imageUrl,
          onTap: onTap);

  static void info(BuildContext context, String message,
          {String? title, String? imageUrl, VoidCallback? onTap}) =>
      show(context, message,
          type: NeonToastType.info,
          title: title,
          imageUrl: imageUrl,
          onTap: onTap);

  static void warning(BuildContext context, String message,
          {String? title, String? imageUrl, VoidCallback? onTap}) =>
      show(context, message,
          type: NeonToastType.warning,
          title: title ?? 'Warning',
          imageUrl: imageUrl,
          onTap: onTap);
}

class _NeonToastWidget extends StatefulWidget {
  final String message;
  final String? title;
  final NeonToastType type;
  final String? imageUrl;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _NeonToastWidget({
    required this.message,
    this.title,
    required this.type,
    this.imageUrl,
    required this.duration,
    required this.onDismiss,
    this.onTap,
  });

  @override
  State<_NeonToastWidget> createState() => _NeonToastWidgetState();
}

class _NeonToastWidgetState extends State<_NeonToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 280),
    );

    _slide = Tween<Offset>(
            begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _ctrl,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic));

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5)));

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _ctrl.forward();
    Future.delayed(widget.duration, _dismissAnimated);
  }

  Future<void> _dismissAnimated() async {
    if (!mounted) return;
    try {
      await _ctrl.reverse();
    } catch (_) {}
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      left: 12,
      right: 12,
      top: topPadding + 8,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onTap?.call();
                _dismissAnimated();
              },
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < -4) _dismissAnimated();
              },
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cfg = _config;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                cfg.color.withValues(alpha: 0.18),
                const Color(0xFF0D0D1A).withValues(alpha: 0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: cfg.color.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: cfg.color.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildIcon(cfg),
                    const SizedBox(width: 12),
                    Expanded(child: _buildText()),
                    const SizedBox(width: 8),
                    _buildCloseBtn(),
                  ],
                ),
              ),
              // Progress drain bar
              _ProgressBar(
                duration: widget.duration,
                color: cfg.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(_ToastConfig cfg) {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: CachedNetworkImageProvider(widget.imageUrl!),
        backgroundColor: Colors.transparent,
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            cfg.color.withValues(alpha: 0.30),
            cfg.color.withValues(alpha: 0.06),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cfg.color.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Icon(cfg.icon, color: cfg.color, size: 24),
    );
  }

  Widget _buildText() {
    final hasTitle = widget.title != null && widget.title!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle)
          Text(
            widget.title!,
            style: TextStyle(
              color: _config.color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              decoration: TextDecoration.none,
            ),
          ),
        if (hasTitle) const SizedBox(height: 2),
        Text(
          widget.message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
            decoration: TextDecoration.none,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildCloseBtn() {
    return GestureDetector(
      onTap: _dismissAnimated,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        child: const Icon(Icons.close_rounded,
            color: Colors.white54, size: 14),
      ),
    );
  }

  _ToastConfig get _config {
    switch (widget.type) {
      case NeonToastType.success:
        return const _ToastConfig(
            color: Color(0xFF22C55E), icon: Icons.check_circle_rounded);
      case NeonToastType.error:
        return const _ToastConfig(
            color: Color(0xFFFF3B30), icon: Icons.error_rounded);
      case NeonToastType.warning:
        return const _ToastConfig(
            color: Color(0xFFFF9F0A), icon: Icons.warning_amber_rounded);
      case NeonToastType.info:
        return const _ToastConfig(
            color: Color(0xFF0A84FF), icon: Icons.info_rounded);
    }
  }
}

/// Thin progress bar that drains over the toast duration
class _ProgressBar extends StatefulWidget {
  final Duration duration;
  final Color color;
  const _ProgressBar({required this.duration, required this.color});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => LinearProgressIndicator(
        value: 1.0 - _ctrl.value,
        minHeight: 2.5,
        backgroundColor: widget.color.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation(widget.color.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _ToastConfig {
  final Color color;
  final IconData icon;
  const _ToastConfig({required this.color, required this.icon});
}
