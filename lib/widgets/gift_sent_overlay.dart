import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── Tier helpers ──────────────────────────────────────────────────────────────
int _giftTier(int coins) {
  if (coins >= 50000) return 3;
  if (coins >= 20000) return 2;
  if (coins >= 8000)  return 1;
  return 0;
}

const _tierPrimary = [
  Color(0xFFFF007F), Color(0xFFBF5AF2), Color(0xFFFF6B00), Color(0xFFFFD700),
];
const _tierSecondary = [
  Color(0xFF00E5FF), Color(0xFF0088FF), Color(0xFFFFD700), Color(0xFFFF6B00),
];
const _tierDurationMs = [2800, 3500, 4500, 5500];
const _tierDrops      = [18,   24,   35,   55];
const _tierSparkles   = [30,   38,   50,   65];
const _tierEmojiPx    = [62.0, 72.0, 82.0, 100.0];
const _tierCircleSize = [130.0, 148.0, 166.0, 190.0];

class _EmojiRainDrop {
  final double x, speed, size, delay;
  final String emoji;
  _EmojiRainDrop({required this.x, required this.speed, required this.size,
      required this.delay, required this.emoji});
}

/// Animated full-screen overlay for gift celebrations — 4 tiers based on coin value.
class GiftSentOverlay {
  static void show(BuildContext context, {
    String? giftImageUrl,
    String? giftName,
    String? emoji,
    int coins = 0,
  }) {
    _showOverlay(context,
      title: 'Gift Sent!',
      subtitle: giftName ?? 'Your gift is on its way',
      giftImageUrl: giftImageUrl,
      emoji: emoji,
      coins: coins,
      primaryColor: _tierPrimary[_giftTier(coins)],
      secondaryColor: _tierSecondary[_giftTier(coins)],
    );
  }

  static void showReceived(BuildContext context, {
    String? giftImageUrl,
    String? giftName,
    String? senderName,
    String? senderAvatar,
    String? emoji,
    int coins = 0,
  }) {
    final subtitle = senderName != null ? 'From $senderName'
        : (giftName ?? 'Someone sent you a gift!');
    _showOverlay(context,
      title: giftName != null ? 'You received $giftName!' : 'Gift Received!',
      subtitle: subtitle,
      giftImageUrl: giftImageUrl,
      senderAvatar: senderAvatar,
      emoji: emoji,
      coins: coins,
      primaryColor: _tierPrimary[_giftTier(coins)],
      secondaryColor: _tierSecondary[_giftTier(coins)],
    );
  }

  static void _showOverlay(BuildContext context, {
    required String title,
    required String subtitle,
    String? giftImageUrl,
    String? senderAvatar,
    String? emoji,
    required Color primaryColor,
    required Color secondaryColor,
    int coins = 0,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GiftOverlayWidget(
        title: title,
        subtitle: subtitle,
        giftImageUrl: giftImageUrl,
        senderAvatar: senderAvatar,
        emoji: emoji,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tier: _giftTier(coins),
        onDismiss: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }
}

// ── Overlay widget ────────────────────────────────────────────────────────────
class _GiftOverlayWidget extends StatefulWidget {
  final String title, subtitle;
  final String? giftImageUrl, senderAvatar, emoji;
  final Color primaryColor, secondaryColor;
  final int tier;
  final VoidCallback onDismiss;

  const _GiftOverlayWidget({
    required this.title, required this.subtitle,
    this.giftImageUrl, this.senderAvatar, this.emoji,
    required this.primaryColor, required this.secondaryColor,
    required this.tier, required this.onDismiss,
  });

  @override
  State<_GiftOverlayWidget> createState() => _GiftOverlayWidgetState();
}

class _GiftOverlayWidgetState extends State<_GiftOverlayWidget>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl, _scaleCtrl, _sparkleCtrl, _glowCtrl, _rainCtrl;
  AnimationController? _pulseCtrl;   // tier 2+
  AnimationController? _shockCtrl;  // tier 3
  AnimationController? _borderCtrl; // tier 3

  late Animation<double> _fadeAnim, _scaleAnim, _sparkleAnim, _glowAnim;

  final List<_Sparkle> _sparkles = [];
  final List<_EmojiRainDrop> _rainDrops = [];
  final Random _rng = Random();

  static const _hearts = ['💗', '💖', '💝', '💕', '✨', '🌟', '💫'];
  static const _legendExtra = ['👑', '🌈', '⭐', '🔥', '💥', '✨', '🌟'];
  static const _vipExtra    = ['⭐', '🔥', '💫', '✨', '🌟', '💥'];
  static const _premExtra   = ['💜', '✨', '💫', '🌟', '⭐'];

  @override
  void initState() {
    super.initState();
    final t = widget.tier;
    final durationMs = _tierDurationMs[t];

    _buildParticles();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);

    _sparkleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _sparkleAnim = CurvedAnimation(parent: _sparkleCtrl, curve: Curves.linear);

    _glowCtrl = AnimationController(vsync: this,
        duration: Duration(milliseconds: t >= 2 ? 800 : 1200));
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _rainCtrl = AnimationController(vsync: this,
        duration: Duration(milliseconds: t >= 3 ? 2200 : t >= 2 ? 2500 : 3000));

    // Tier 2+: pulsing rings
    if (t >= 2) {
      _pulseCtrl = AnimationController(vsync: this,
          duration: Duration(milliseconds: t >= 3 ? 1200 : 1500))
        ..repeat();
    }

    // Tier 3: shockwave (one-shot) + rainbow border
    if (t >= 3) {
      _shockCtrl = AnimationController(vsync: this,
          duration: const Duration(milliseconds: 1200))..forward();
      _borderCtrl = AnimationController(vsync: this,
          duration: const Duration(seconds: 2))..repeat();
    }

    _fadeCtrl.forward();
    _scaleCtrl.forward();
    _sparkleCtrl.repeat();
    _glowCtrl.repeat(reverse: true);
    _rainCtrl.repeat();

    Future.delayed(Duration(milliseconds: durationMs), () {
      if (mounted) {
        _fadeCtrl.reverse().then((_) { if (mounted) widget.onDismiss(); });
      }
    });
  }

