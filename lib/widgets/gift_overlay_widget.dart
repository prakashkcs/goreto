import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/login_required_sheet.dart';

/// Model for a gift transaction displayed on the overlay.
class GiftTx {
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String giftName;
  final String gifUrl;
  final String emoji;
  final int coinPrice;
  final DateTime createdAt;

  const GiftTx({
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.giftName,
    required this.gifUrl,
    this.emoji = '🎁',
    required this.coinPrice,
    required this.createdAt,
  });

  factory GiftTx.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map
        ? json['sender'] as Map<String, dynamic>
        : <String, dynamic>{};
    final rawEmoji = (json['emoji'] ?? '').toString().trim();
    return GiftTx(
      senderId: (json['sender_id'] ?? sender['id'] ?? sender['user_id'] ?? '')
          .toString(),
      senderName:
          (json['sender_name'] ??
                  sender['name'] ??
                  sender['username'] ??
                  'User')
              .toString(),
      senderAvatar:
          (json['sender_avatar'] ??
                  json['sender_pic'] ??
                  sender['avatar'] ??
                  sender['avatar_url'] ??
                  '')
              .toString(),
      giftName: (json['gift_name'] ?? json['name'] ?? 'Gift').toString(),
      gifUrl: (json['gif_url'] ?? json['thumb_image'] ?? json['image'] ?? '')
          .toString(),
      emoji: rawEmoji.isNotEmpty ? rawEmoji : '🎁',
      coinPrice:
          int.tryParse((json['coin_price'] ?? json['price'] ?? 0).toString()) ??
          0,
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Set to true to inject fake test gifts when the real list is empty.
/// Only works in debug mode (kDebugMode).
bool kShowFakeGiftsOverlay = true;

/// Fake test gifts for development/testing.
List<GiftTx> _fakeTestGifts() => [
  GiftTx(
    senderId: 'test_1',
    senderName: 'Prakash',
    senderAvatar: '',
    giftName: 'Diamond',
    gifUrl: 'https://media.giphy.com/media/26tPplGWjN0xLybiU/giphy.gif',
    coinPrice: 500,
    createdAt: DateTime.now().subtract(const Duration(seconds: 10)),
  ),
  GiftTx(
    senderId: 'test_2',
    senderName: 'Anita',
    senderAvatar: '',
    giftName: 'Rose',
    gifUrl: 'https://media.giphy.com/media/l0HlNQ03J5JxX2rza/giphy.gif',
    coinPrice: 200,
    createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
  ),
];

/// Animated gift overlay that cycles through the top 3 gifts on a post/reel.
/// Shows sender avatar, name, gift, coin price — and optionally a Follow button.
class GiftOverlayWidget extends StatefulWidget {
  final List<GiftTx> gifts;

  /// Called when the viewer taps Follow on the overlay. Receives the senderId.
  final Future<void> Function(String senderId)? onFollow;

  /// A set of user IDs that the viewer already follows — used to hide the
  /// Follow button for senders the viewer is already following.
  final Set<String> followingIds;

  /// The current viewer's own user ID — Follow is hidden for the post owner.
  final String? viewerUserId;

  const GiftOverlayWidget({
    super.key,
    required this.gifts,
    this.onFollow,
    this.followingIds = const {},
    this.viewerUserId,
  });

  @override
  State<GiftOverlayWidget> createState() => _GiftOverlayWidgetState();
}

class _GiftOverlayWidgetState extends State<GiftOverlayWidget>
    with SingleTickerProviderStateMixin {
  late List<GiftTx> _sorted;
  int _currentIndex = 0;
  Timer? _cycleTimer;
  Timer? _hideTimer;
  bool _visible = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _sorted = _sortGifts(widget.gifts);

    if (_sorted.isNotEmpty) {
      _animController.forward();
      _startCycleTimer();
      _startHideTimer();
    }
  }

  @override
  void didUpdateWidget(covariant GiftOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gifts != oldWidget.gifts) {
      _sorted = _sortGifts(widget.gifts);
      _currentIndex = 0;
      if (_sorted.isNotEmpty) {
        _visible = true;
        _animController.forward(from: 0);
        _startCycleTimer();
        _startHideTimer();
      }
    }
  }

