import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class ProfileGiftsShelf extends StatelessWidget {
  final List<Map<String, dynamic>> gifts;
  final bool isOwnProfile;
  final VoidCallback? onSold;

  const ProfileGiftsShelf({
    super.key,
    required this.gifts,
    required this.isOwnProfile,
    this.onSold,
  });

  static Color _rarityGlow(int coinPrice) {
    if (coinPrice >= 1000) return const Color(0xFFFFD700);
    if (coinPrice >= 200)  return const Color(0xFFBF5AF2);
    if (coinPrice >= 50)   return const Color(0xFF0A84FF);
    return const Color(0xFF8E8E93);
  }

  static Color _rarityBg(int coinPrice) {
    if (coinPrice >= 1000) return const Color(0xFF2A2000);
    if (coinPrice >= 200)  return const Color(0xFF1E0A2E);
    if (coinPrice >= 50)   return const Color(0xFF001228);
    return const Color(0xFF1C1C1E);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '✨ Gifts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              if (gifts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${gifts.length}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (gifts.isEmpty)
            _buildEmpty()
          else
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: gifts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _GiftCard(
                  gift: gifts[i],
                  isOwnProfile: isOwnProfile,
                  onSold: onSold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              isOwnProfile ? 'No gifts yet — keep streaming!' : 'No gifts yet',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftCard extends StatelessWidget {
  final Map<String, dynamic> gift;
  final bool isOwnProfile;
  final VoidCallback? onSold;

  const _GiftCard({required this.gift, required this.isOwnProfile, this.onSold});

  @override
  Widget build(BuildContext context) {
    final coinPrice = int.tryParse(gift['coin_price']?.toString() ?? '0') ?? 0;
    final qty       = int.tryParse(gift['qty']?.toString() ?? '0') ?? 0;
    final name      = (gift['name'] ?? gift['gift_name'] ?? '').toString();
    final thumb     = (gift['gif_url'] ?? gift['thumb_image'] ?? '').toString().trim();
    final emoji     = (gift['emoji'] ?? '🎁').toString().trim();
    final glowColor = ProfileGiftsShelf._rarityGlow(coinPrice);
    final bgColor   = ProfileGiftsShelf._rarityBg(coinPrice);

    return GestureDetector(
      onLongPress: isOwnProfile ? () => _showSellDialog(context, name, emoji, thumb, coinPrice, qty) : null,
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: glowColor.withValues(alpha: 0.35), width: 1),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.18),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                        child: thumb.isNotEmpty && thumb.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => _emojiOrIcon(emoji),
                              )
                            : _emojiOrIcon(emoji),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Quantity badge
            if (qty > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: glowColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '×$qty',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

            // Long-press hint for own profile
            if (isOwnProfile)
              Positioned(
                bottom: 22,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'hold to sell',
                      style: TextStyle(color: Colors.white54, fontSize: 7),
                    ),
                  ),
                ),
              ),

            // Rarity bottom glow
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
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
      ),
    );
  }

  Widget _emojiOrIcon(String emoji) {
    if (emoji.isNotEmpty && emoji != '🎁' || emoji == '🎁') {
      return FittedBox(
        fit: BoxFit.contain,
        child: Text(emoji, style: const TextStyle(fontSize: 32)),
      );
    }
    return const Icon(Icons.card_giftcard_rounded, color: Colors.white38, size: 32);
  }

  void _showSellDialog(BuildContext context, String name, String emoji,
      String thumb, int coinPrice, int qty) {
    if (qty <= 0) return;
    int selectedQty = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final earn = selectedQty * coinPrice;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Sell $name', style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gift visual
                SizedBox(
                  width: 72,
                  height: 72,
                  child: thumb.isNotEmpty && thumb.startsWith('http')
                      ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => Center(
                            child: Text(emoji, style: const TextStyle(fontSize: 40)),
                          ))
                      : Center(child: Text(emoji, style: const TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 12),
                Text('You own $qty', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: selectedQty > 1
                          ? () => setDialogState(() => selectedQty--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text('$selectedQty',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: selectedQty < qty
                          ? () => setDialogState(() => selectedQty++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Earn $earn',
                        style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(width: 4),
                    const CoinIcon(size: 18, color: Color(0xFF22C55E)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selectedQty),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                child: const Text('Sell Now'),
              ),
            ],
          );
        },
      ),
    ).then((qty) async {
      if (qty == null || qty <= 0) return;
      final giftId = gift['gift_id'];
      if (giftId == null) return;
      final result = await ApiService().sellWalletGift(giftId: giftId, qty: qty as int);
      if (!context.mounted) return;
      final success = result['status'] == true || result['status'] == 'success';
      if (success) {
        NeonToast.success(context, 'Sold ×$qty $name!');
        onSold?.call();
      } else {
        NeonToast.error(context, result['message']?.toString() ?? 'Failed to sell');
      }
    });
  }
}