  void _buildParticles() {
    final t = widget.tier;
    final nSparkles = _tierSparkles[t];
    final nDrops    = _tierDrops[t];

    for (int i = 0; i < nSparkles; i++) {
      _sparkles.add(_Sparkle(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
        size: 2 + _rng.nextDouble() * 8,
        speed: 0.3 + _rng.nextDouble() * 0.7,
        delay: _rng.nextDouble() * 0.5,
        color: _rng.nextBool() ? widget.primaryColor : widget.secondaryColor,
      ));
    }

    final extraEmojis = t >= 3 ? _legendExtra
        : t == 2 ? _vipExtra
        : t == 1 ? _premExtra
        : const <String>[];

    final giftEmoji = widget.emoji?.isNotEmpty == true ? widget.emoji! : '🎁';
    final rainEmojis = [
      ...List.filled(t >= 3 ? 6 : t >= 2 ? 5 : 4, giftEmoji),
      ..._hearts,
      ...extraEmojis,
    ];

    for (int i = 0; i < nDrops; i++) {
      _rainDrops.add(_EmojiRainDrop(
        x: _rng.nextDouble(),
        speed: 0.2 + _rng.nextDouble() * 0.5,
        size: 18 + _rng.nextDouble() * (t >= 3 ? 24 : t >= 2 ? 18 : 14),
        delay: _rng.nextDouble(),
        emoji: rainEmojis[i % rainEmojis.length],
      ));
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose(); _scaleCtrl.dispose();
    _sparkleCtrl.dispose(); _glowCtrl.dispose(); _rainCtrl.dispose();
    _pulseCtrl?.dispose(); _shockCtrl?.dispose(); _borderCtrl?.dispose();
    super.dispose();
  }

  void _dismiss() {
    _fadeCtrl.reverse().then((_) { if (mounted) widget.onDismiss(); });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final t = widget.tier;
    final overlayAlpha = [0.60, 0.68, 0.75, 0.82][t];

    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onTap: _dismiss,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Background
              Container(
                width: size.width, height: size.height,
                color: Colors.black.withValues(alpha: overlayAlpha),
              ),

              // Tier 3: rainbow screen border
              if (t >= 3 && _borderCtrl != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _borderCtrl!,
                      builder: (_, __) => CustomPaint(
                        size: size,
                        painter: _RainbowScreenBorderPainter(
                            progress: _borderCtrl!.value),
                      ),
                    ),
                  ),
                ),