  List<GiftTx> _sortGifts(List<GiftTx> gifts) {
    var list = List<GiftTx>.from(gifts);

    // Inject fake test gifts when empty and debug flag is on
    if (list.isEmpty && kDebugMode && kShowFakeGiftsOverlay) {
      list = _fakeTestGifts();
    }

    list.sort((a, b) {
      final priceCmp = b.coinPrice.compareTo(a.coinPrice);
      if (priceCmp != 0) return priceCmp;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list.take(3).toList();
  }

  void _startCycleTimer() {
    _cycleTimer?.cancel();
    if (_sorted.length <= 1) return;
    _cycleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_visible) return;
      _animController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _currentIndex = (_currentIndex + 1) % _sorted.length;
        });
        _animController.forward();
      });
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _animController.reverse().then((_) {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sorted.isEmpty || !_visible) return const SizedBox.shrink();

    final gift = _sorted[_currentIndex];
    final alreadyFollowing = widget.followingIds.contains(gift.senderId);
    final isOwnGift = widget.viewerUserId != null &&
        widget.viewerUserId == gift.senderId;
    final showFollow = widget.onFollow != null && !alreadyFollowing && !isOwnGift;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD946EF).withValues(alpha: 0.18),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sender avatar
              _buildAvatar(gift.senderAvatar, gift.senderName),
              const SizedBox(width: 8),
              // Text info
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gift.senderName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'sent ${gift.giftName} · ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '${gift.coinPrice}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const CoinIcon(size: 10, color: Colors.amber),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Gift thumbnail
              _buildGiftThumb(gift.gifUrl, emoji: gift.emoji),
              // Follow button — shown only when not already following
              if (showFollow) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => widget.onFollow!(gift.senderId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD946EF), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Follow',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String url, String name) {
    if (url.isNotEmpty && url.startsWith('http')) {
      return CircleAvatar(
        radius: 14,
        backgroundImage: CachedNetworkImageProvider(url),
        backgroundColor: const Color(0xFF1A1A1A),
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFFD946EF),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGiftThumb(String url, {String emoji = '🎁'}) {
    if (url.isNotEmpty && url.startsWith('http')) {
      return SizedBox(
        width: 32,
        height: 32,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) =>
              Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      );
    }
    return Text(emoji, style: const TextStyle(fontSize: 20));
  }
}

/// Compact animated chip shown on a post/video that has received gifts: the top
/// gifter's gift + avatar + name + coins, with a one-tap Follow button.
/// Animates in (scale + fade) so a new gift feels alive. Tapping the body runs
/// [onTap] (open the full gifter leaderboard).
class TopGifterChip extends StatefulWidget {
  final List<GiftTx> gifts;
  final ApiService api;
  final bool isGuest;
  final String? currentUserId;
  final VoidCallback onTap;

  const TopGifterChip({
    super.key,
    required this.gifts,
    required this.api,
    required this.isGuest,
    required this.onTap,
    this.currentUserId,
  });

  @override
  State<TopGifterChip> createState() => _TopGifterChipState();
}

