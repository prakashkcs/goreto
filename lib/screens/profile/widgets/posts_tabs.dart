import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/user_post.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Posts section with tabs: Photos | Reels | Gifts
class PostsTabs extends StatefulWidget {
  final List<UserPost> posts;
  final List<Map<String, dynamic>> gifts;
  final bool isOwnProfile;
  final void Function(UserPost)? onPostTap;
  final void Function(PostType)? onTabChanged;
  final VoidCallback? onGiftSold;

  const PostsTabs({
    super.key,
    required this.posts,
    this.gifts = const [],
    this.isOwnProfile = false,
    this.onPostTap,
    this.onTabChanged,
    this.onGiftSold,
  });

  @override
  State<PostsTabs> createState() => _PostsTabsState();
}

class _PostsTabsState extends State<PostsTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  final List<String> _tabs = ['Photos', 'Reels', 'Gifts'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() => _selectedTabIndex = _tabController.index);
      if (_selectedTabIndex < 2) {
        widget.onTabChanged?.call(
          _selectedTabIndex == 0 ? PostType.photo : PostType.reel,
        );
      }
    }
  }

  /// Photos — exclude reshares
  List<UserPost> get _photoPosts => widget.posts
      .where((p) => p.type == PostType.photo && !p.isRepost)
      .toList();

  /// Reels — exclude reshares
  List<UserPost> get _reelPosts => widget.posts
      .where(
        (p) =>
            (p.type == PostType.reel || p.type == PostType.video) &&
            !p.isRepost,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tab bar ──
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // ── Tab content ──
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey(_selectedTabIndex),
            child: _buildTabContent(_selectedTabIndex),
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent(int index) {
    switch (index) {
      case 0:
        return _buildPhotoGridSection(_photoPosts);
      case 1:
        return _buildReelGridSection(_reelPosts);
      case 2:
        return _buildGiftsSection(widget.gifts);
      default:
        return const SizedBox();
    }
  }

  // ─────────────────────────── PHOTOS ───────────────────────────

  Widget _buildPhotoGridSection(List<UserPost> posts) {
    if (posts.isEmpty) {
      return _buildEmpty(Icons.photo_library, 'No photos yet');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) => _buildPhotoItem(posts[index]),
    );
  }

  Widget _buildPhotoItem(UserPost post) {
    return GestureDetector(
      onTap: () => widget.onPostTap?.call(post),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF007F).withValues(alpha: 0.3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: post.mediaUrl,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                errorWidget: (p1_0, p1_1, p1_2) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: const Icon(Icons.image, color: Colors.white24),
                ),
              ),
              // Views badge
              Positioned(
                bottom: 4,
                left: 4,
                child: _viewBadge(
                  post.viewsTotal,
                  uniqueViews: post.viewsUnique,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── REELS ────────────────────────────

  Widget _buildReelGridSection(List<UserPost> posts) {
    if (posts.isEmpty) {
      return _buildEmpty(Icons.movie, 'No reels yet');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 9 / 16,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) => _buildVideoItem(posts[index]),
    );
  }

  Widget _buildVideoItem(UserPost post) {
    return _ReelGridItem(
      post: post,
      onTap: () => widget.onPostTap?.call(post),
      viewBadgeBuilder: (total, unique) =>
          _viewBadge(total, uniqueViews: unique, small: false),
    );
  }

  // ───────────────────────────── GIFTS ──────────────────────────

  /// Group gifts by gift_id and sum quantities (handles backend returning
  /// one row per sender for the same gift type).
  List<Map<String, dynamic>> _groupGifts(List<Map<String, dynamic>> raw) {
    final Map<int, Map<String, dynamic>> grouped = {};
    for (final g in raw) {
      final id = int.tryParse(
              (g['gift_id'] ?? g['id'] ?? '0').toString()) ??
          0;
      if (id == 0) continue;
      if (grouped.containsKey(id)) {
        final prev = grouped[id]!;
        final prevQty =
            int.tryParse(prev['qty']?.toString() ?? '0') ?? 0;
        final addQty =
            int.tryParse(g['qty']?.toString() ?? '0') ?? 0;
        grouped[id] = {...prev, 'qty': prevQty + addQty};
      } else {
        grouped[id] = Map<String, dynamic>.from(g);
      }
    }
    final list = grouped.values.toList();
    list.sort((a, b) {
      final pa =
          int.tryParse(a['coin_price']?.toString() ?? '0') ?? 0;
      final pb =
          int.tryParse(b['coin_price']?.toString() ?? '0') ?? 0;
      return pb.compareTo(pa);
    });
    return list;
  }

  Widget _buildGiftsSection(List<Map<String, dynamic>> gifts) {
    final grouped = _groupGifts(gifts);
    if (grouped.isEmpty) {
      return _buildEmpty(Icons.card_giftcard_rounded, 'No gifts yet');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: grouped.length,
      itemBuilder: (_, i) => _buildGiftPileItem(grouped[i]),
    );
  }

  Widget _buildGiftPileItem(Map<String, dynamic> gift) {
    final coinPrice =
        int.tryParse(gift['coin_price']?.toString() ?? '0') ?? 0;
    final qty = int.tryParse(gift['qty']?.toString() ?? '0') ?? 0;
    final glowColor = _giftRarityGlow(coinPrice);
    final bgColor = _giftRarityBg(coinPrice);
    final thumb =
        (gift['gif_url'] ?? gift['thumb_image'] ?? '').toString().trim();
    final name =
        (gift['name'] ?? gift['gift_name'] ?? '').toString();
    final emoji = (gift['emoji'] ?? '🎁').toString().trim();

    Widget card = Stack(
      children: [
        if (qty > 2)
          Positioned(
            bottom: 0, left: 8, right: 8, top: 10,
            child: _buildPileLayer(bgColor, glowColor, 0.35),
          ),
        if (qty > 1)
          Positioned(
            bottom: 0, left: 4, right: 4, top: 5,
            child: _buildPileLayer(bgColor, glowColor, 0.6),
          ),
        _buildGiftCard(thumb, emoji, name, qty, bgColor, glowColor),
      ],
    );

    if (!widget.isOwnProfile) return card;

    return GestureDetector(
      onLongPress: () =>
          _showSellDialog(context, gift, name, emoji, thumb, coinPrice, qty),
      child: card,
    );
  }

  Widget _buildPileLayer(Color bg, Color glow, double opacity) {
    return Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: glow.withValues(alpha: opacity * 0.5),
          width: 1,
        ),
      ),
    );
  }

  Widget _buildGiftCard(
    String thumb, String emoji, String name, int qty,
    Color bgColor, Color glowColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: glowColor.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: glowColor.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Stack(
        children: [
          // Gift image / emoji
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 24),
              child: thumb.isNotEmpty && thumb.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(emoji,
                            style: const TextStyle(fontSize: 28),
                            textAlign: TextAlign.center),
                      ),
                    )
                  : Center(
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 28),
                          textAlign: TextAlign.center),
                    ),
            ),
          ),
          // Name
          Positioned(
            bottom: 6, left: 5, right: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Qty badge
          if (qty > 0)
            Positioned(
              top: 5, right: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: glowColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '×$qty',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          // Bottom glow bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                gradient: LinearGradient(
                  colors: [
                    glowColor.withValues(alpha: 0.0),
                    glowColor.withValues(alpha: 0.7),
                    glowColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSellDialog(
    BuildContext context,
    Map<String, dynamic> gift,
    String name,
    String emoji,
    String thumb,
    int coinPrice,
    int qty,
  ) {
    if (qty <= 0) return;
    int selectedQty = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final earn = selectedQty * coinPrice;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Sell $name',
                style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: thumb.isNotEmpty && thumb.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => Center(
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 40)),
                          ))
                      : Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 12),
                Text('You own $qty',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: selectedQty > 1
                          ? () => setDialogState(() => selectedQty--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text('$selectedQty',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: selectedQty < qty
                          ? () => setDialogState(() => selectedQty++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Earn $earn',
                        style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(width: 4),
                    const CoinIcon(size: 18, color: Color(0xFF22C55E)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selectedQty),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E)),
                child: const Text('Sell Now'),
              ),
            ],
          );
        },
      ),
    ).then((sellQty) async {
      if (sellQty == null || sellQty <= 0) return;
      final giftId = gift['gift_id'] ?? gift['id'];
      if (giftId == null) return;
      final result = await ApiService()
          .sellWalletGift(giftId: giftId, qty: sellQty as int);
      if (!context.mounted) return;
      final ok =
          result['status'] == true || result['status'] == 'success';
      if (ok) {
        NeonToast.success(context, 'Sold ×$sellQty $name!');
        widget.onGiftSold?.call();
      } else {
        NeonToast.error(
            context, result['message']?.toString() ?? 'Failed to sell');
      }
    });
  }

  static Color _giftRarityGlow(int coinPrice) {
    if (coinPrice >= 1000) return const Color(0xFFFFD700);
    if (coinPrice >= 200) return const Color(0xFFBF5AF2);
    if (coinPrice >= 50) return const Color(0xFF0A84FF);
    return const Color(0xFF8E8E93);
  }

  static Color _giftRarityBg(int coinPrice) {
    if (coinPrice >= 1000) return const Color(0xFF2A2000);
    if (coinPrice >= 200) return const Color(0xFF1E0A2E);
    if (coinPrice >= 50) return const Color(0xFF001228);
    return const Color(0xFF1C1C1E);
  }

  // ─────────────────────────── HELPERS ──────────────────────────

  /// View count badge: shows total views and unique views side by side
  Widget _viewBadge(int total, {int uniqueViews = 0, bool small = true}) {
    final displayTotal = _formatViews(total);
    final displayUnique = _formatViews(uniqueViews);
    final fontSize = small ? 9.0 : 10.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        uniqueViews > 0
            ? '$displayUnique Views'
            : (total > 0 ? '$displayTotal Views' : '0 Views'),
        style: TextStyle(color: Colors.white70, fontSize: fontSize),
      ),
    );
  }

  Widget _buildEmpty(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}

