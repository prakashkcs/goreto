import 'dart:math';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/gift_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

// ─── Category tab data ────────────────────────────────────────────────────────
const _kCats = [
  ('all', 'All', '🎁'),
  ('love', 'Love', '❤️'),
  ('vibe', 'Vibe', '🔥'),
  ('luxury', 'Luxury', '💎'),
  ('cute', 'Cute', '🐰'),
  ('funny', 'Funny', '😂'),
  ('general', 'Other', '✨'),
];

// ─── Animation type → Flutter animation mapping ───────────────────────────────
enum _AnimType {
  float,
  pulse,
  bounce,
  spin,
  burst,
  shoot,
  fly,
  sparkle,
  zap,
  shake,
  pop
}

_AnimType _parseAnim(String? s) {
  switch (s) {
    case 'pulse':
      return _AnimType.pulse;
    case 'bounce':
      return _AnimType.bounce;
    case 'spin':
      return _AnimType.spin;
    case 'burst':
      return _AnimType.burst;
    case 'shoot':
      return _AnimType.shoot;
    case 'fly':
      return _AnimType.fly;
    case 'sparkle':
      return _AnimType.sparkle;
    case 'zap':
      return _AnimType.zap;
    case 'shake':
      return _AnimType.shake;
    case 'pop':
      return _AnimType.pop;
    default:
      return _AnimType.float;
  }
}

// ─── Category → gradient ─────────────────────────────────────────────────────
List<Color> _catGradient(String cat) {
  switch (cat) {
    case 'love':
      return [const Color(0xFFFF007F), const Color(0xFFFF6B9D)];
    case 'vibe':
      return [const Color(0xFFFF6B00), const Color(0xFFFFD700)];
    case 'luxury':
      return [const Color(0xFF7C3AED), const Color(0xFFD946EF)];
    case 'cute':
      return [const Color(0xFF06B6D4), const Color(0xFF8B5CF6)];
    case 'funny':
      return [const Color(0xFF22C55E), const Color(0xFF84CC16)];
    default:
      return [const Color(0xFF374151), const Color(0xFF6B7280)];
  }
}