              // Tier 3: shockwave ring
              if (t >= 3 && _shockCtrl != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shockCtrl!,
                      builder: (_, __) => CustomPaint(
                        size: size,
                        painter: _ShockwavePainter(
                          progress: _shockCtrl!.value,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),

              // Tier 2+: pulse rings
              if (t >= 2 && _pulseCtrl != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _pulseCtrl!,
                      builder: (_, __) => CustomPaint(
                        size: size,
                        painter: _PulseRingPainter(
                          progress: _pulseCtrl!.value,
                          color: widget.primaryColor,
                          tier: t,
                        ),
                      ),
                    ),
                  ),
                ),

              // Sparkle particles
              AnimatedBuilder(
                animation: _sparkleCtrl,
                builder: (_, __) => CustomPaint(
                  size: size,
                  painter: _SparklePainter(
                      sparkles: _sparkles, progress: _sparkleAnim.value),
                ),
              ),

              // Emoji rain
              AnimatedBuilder(
                animation: _rainCtrl,
                builder: (_, __) => Stack(
                  children: _rainDrops.map((drop) {
                    final progress = (_rainCtrl.value + drop.delay) % 1.0;
                    final y = -40 + progress * (size.height + 80);
                    final opacity = progress < 0.08 ? progress / 0.08
                        : progress > 0.88 ? (1 - progress) / 0.12
                        : 1.0;
                    return Positioned(
                      left: drop.x * size.width,
                      top: y,
                      child: Opacity(
                        opacity: (opacity * 0.9).clamp(0.0, 1.0),
                        child: Text(drop.emoji,
                            style: TextStyle(fontSize: drop.size)),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Center card
              Center(
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tier badge
                      _buildTierBadge(t),
                      const SizedBox(height: 8),

                      // Glowing gift visual
                      AnimatedBuilder(
                        animation: _glowCtrl,
                        builder: (_, child) {
                          final g = _glowAnim.value;
                          final baseBlur  = [30.0, 36.0, 45.0, 60.0][t];
                          final extraBlur = [30.0, 35.0, 40.0, 50.0][t];
                          return Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.primaryColor.withValues(alpha: 0.3 + g * 0.45),
                                  blurRadius: baseBlur + g * extraBlur,
                                  spreadRadius: 5 + g * (t >= 3 ? 20 : 10),
                                ),
                                BoxShadow(
                                  color: widget.secondaryColor.withValues(alpha: 0.2 + g * 0.3),
                                  blurRadius: 50 + g * 20,
                                  spreadRadius: 2 + g * 8,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: _buildGiftVisual(t),
                      ),
                      const SizedBox(height: 28),

                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [widget.primaryColor, widget.secondaryColor],
                        ).createShader(bounds),
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: [32.0, 34.0, 36.0, 40.0][t],
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: [16.0, 17.0, 18.0, 20.0][t],
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),

                      if (widget.senderAvatar?.isNotEmpty == true) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: [widget.primaryColor, widget.secondaryColor]),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundImage: CachedNetworkImageProvider(widget.senderAvatar!),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                      Text('Tap to dismiss',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTierBadge(int t) {
    if (t == 0) return const SizedBox.shrink();
    final configs = [
      null,
      {'text': '💜  P R E M I U M', 'colors': [const Color(0xFFBF5AF2), const Color(0xFF7B61FF)]},
      {'text': '⭐  V I P  ⭐',     'colors': [const Color(0xFFFF6B00), const Color(0xFFFFD700)]},
      {'text': '👑  L E G E N D A R Y  👑', 'colors': [const Color(0xFFFFD700), const Color(0xFFFF6B00), const Color(0xFFFF007F)]},
    ];
    final cfg = configs[t]!;
    final colors = (cfg['colors'] as List).cast<Color>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: colors.first.withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: Text(
        cfg['text'] as String,
        style: TextStyle(
          color: t == 1 ? Colors.white : Colors.black,
          fontSize: t >= 3 ? 13 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildGiftVisual(int t) {
    final hasImage = widget.giftImageUrl?.isNotEmpty == true;
    final hasEmoji = widget.emoji?.isNotEmpty == true;
    final circleSize = _tierCircleSize[t];
    final emojiSize  = _tierEmojiPx[t];

    Widget inner;
    if (hasImage) {
      inner = CachedNetworkImage(
        imageUrl: widget.giftImageUrl!,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => Text(
          hasEmoji ? widget.emoji! : '🎁',
          style: TextStyle(fontSize: emojiSize),
        ),
      );
    } else {
      inner = Text(
        hasEmoji ? widget.emoji! : '🎁',
        style: TextStyle(fontSize: emojiSize),
      );
    }

    return Container(
      width: circleSize, height: circleSize,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          widget.primaryColor.withValues(alpha: t >= 3 ? 0.35 : 0.25),
          widget.secondaryColor.withValues(alpha: t >= 3 ? 0.20 : 0.15),
        ]),
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: t >= 3 ? 0.9 : 0.6),
          width: t >= 3 ? 3 : 2,
        ),
      ),
      child: Center(child: inner),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────
class _Sparkle {
  final double x, y, size, speed, delay;
  final Color color;
  _Sparkle({required this.x, required this.y, required this.size,
      required this.speed, required this.delay, required this.color});
}

class _SparklePainter extends CustomPainter {
  final List<_Sparkle> sparkles;
  final double progress;
  _SparklePainter({required this.sparkles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final t = (progress + s.delay) % 1.0;
      final alpha = t < 0.5 ? t * 2 : 2 - t * 2;
      if (alpha <= 0) continue;
      final paint = Paint()
        ..color = s.color.withValues(alpha: alpha * 0.8)
        ..style = PaintingStyle.fill;
      final cx = size.width * 0.5;
      final cy = size.height * 0.5;
      final angle  = s.x * 2 * pi;
      final radius = (0.15 + t * s.speed) * size.width * 0.5;
      final px = cx + cos(angle + progress * 2 * pi * s.speed) * radius;
      final py = cy + sin(angle + progress * 2 * pi * s.speed) * radius * 0.8 - t * 80;
      _drawStar(canvas, px, py, s.size * alpha, paint);
    }
  }

  void _drawStar(Canvas canvas, double x, double y, double size, Paint paint) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = i * pi / 2;
      final outerX = x + cos(a) * size;
      final outerY = y + sin(a) * size;
      final ia = a + pi / 4;
      final innerX = x + cos(ia) * size * 0.35;
      final innerY = y + sin(ia) * size * 0.35;
      if (i == 0) { path.moveTo(outerX, outerY); } else { path.lineTo(outerX, outerY); }
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(x, y), size * 1.2,
        Paint()..color = paint.color.withValues(alpha: 0.3)
               ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.progress != progress;
}

class _PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int tier;
  _PulseRingPainter({required this.progress, required this.color, required this.tier});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final maxRadius = size.width * 0.52;
    final ringCount = tier >= 3 ? 4 : 3;

    for (int i = 0; i < ringCount; i++) {
      final t = (progress + i / ringCount) % 1.0;
      final radius = t * maxRadius;
      final alpha  = (1.0 - t) * 0.55;
      final stroke = (1.0 - t) * 3.5 + 1.0;
      if (alpha <= 0) continue;
      canvas.drawCircle(
        center, radius,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) => old.progress != progress;
}

class _ShockwavePainter extends CustomPainter {
  final double progress;
  final Color color;
  _ShockwavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.42);
    final maxR   = size.width * 1.1;
    final radius = progress * maxR;
    final alpha  = (1.0 - progress) * 0.85;
    final stroke = (1.0 - progress) * 10 + 2;

    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // Inner ring
    if (progress < 0.7) {
      final r2 = progress * maxR * 0.55;
      canvas.drawCircle(
        center, r2,
        Paint()
          ..color = Colors.white.withValues(alpha: (1 - progress / 0.7) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - progress) * 5 + 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShockwavePainter old) => old.progress != progress;
}

class _RainbowScreenBorderPainter extends CustomPainter {
  final double progress;
  static const _colors = [
    Color(0xFFFF0080), Color(0xFFFF6B00), Color(0xFFFFD700),
    Color(0xFF00FF88), Color(0xFF00DDFF), Color(0xFF7B61FF), Color(0xFFFF0080),
  ];
  _RainbowScreenBorderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 4.0;
    final rect  = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(0));
    final rotate = GradientRotation(progress * 2 * pi);

    canvas.drawRRect(rrect,
      Paint()
        ..shader = SweepGradient(colors: _colors, transform: rotate).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawRRect(rrect,
      Paint()
        ..shader = SweepGradient(
            colors: _colors.map((c) => c.withValues(alpha: 0.45)).toList(),
            transform: rotate).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(covariant _RainbowScreenBorderPainter old) => old.progress != progress;
}