// ─────────────────────────── REEL GRID ITEM ───────────────────────────────

class _ReelGridItem extends StatefulWidget {
  final UserPost post;
  final VoidCallback? onTap;
  final Widget Function(int total, int unique) viewBadgeBuilder;

  const _ReelGridItem({
    required this.post,
    required this.viewBadgeBuilder,
    this.onTap,
  });

  @override
  State<_ReelGridItem> createState() => _ReelGridItemState();
}

class _ReelGridItemState extends State<_ReelGridItem> {
  Uint8List? _generatedThumb;
  bool _thumbRequested = false;

  String get _thumbUrl {
    final t = (widget.post.thumbnailUrl ?? '').trim();
    return t.isNotEmpty && t.startsWith('http') ? t : '';
  }

  @override
  void initState() {
    super.initState();
    if (_thumbUrl.isEmpty) {
      // Check if already preloaded (instant)
      _generatedThumb = ThumbnailCache.instance.get(widget.post.mediaUrl);
      if (_generatedThumb == null) _fetchThumb();
    }
  }

  Future<void> _fetchThumb() async {
    if (_thumbRequested) return;
    final url = widget.post.mediaUrl;
    if (url.isEmpty || !url.startsWith('http')) return;
    _thumbRequested = true;
    final bytes = await ThumbnailCache.instance.fetch(url);
    if (mounted && bytes != null) setState(() => _generatedThumb = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media layer: stored thumbnail > preloaded bytes > placeholder
              if (_thumbUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: _thumbUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 300,
                  errorWidget: (_, __, ___) => _placeholder(),
                )
              else if (_generatedThumb != null)
                Image.memory(
                  _generatedThumb!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                _placeholder(),
              // Dark gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
              // Play icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 24),
                ),
              ),
              // Bottom meta row
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    widget.viewBadgeBuilder(
                        widget.post.viewsTotal, widget.post.viewsUnique),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.post.type == PostType.reel ? 'Reel' : 'Video',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: const Icon(Icons.videocam, color: Colors.white24, size: 32),
    );
  }
}