// ─── Main screen ─────────────────────────────────────────────────────────────
class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  final GiftService _giftService = GiftService();
  bool _isLoading = true;
  List<GiftItem> _gifts = [];
  String _selectedCat = 'all';
  String _searchQ = '';
  final _searchCtrl = TextEditingController();

  // Track which gift was just bought (for burst animation)
  int? _justBoughtId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final gifts = await _giftService.getGifts();
      if (!mounted) return;
      setState(() => _gifts = gifts);
    } catch (_) {
      if (!mounted) return;
      NeonToast.error(context, 'Could not load gifts');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _buyGift(GiftItem gift) async {
    final result = await _giftService.buyGift(giftId: gift.id);
    if (!mounted) return;
    NeonToast.info(context, result.message);
    if (result.success) {
      setState(() => _justBoughtId = gift.id);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _justBoughtId = null);
      _load();
    }
  }

  Future<void> _sellGift(GiftItem gift) async {
    final result = await _giftService.sellGift(giftId: gift.id);
    if (!mounted) return;
    NeonToast.info(context, result.message);
    if (result.success) _load();
  }

  List<GiftItem> get _filtered {
    return _gifts.where((g) {
      final catOk =
          _selectedCat == 'all' || (g.category ?? 'general') == _selectedCat;
      final qOk = _searchQ.isEmpty ||
          g.name.toLowerCase().contains(_searchQ.toLowerCase());
      return catOk && qOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080810),
        elevation: 0,
        title: const Text(
          'Gift Shop',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search gifts...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white38, size: 20),
                  suffixIcon: _searchQ.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.white38, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQ = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF141420),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() => _searchQ = v),
              ),
            ),
            // Category tabs
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _kCats.length,
                itemBuilder: (context, i) {
                  final (key, label, emoji) = _kCats[i];
                  final active = _selectedCat == key;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCat = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: active
                            ? const LinearGradient(
                                colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                              )
                            : null,
                        color: active ? null : const Color(0xFF141420),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active ? Colors.transparent : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Gift grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🎁', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text(
                                _searchQ.isNotEmpty
                                    ? 'No gifts match "$_searchQ"'
                                    : 'No gifts in this category',
                                style: const TextStyle(color: Colors.white38),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.78,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final gift = _filtered[index];
                              return _GiftCard(
                                gift: gift,
                                isBurstActive: _justBoughtId == gift.id,
                                onBuy: () => _buyGift(gift),
                                onSell: gift.ownedCount > 0
                                    ? () => _sellGift(gift)
                                    : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated gift card ───────────────────────────────────────────────────────
class _GiftCard extends StatefulWidget {
  final GiftItem gift;
  final bool isBurstActive;
  final VoidCallback onBuy;
  final VoidCallback? onSell;

  const _GiftCard({
    required this.gift,
    required this.isBurstActive,
    required this.onBuy,
    this.onSell,
  });

  @override
  State<_GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends State<_GiftCard> with TickerProviderStateMixin {
  late AnimationController _loopCtrl;
  late AnimationController _burstCtrl;
  late Animation<double> _loopAnim;
  late Animation<double> _burstScale;
  late Animation<double> _burstOpacity;

  @override
  void initState() {
    super.initState();
    final anim = _parseAnim(widget.gift.animationType);

    // Loop animation
    _loopCtrl = AnimationController(
      vsync: this,
      duration: _loopDuration(anim),
    )..repeat(reverse: _loopReverse(anim));

    _loopAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _loopCtrl, curve: _loopCurve(anim)),
    );

    // Burst animation (on buy)
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _burstScale = Tween<double>(begin: 1, end: 1.6).animate(
      CurvedAnimation(parent: _burstCtrl, curve: Curves.elasticOut),
    );
    _burstOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _burstCtrl, curve: const Interval(0.5, 1.0)),
    );
  }

  @override
  void didUpdateWidget(_GiftCard old) {
    super.didUpdateWidget(old);
    if (widget.isBurstActive && !old.isBurstActive) {
      _burstCtrl.forward(from: 0);
    }
  }

  Duration _loopDuration(_AnimType a) {
    switch (a) {
      case _AnimType.pulse:
        return const Duration(milliseconds: 900);
      case _AnimType.bounce:
        return const Duration(milliseconds: 700);
      case _AnimType.spin:
        return const Duration(milliseconds: 2000);
      case _AnimType.zap:
        return const Duration(milliseconds: 400);
      case _AnimType.shake:
        return const Duration(milliseconds: 500);
      default:
        return const Duration(milliseconds: 2400);
    }
  }

  bool _loopReverse(_AnimType a) {
    switch (a) {
      case _AnimType.spin:
      case _AnimType.shoot:
      case _AnimType.fly:
        return false;
      default:
        return true;
    }
  }

  Curve _loopCurve(_AnimType a) {
    switch (a) {
      case _AnimType.bounce:
        return Curves.bounceInOut;
      case _AnimType.pulse:
        return Curves.easeInOut;
      case _AnimType.zap:
        return Curves.easeIn;
      default:
        return Curves.easeInOut;
    }
  }

  @override
  void dispose() {
    _loopCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  Widget _buildAnimatedEmoji(String emoji, _AnimType anim) {
    return AnimatedBuilder(
      animation: _loopAnim,
      builder: (context, child) {
        double tx = 0, ty = 0, scale = 1, rotation = 0, opacity = 1;
        switch (anim) {
          case _AnimType.float:
            ty = -6 * _loopAnim.value;
            break;
          case _AnimType.pulse:
            scale = 1.0 + 0.18 * _loopAnim.value;
            break;
          case _AnimType.bounce:
            ty = -10 * _loopAnim.value;
            break;
          case _AnimType.spin:
            rotation = 2 * pi * _loopAnim.value;
            break;
          case _AnimType.burst:
            scale = 1.0 + 0.12 * sin(_loopAnim.value * pi);
            break;
          case _AnimType.shoot:
            tx = 8 * _loopAnim.value;
            ty = -8 * _loopAnim.value;
            break;
          case _AnimType.fly:
            ty = -12 * _loopAnim.value;
            tx = 4 * sin(_loopAnim.value * pi);
            break;
          case _AnimType.sparkle:
            scale = 1.0 + 0.15 * _loopAnim.value;
            opacity = 0.7 + 0.3 * _loopAnim.value;
            break;
          case _AnimType.zap:
            tx = 3 * ((_loopAnim.value > 0.5) ? 1 : -1);
            break;
          case _AnimType.shake:
            tx = 4 * sin(_loopAnim.value * 2 * pi);
            break;
          case _AnimType.pop:
            scale = 1.0 + 0.2 * sin(_loopAnim.value * pi);
            break;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(tx, ty)
              ..rotateZ(rotation)
              ..scale(scale),
            child: child,
          ),
        );
      },
      child: Text(
        emoji.isNotEmpty ? emoji : '🎁',
        style: const TextStyle(fontSize: 44),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gift = widget.gift;
    final anim = _parseAnim(gift.animationType);
    final emoji = gift.emoji?.isNotEmpty == true ? gift.emoji! : '🎁';
    final cat = gift.category ?? 'general';
    final grad = _catGradient(cat);

    return AnimatedBuilder(
      animation: _burstCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: _burstCtrl.isAnimating ? _burstScale.value : 1.0,
          child: Opacity(
            opacity: _burstCtrl.isAnimating
                ? _burstOpacity.value.clamp(0.3, 1.0)
                : 1.0,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: [
            BoxShadow(
              color: grad[0].withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Emoji area with gradient header
            Container(
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    grad[0].withValues(alpha: 0.18),
                    grad[1].withValues(alpha: 0.08),
                  ],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  // Sparkle particles for sparkle/burst types
                  if (anim == _AnimType.sparkle || anim == _AnimType.burst)
                    ..._buildParticles(grad[0]),
                  Center(
                    child: gift.image?.trim().isNotEmpty == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              gift.image!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildAnimatedEmoji(emoji, anim),
                            ),
                          )
                        : _buildAnimatedEmoji(emoji, anim),
                  ),
                  // Owned badge
                  if (gift.ownedCount > 0)
                    Positioned(
                      top: 6,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: grad),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'x${gift.ownedCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const CoinIcon(size: 12, color: Color(0xFF22C55E)),
                        const SizedBox(width: 3),
                        Text(
                          '${gift.coinPrice}',
                          style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: grad[0].withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              color: grad[0],
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: widget.onBuy,
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: grad),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Buy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onSell != null) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: widget.onSell,
                            child: Container(
                              height: 30,
                              width: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Sell',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParticles(Color color) {
    final rng = Random(widget.gift.id);
    return List.generate(5, (i) {
      final x = rng.nextDouble() * 80 + 10;
      final y = rng.nextDouble() * 60 + 10;
      return AnimatedBuilder(
        animation: _loopAnim,
        builder: (_, __) {
          final opacity =
              (0.3 + 0.5 * sin(_loopAnim.value * pi + i)).clamp(0.0, 1.0);
          return Positioned(
            left: x,
            top: y,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