class _TopGifterChipState extends State<TopGifterChip>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Timer? _timer;
  bool _following = false;
  bool _busy = false;
  late List<GiftTx> _sorted;
  // Drives the looping float / glow / border shimmer.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _sorted = _sortGifts(widget.gifts);
    _startCycle();
  }

  @override
  void didUpdateWidget(covariant TopGifterChip old) {
    super.didUpdateWidget(old);
    if (widget.gifts.length != old.gifts.length) {
      _sorted = _sortGifts(widget.gifts);
      if (_index >= _sorted.length) _index = 0;
      _startCycle();
    }
  }

  List<GiftTx> _sortGifts(List<GiftTx> g) =>
      List<GiftTx>.from(g)..sort((a, b) => b.coinPrice.compareTo(a.coinPrice));

  void _startCycle() {
    _timer?.cancel();
    if (_sorted.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _sorted.length;
        _following = false;
        _busy = false;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loop.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow(String id) async {
    if (widget.isGuest) {
      LoginRequiredSheet.show(context, feature: 'follow people');
      return;
    }
    if (id.isEmpty || _busy) return;
    final next = !_following;
    setState(() {
      _following = next;
      _busy = true;
    });
    try {
      if (next) {
        await widget.api.followUser(id);
      } else {
        await widget.api.unfollowUser(id);
      }
    } catch (_) {
      if (mounted) setState(() => _following = !next);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Rarity colour by coin value: gold / purple / pink / cyan.
  static Color _tierColor(int coins) {
    if (coins >= 1000) return const Color(0xFFFFC83D);
    if (coins >= 200) return const Color(0xFFD946EF);
    if (coins >= 20) return const Color(0xFFFF007F);
    return const Color(0xFF06B6D4);
  }

  @override
  Widget build(BuildContext context) {
    if (_sorted.isEmpty) return const SizedBox.shrink();
    if (_index >= _sorted.length) _index = 0;
    final t = _sorted[_index];
    final total = _sorted.length;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.25, 0),
            end: Offset.zero,
          ).animate(anim),
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(anim),
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
      child: _chip(t, total,
          key: ValueKey('${t.senderId}_${t.giftName}_$_index')),
    );
  }

  Widget _chip(GiftTx t, int total, {Key? key}) {
    final name =
        t.senderName.trim().isEmpty ? 'Someone' : t.senderName.split(' ').first;
    final avatar = t.senderAvatar;
    final hasAvatar = avatar.startsWith('http');
    final isSelf =
        widget.currentUserId != null && t.senderId == widget.currentUserId;
    final tier = _tierColor(t.coinPrice);

    return AnimatedBuilder(
      key: key,
      animation: _loop,
      builder: (context, _) {
        final v = _loop.value; // 0..1
        final wave = math.sin(v * 2 * math.pi); // -1..1
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            // Animated gradient border: the shimmer sweeps around the chip.
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: SweepGradient(
                transform: GradientRotation(v * 2 * math.pi),
                colors: [
                  tier,
                  tier.withValues(alpha: 0.15),
                  const Color(0xFF06B6D4).withValues(alpha: 0.6),
                  tier.withValues(alpha: 0.15),
                  tier,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: tier.withValues(alpha: 0.28 + 0.12 * wave),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              decoration: BoxDecoration(
                color: const Color(0xE6100B1A),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Floating gift with a pulsing glow + total badge.
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              tier.withValues(alpha: 0.45 + 0.15 * wave),
                              tier.withValues(alpha: 0.0),
                            ]),
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(0, -2.5 * wave),
                          child: Transform.rotate(
                            angle: 0.06 * wave,
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: (t.gifUrl.isNotEmpty &&
                                      t.gifUrl.startsWith('http'))
                                  ? CachedNetworkImage(
                                      imageUrl: t.gifUrl,
                                      fit: BoxFit.contain,
                                      errorWidget: (_, __, ___) => Center(
                                        child: Text(t.emoji,
                                            style:
                                                const TextStyle(fontSize: 20)),
                                      ),
                                    )
                                  : Center(
                                      child: Text(t.emoji,
                                          style: const TextStyle(fontSize: 20)),
                                    ),
                            ),
                          ),
                        ),
                        if (total > 1)
                          Positioned(
                            right: -3,
                            top: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFFFF007F),
                                  Color(0xFFD946EF)
                                ]),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF100B1A), width: 1),
                              ),
                              child: Text('$total',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Gifter avatar with a tier-coloured ring.
                  Container(
                    padding: const EdgeInsets.all(1.4),
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: tier),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: const Color(0xFF2A1A3E),
                      backgroundImage:
                          hasAvatar ? CachedNetworkImageProvider(avatar) : null,
                      child: hasAvatar
                          ? null
                          : Text(name[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 1),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'sent ${t.giftName.isNotEmpty ? t.giftName : 'a gift'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 9.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            CoinIcon(size: 9, color: tier),
                            const SizedBox(width: 2),
                            Text('${t.coinPrice}',
                                style: TextStyle(
                                    color: tier,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isSelf) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _toggleFollow(t.senderId),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: _following
                              ? null
                              : const LinearGradient(colors: [
                                  Color(0xFFFF007F),
                                  Color(0xFFD946EF)
                                ]),
                          color: _following
                              ? Colors.white.withValues(alpha: 0.14)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          border: _following
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.3))
                              : null,
                        ),
                        child: Text(_following ? 'Following' : 'Follow',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
