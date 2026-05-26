import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/gift_sent_overlay.dart';
import 'package:love_vibe_pro/screens/settings/wallet_screen.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class GiftsSheet extends StatefulWidget {
  final String toUserId;
  final String contextType;
  final dynamic contextId;
  final bool liveMode;
  final Function(String name, int coins, String gifUrl, String emoji)? onGiftSent;

  const GiftsSheet({
    super.key,
    required this.toUserId,
    required this.contextType,
    required this.contextId,
    this.liveMode = false,
    this.onGiftSent,
  });

  static Future<void> show({
    required BuildContext context,
    required String toUserId,
    required String contextType,
    required dynamic contextId,
    bool liveMode = false,
    Function(String name, int coins, String gifUrl, String emoji)? onGiftSent,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GiftsSheet(
        toUserId: toUserId,
        contextType: contextType,
        contextId: contextId,
        liveMode: liveMode,
        onGiftSent: onGiftSent,
      ),
    );
  }

  @override
  State<GiftsSheet> createState() => _GiftsSheetState();
}

class _GiftsSheetState extends State<GiftsSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _msgController = TextEditingController();

  List<Map<String, dynamic>> _gifts = [];
  bool _loading = true;
  bool _sending = false;
  int? _selectedIndex;
  String _selectedCategory = 'all';
  String _sortMode = 'price_asc';
  int _coinBalance = 0;

  static const _categories = [
    {'key': 'all',    'label': 'All',    'emoji': '🎁'},
    {'key': 'love',   'label': 'Love',   'emoji': '💖'},
    {'key': 'vibe',   'label': 'Vibe',   'emoji': '🔥'},
    {'key': 'luxury', 'label': 'Luxury', 'emoji': '💎'},
    {'key': 'cute',   'label': 'Cute',   'emoji': '🐰'},
    {'key': 'funny',  'label': 'Funny',  'emoji': '😂'},
    {'key': 'legend', 'label': 'Legend', 'emoji': '👑'},
  ];

  static const _sortOptions = [
    {'key': 'price_asc',  'label': 'Price: Low → High', 'icon': Icons.arrow_upward},
    {'key': 'price_desc', 'label': 'Price: High → Low', 'icon': Icons.arrow_downward},
    {'key': 'name_asc',   'label': 'Name: A → Z',       'icon': Icons.sort_by_alpha},
  ];

  @override
  void initState() {
    super.initState();
    _fetchGifts();
    _fetchBalance();
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _fetchGifts() async {
    try {
      final gifts = await _api.getGifts();
      if (!mounted) return;
      setState(() { _gifts = gifts; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchBalance() async {
    try {
      final info = await _api.getWalletBalanceRemote();
      if (mounted) setState(() => _coinBalance = info.coins);
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filteredGifts {
    final list = _selectedCategory == 'all'
        ? List<Map<String, dynamic>>.of(_gifts)
        : _gifts.where((g) => (g['category'] ?? '').toString() == _selectedCategory).toList();

    switch (_sortMode) {
      case 'price_desc':
        list.sort((a, b) => _price(b).compareTo(_price(a)));
      case 'name_asc':
        list.sort((a, b) => _name(a).compareTo(_name(b)));
      default:
        list.sort((a, b) => _price(a).compareTo(_price(b)));
    }
    return list;
  }

  String _imgUrl(Map<String, dynamic> g) =>
      (g['gif_url'] ?? g['thumb_image'] ?? g['image'] ?? '').toString();

  String _name(Map<String, dynamic> g) =>
      (g['name'] ?? g['title'] ?? 'Gift').toString();

  int _price(Map<String, dynamic> g) =>
      int.tryParse((g['coin_price'] ?? g['price'] ?? 0).toString()) ?? 0;

  String _id(Map<String, dynamic> g) =>
      (g['id'] ?? g['gift_id'] ?? '').toString();

  String _emoji(Map<String, dynamic> g) =>
      (g['emoji'] ?? '').toString();

  bool _isLegendary(Map<String, dynamic> g) => _price(g) >= 50000;
  bool _isVip(Map<String, dynamic> g)       => _price(g) >= 20000 && !_isLegendary(g);
  bool _isPremium(Map<String, dynamic> g)   => _price(g) >= 8000  && !_isVip(g) && !_isLegendary(g);

  // ── Tap ────────────────────────────────────────────────────────────
  void _onGiftTap(int index) {
    HapticFeedback.lightImpact();
    if (widget.liveMode) {
      setState(() => _selectedIndex = index);
    } else {
      // Show full preview dialog with send option
      _showPreviewDialog(_filteredGifts[index]);
    }
  }

  void _showPreviewDialog(Map<String, dynamic> g) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _GiftPreviewDialog(
        imageUrl: _imgUrl(g),
        emoji: _emoji(g),
        name: _name(g),
        price: _price(g),
        isLegendary: _isLegendary(g),
        isVip: _isVip(g),
        onSend: () { Navigator.pop(ctx); _sendGift(g); },
      ),
    );
  }

  // ── Sort sheet ─────────────────────────────────────────────────────
  void _showSortSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: SizedBox(
                width: 40, height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Sort Gifts',
                style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ..._sortOptions.map((opt) {
              final isActive = _sortMode == opt['key'];
              return GestureDetector(
                onTap: () {
                  setState(() => _sortMode = opt['key'] as String);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFFF2D55).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFFFF2D55).withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(opt['icon'] as IconData,
                          color: isActive
                              ? const Color(0xFFFF2D55)
                              : Colors.white38,
                          size: 18),
                      const SizedBox(width: 12),
                      Text(opt['label'] as String,
                          style: TextStyle(
                              color: isActive ? Colors.white : Colors.white60,
                              fontSize: 14,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      const Spacer(),
                      if (isActive)
                        const Icon(Icons.check_circle,
                            color: Color(0xFFFF2D55), size: 18),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Send ───────────────────────────────────────────────────────────
  Future<void> _sendGift(Map<String, dynamic> g) async {
    if (_sending) return;
    setState(() => _sending = true);

    final result = await _api.sendGift(
      giftId: _id(g),
      toUserId: widget.toUserId,
      contextType: widget.contextType,
      contextId: widget.contextId,
      message: widget.liveMode ? '' : _msgController.text,
    );
    if (!mounted) return;

    final msg = (result['message'] ?? '').toString();
    final success = result['status'] == 'success' ||
        result['status'] == 'ok' ||
        result['status'] == true ||
        result['status'] == 1 ||
        result['success'] == true ||
        result['success'] == 1 ||
        msg.toLowerCase().contains('sent') ||
        msg.toLowerCase().contains('success');

    if (success) {
      final newBal = result['new_balance'] ?? result['balance_coins'];
      if (newBal != null) {
        setState(() => _coinBalance = int.tryParse(newBal.toString()) ?? _coinBalance);
      } else {
        _fetchBalance();
      }

      widget.onGiftSent?.call(_name(g), _price(g), _imgUrl(g), _emoji(g));
      if (mounted) {
        Navigator.pop(context);
        GiftSentOverlay.show(
          context,
          giftImageUrl: _imgUrl(g),
          giftName: _name(g),
          emoji: _emoji(g),
          coins: _price(g),
        );
      }
    } else {
      final isLow = msg.toLowerCase().contains('not enough') ||
          msg.toLowerCase().contains('insufficient');
      if (isLow) {
        NeonToast.error(context, 'Not Enough Coins');
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WalletScreen()));
        }
      } else {
        NeonToast.error(context, msg.isNotEmpty ? msg : 'Failed to send gift');
      }
    }

    if (mounted) setState(() => _sending = false);
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.liveMode ? 0.65 : 0.55,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D18),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              const SizedBox(
                width: 48, height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildHeader(),
              const SizedBox(height: 12),
              _buildCategoryTabs(),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(scrollController)),
              if (_selectedIndex != null) _buildSendBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text(
            '🎁  Send a Gift',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          // Sort button
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12), width: 1),
              ),
              child: Row(children: [
                const Icon(Icons.sort, color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Text(
                  _sortOptions
                      .firstWhere((o) => o['key'] == _sortMode,
                          orElse: () => _sortOptions[0])['label']!
                      .toString()
                      .split(':')
                      .last
                      .trim(),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ]),
            ),
          ),
          // Coin balance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(children: [
              const CoinIcon(size: 14, color: Colors.amber),
              const SizedBox(width: 5),
              Text(
                _fmtCoins(_coinBalance),
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _fmtCoins(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(1)}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return '$n';
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final isActive = _selectedCategory == cat['key'];
          final isLegend = cat['key'] == 'legend';
          return GestureDetector(
            onTap: () => setState(() {
              _selectedCategory = cat['key']!;
              _selectedIndex = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: isActive
                    ? (isLegend
                        ? const LinearGradient(colors: [
                            Color(0xFFFFD700), Color(0xFFFF6B00), Color(0xFFFF007F)
                          ])
                        : const LinearGradient(
                            colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]))
                    : null,
                color: isActive ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                border: Border.all(
                  color: isActive
                      ? Colors.transparent
                      : isLegend
                          ? const Color(0xFFFFD700).withValues(alpha: 0.30)
                          : Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: isActive && isLegend
                    ? [
                        BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 3))
                      ]
                    : isActive
                        ? [
                            BoxShadow(
                                color: const Color(0xFFFF2D55).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3))
                          ]
                        : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cat['emoji']!, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(cat['label']!,
                      style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(ScrollController sc) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD946EF)));
    }
    final list = _filteredGifts;
    if (list.isEmpty) {
      return const Center(
          child: Text('No gifts available',
              style: TextStyle(color: Colors.white38, fontSize: 14)));
    }
    return GridView.builder(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildCell(list[i], i),
    );
  }

  Widget _buildCell(Map<String, dynamic> g, int index) {
    final isSelected = _selectedIndex == index;
    final isLegendary = _isLegendary(g);
    final isVip = _isVip(g);
    final isPremium = _isPremium(g);
    final url = _imgUrl(g);
    final emoji = _emoji(g);
    final price = _price(g);

    final tierColor = isLegendary
        ? const Color(0xFFFFD700)
        : isVip
            ? const Color(0xFFFF6B00)
            : isPremium
                ? const Color(0xFFBF5AF2)
                : null;

    Widget cell = GestureDetector(
      onTap: () => _onGiftTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFF2D55).withValues(alpha: 0.20),
                    const Color(0xFFBF5AF2).withValues(alpha: 0.15),
                  ],
                )
              : isLegendary
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1A1200).withValues(alpha: 0.95),
                        const Color(0xFF120A1E).withValues(alpha: 0.95),
                      ],
                    )
                  : null,
          color: isSelected || isLegendary
              ? null
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: isLegendary
              ? null
              : Border.all(
                  color: isSelected
                      ? const Color(0xFFFF2D55).withValues(alpha: 0.80)
                      : tierColor?.withValues(alpha: 0.45) ??
                          Colors.white.withValues(alpha: 0.10),
                  width: isSelected ? 1.8 : 1,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: const Color(0xFFFF2D55).withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 1)
                ]
              : isLegendary
                  ? [
                      BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.30),
                          blurRadius: 16,
                          spreadRadius: 2),
                      BoxShadow(
                          color: const Color(0xFFFF6B00).withValues(alpha: 0.20),
                          blurRadius: 24,
                          spreadRadius: 0),
                    ]
                  : tierColor != null
                      ? [
                          BoxShadow(
                              color: tierColor.withValues(alpha: 0.20),
                              blurRadius: 8)
                        ]
                      : null,
        ),
        child: Stack(
          children: [
            // Tier badge
            if (isLegendary)
              Positioned(
                top: 5, right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF6B00)]),
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: const Text('👑',
                      style: TextStyle(fontSize: 8)),
                ),
              )
            else if (isVip)
              Positioned(
                top: 5, right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.20),
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    border: Border.all(
                        color: const Color(0xFFFF6B00).withValues(alpha: 0.5),
                        width: 0.8),
                  ),
                  child: const Text('VIP',
                      style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5)),
                ),
              )
            else if (isPremium)
              Positioned(
                top: 5, right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBF5AF2).withValues(alpha: 0.20),
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                  ),
                  child: const Text('💜',
                      style: TextStyle(fontSize: 8)),
                ),
              ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _FloatingGiftIcon(
                      phaseOffset: index * 0.37,
                      child: url.isNotEmpty && url.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const Center(
                                child: SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFD946EF)),
                                ),
                              ),
                              errorWidget: (_, __, ___) => _emojiOrIcon(emoji),
                            )
                          : _emojiOrIcon(emoji),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    _name(g),
                    style: TextStyle(
                        color: isLegendary
                            ? const Color(0xFFFFD700)
                            : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CoinIcon(
                          size: 11,
                          color: isLegendary
                              ? const Color(0xFFFFD700)
                              : isVip
                                  ? const Color(0xFFFF6B00)
                                  : isPremium
                                      ? const Color(0xFFBF5AF2)
                                      : Colors.amber),
                      const SizedBox(width: 3),
                      Text(
                        _fmtCoins(price),
                        style: TextStyle(
                          color: isLegendary
                              ? const Color(0xFFFFD700)
                              : isVip
                                  ? const Color(0xFFFF6B00)
                                  : isPremium
                                      ? const Color(0xFFBF5AF2)
                                      : Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Wrap legendary gifts in animated rainbow border
    if (isLegendary) {
      cell = _AnimatedRainbowBorder(child: cell);
    }
    return cell;
  }

  Widget _emojiOrIcon(String emoji) {
    if (emoji.isNotEmpty) {
      return Center(
          child: Text(emoji,
              style: const TextStyle(fontSize: 30),
              textAlign: TextAlign.center));
    }
    return const Icon(Icons.card_giftcard_rounded, color: Colors.white24, size: 28);
  }

  Widget _buildSendBar() {
    final g = _filteredGifts[_selectedIndex!];
    final name = _name(g);
    final price = _price(g);
    final isLegendary = _isLegendary(g);
    final isVip = _isVip(g);
    final isPremium = _isPremium(g);
    final tierColor = isLegendary
        ? const Color(0xFFFFD700)
        : isVip
            ? const Color(0xFFFF6B00)
            : isPremium
                ? const Color(0xFFBF5AF2)
                : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D18),
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.liveMode)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: TextField(
                  controller: _msgController,
                  maxLength: 30,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add a message (optional)',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.28),
                        fontSize: 13),
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          border: Border.all(
                              color: tierColor?.withValues(alpha: 0.4) ??
                                  Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Center(
                          child: Text(
                            _emoji(g).isNotEmpty ? _emoji(g) : '🎁',
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          const SizedBox(height: 2),
                          Row(children: [
                            CoinIcon(
                                size: 13,
                                color: tierColor ?? Colors.amber),
                            const SizedBox(width: 4),
                            Text(_fmtCoins(price),
                                style: TextStyle(
                                    color: tierColor ?? Colors.amber,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800)),
                            if (_coinBalance > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '/ ${_fmtCoins(_coinBalance)} balance',
                                style: const TextStyle(
                                    color: Colors.white30, fontSize: 10),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),

                GestureDetector(
                  onTap: _sending ? null : () => _sendGift(g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 13),
                    decoration: BoxDecoration(
                      gradient: _sending
                          ? null
                          : isLegendary
                              ? const LinearGradient(
                                  colors: [Color(0xFFFFD700), Color(0xFFFF6B00)])
                              : const LinearGradient(
                                  colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]),
                      color: _sending ? Colors.white12 : null,
                      borderRadius: const BorderRadius.all(Radius.circular(24)),
                      boxShadow: _sending
                          ? null
                          : [
                              BoxShadow(
                                  color: (isLegendary
                                          ? const Color(0xFFFFD700)
                                          : const Color(0xFFFF2D55))
                                      .withValues(alpha: 0.40),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4))
                            ],
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Send',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full preview dialog ────────────────────────────────────────────────────────
class _GiftPreviewDialog extends StatelessWidget {
  final String imageUrl;
  final String emoji;
  final String name;
  final int price;
  final bool isLegendary;
  final bool isVip;
  final VoidCallback onSend;

  const _GiftPreviewDialog({
    required this.imageUrl,
    required this.emoji,
    required this.name,
    required this.price,
    required this.onSend,
    this.isLegendary = false,
    this.isVip = false,
  });

  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isLegendary
        ? const Color(0xFFFFD700)
        : isVip
            ? const Color(0xFFFF6B00)
            : const Color(0xFFD946EF);

    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          border: Border.all(color: accentColor.withValues(alpha: 0.40)),
          boxShadow: [
            BoxShadow(
                color: accentColor.withValues(alpha: 0.18),
                blurRadius: 40,
                spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tier label
            if (isLegendary)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF6B00)]),
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                child: const Text('👑  LEGENDARY GIFT',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              )
            else if (isVip)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.all(
                      color: const Color(0xFFFF6B00).withValues(alpha: 0.5)),
                ),
                child: const Text('⭐  VIP GIFT',
                    style: TextStyle(
                        color: Color(0xFFFF6B00),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ),

            // Gift visual
            Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(
                    color: accentColor.withValues(alpha: 0.45), width: 2),
              ),
              child: Center(
                child: imageUrl.isNotEmpty && imageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 110, height: 110,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => Text(
                            emoji.isNotEmpty ? emoji : '🎁',
                            style: const TextStyle(fontSize: 64)))
                    : Text(emoji.isNotEmpty ? emoji : '🎁',
                        style: const TextStyle(fontSize: 64)),
              ),
            ),
            const SizedBox(height: 16),

            Text(name,
                style: TextStyle(
                    color: isLegendary
                        ? const Color(0xFFFFD700)
                        : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),

            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              CoinIcon(size: 18, color: accentColor),
              const SizedBox(width: 6),
              Text(_fmt(price),
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 22),

            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: const BoxDecoration(
                        color: Color(0x14FFFFFF),
                        borderRadius: BorderRadius.all(Radius.circular(14))),
                    child: const Text('Close',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white60, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onSend,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: isLegendary
                          ? const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF6B00)])
                          : const LinearGradient(
                              colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]),
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      boxShadow: [
                        BoxShadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: const Text('Send Gift',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Animated rainbow border for legendary gifts ───────────────────────────────
class _AnimatedRainbowBorder extends StatefulWidget {
  final Widget child;
  const _AnimatedRainbowBorder({required this.child});

  @override
  State<_AnimatedRainbowBorder> createState() => _AnimatedRainbowBorderState();
}

class _AnimatedRainbowBorderState extends State<_AnimatedRainbowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
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
      builder: (_, child) => CustomPaint(
        foregroundPainter: _RainbowBorderPainter(progress: _ctrl.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _RainbowBorderPainter extends CustomPainter {
  final double progress;

  _RainbowBorderPainter({required this.progress});

  static const _colors = [
    Color(0xFFFF0080),
    Color(0xFFFF6B00),
    Color(0xFFFFD700),
    Color(0xFF00FF88),
    Color(0xFF00DDFF),
    Color(0xFF7B61FF),
    Color(0xFFFF0080),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final rotate = GradientRotation(progress * 2 * math.pi);

    final paint = Paint()
      ..shader = SweepGradient(colors: _colors, transform: rotate).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawRRect(rrect, paint);

    final glowPaint = Paint()
      ..shader = SweepGradient(
        colors: _colors.map((c) => c.withValues(alpha: 0.4)).toList(),
        transform: rotate,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawRRect(rrect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RainbowBorderPainter old) =>
      old.progress != progress;
}

// ── Floating animation ────────────────────────────────────────────────────────
class _FloatingGiftIcon extends StatefulWidget {
  final Widget child;
  final double phaseOffset;

  const _FloatingGiftIcon({required this.child, this.phaseOffset = 0});

  @override
  State<_FloatingGiftIcon> createState() => _FloatingGiftIconState();
}

class _FloatingGiftIconState extends State<_FloatingGiftIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _float = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (_, child) {
        final dy = math.sin(
              (_float.value + widget.phaseOffset) * 2 * math.pi,
            ) *
            3.5;
        final scale = 1.0 +
            math.sin((_float.value + widget.phaseOffset) * 2 * math.pi) * 0.03;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}
