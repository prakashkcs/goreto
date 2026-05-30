import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

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
