import 'dart:math';
import 'package:flutter/material.dart';

class _BadgeData {
  final String emoji;
  final String label;
  final int minCoins;
  final Color color1;
  final Color color2;
  const _BadgeData(
      this.emoji, this.label, this.minCoins, this.color1, this.color2);
}

const _kBadgeLevels = <_BadgeData?>[
  null,
  _BadgeData('💝', 'Lovely',    10000,    Color(0xFFFF6B9D), Color(0xFFFF8EBF)),
  _BadgeData('✨', 'Charming',  50000,    Color(0xFF00CED1), Color(0xFF7FFFD4)),
  _BadgeData('🌟', 'Generous',  200000,   Color(0xFFFFD700), Color(0xFFFFA500)),
  _BadgeData('💎', 'Superstar', 500000,   Color(0xFF4FC3F7), Color(0xFF0288D1)),
  _BadgeData('👑', 'Legend',    1500000,  Color(0xFFAB47BC), Color(0xFFE040FB)),
  _BadgeData('🔥', 'Supreme',   5000000,  Color(0xFFFF4500), Color(0xFFFF8C00)),
];

const _kRainbow = [
  Color(0xFFFF0000), Color(0xFFFF7700), Color(0xFFFFFF00),
  Color(0xFF00FF00), Color(0xFF0000FF), Color(0xFF8B00FF), Color(0xFFFF0000),
];

enum GifterBadgeSize { chip, pill }

/// Animated gifter rank badge shown next to usernames throughout the app.
/// Level 0 renders nothing. Levels 1–6 show increasingly impressive styles.
class GifterBadge extends StatefulWidget {
  final int level;
  final GifterBadgeSize size;
  final bool animated;

  const GifterBadge({
    super.key,
    required this.level,
    this.size = GifterBadgeSize.chip,
    this.animated = false,
  });

  static int levelFromCoins(int totalCoinsSent) {
    for (int i = 6; i >= 1; i--) {
      if (totalCoinsSent >= _kBadgeLevels[i]!.minCoins) return i;
    }
    return 0;
  }

  @override
  State<GifterBadge> createState() => _GifterBadgeState();
}

class _GifterBadgeState extends State<GifterBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.level >= 5 ? 1600 : 2200),
    );
    if (widget.animated && widget.level >= 1) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lvl = widget.level.clamp(0, 6);
    if (lvl == 0) return const SizedBox.shrink();
    final data = _kBadgeLevels[lvl]!;
    return widget.size == GifterBadgeSize.chip
        ? _chip(lvl, data)
        : _pill(lvl, data);
  }

  // ── Chip (inline, small) ─────────────────────────────────────────────
  Widget _chip(int lvl, _BadgeData data) {
    final core = _chipCore(data);
    if (!widget.animated || lvl < 3) return core;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: data.color1.withValues(
                  alpha: 0.5 + 0.4 * sin(_ctrl.value * 2 * pi)),
              blurRadius: 5 + 5 * sin(_ctrl.value * 2 * pi),
            ),
          ],
        ),
        child: child,
      ),
      child: core,
    );
  }

  Widget _chipCore(_BadgeData data) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [data.color1, data.color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(data.emoji,
            style: const TextStyle(fontSize: 11, height: 1.2)),
      );

  // ── Pill (profile / prominent display) ──────────────────────────────
  Widget _pill(int lvl, _BadgeData data) {
    final core = _pillCore(data);
    if (!widget.animated) return core;

    if (lvl >= 5) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            gradient: SweepGradient(
              colors: _kRainbow,
              transform: GradientRotation(_ctrl.value * 2 * pi),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
        child: core,
      );
    }

    if (lvl >= 3) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final t = sin(_ctrl.value * 2 * pi) * 0.5 + 0.5;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: data.color1.withValues(alpha: 0.2 + t * 0.45),
                  blurRadius: 4 + t * 12,
                  spreadRadius: t * 2,
                ),
              ],
            ),
            child: child,
          );
        },
        child: core,
      );
    }

    // Level 1–2: gentle shimmer
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = sin(_ctrl.value * 2 * pi) * 0.5 + 0.5;
        return Opacity(opacity: 0.75 + t * 0.25, child: child);
      },
      child: core,
    );
  }

  Widget _pillCore(_BadgeData data) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [data.color1, data.color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data.emoji,
                style: const TextStyle(fontSize: 13, height: 1.2)),
            const SizedBox(width: 5),
            Text(
              data.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
}
