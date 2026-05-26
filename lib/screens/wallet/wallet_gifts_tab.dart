import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/wallet_gift_item.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class WalletGiftsTab extends StatefulWidget {
  final VoidCallback onBalanceUpdated;

  const WalletGiftsTab({super.key, required this.onBalanceUpdated});

  @override
  State<WalletGiftsTab> createState() => _WalletGiftsTabState();
}

class _WalletGiftsTabState extends State<WalletGiftsTab> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<WalletGiftItem> _gifts = [];

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final gifts = await _apiService.fetchWalletGifts();
      if (mounted) {
        setState(() {
          _gifts = gifts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Failed to load gifts');
      }
    }
  }

  Future<void> _showSellDialog(WalletGiftItem gift) async {
    int selectedQty = 1;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int earnedCoins = selectedQty * gift.sellPrice;

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Sell ${gift.name}',
                style: const TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: gift.thumbImage.isNotEmpty && gift.thumbImage.startsWith('http')
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              gift.thumbImage,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(gift.emoji, style: const TextStyle(fontSize: 44)),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(gift.emoji, style: const TextStyle(fontSize: 44)),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You own ${gift.qty} items',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: selectedQty > 1
                            ? () => setDialogState(() => selectedQty--)
                            : null,
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        selectedQty.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: selectedQty < gift.qty
                            ? () => setDialogState(() => selectedQty++)
                            : null,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Receive $earnedCoins',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const CoinIcon(size: 18, color: Color(0xFF22C55E)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                  ),
                  child: const Text('Sell Now'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await _processSale(gift, selectedQty);
    }
  }

  Future<void> _processSale(WalletGiftItem gift, int qty) async {
    if (!mounted) return;
    NeonToast.info(context, 'Selling ${gift.name}...');

    final response = await _apiService.sellWalletGift(
      giftId: gift.giftId,
      qty: qty,
    );

    if (!mounted) return;

    final bool success =
        response['status'] == true || response['status'] == 'success';
    if (success) {
      final coinsAdded = response['coins_added'] ?? (qty * gift.sellPrice);
      NeonToast.success(context, 'Sold $qty gift(s) +$coinsAdded coins');
      widget.onBalanceUpdated();
      _loadGifts();
    } else {
      NeonToast.error(
        context,
        response['message']?.toString() ?? 'Failed to sell gift',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFF97316)),
        ),
      );
    }

    if (_gifts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(
              Icons.card_giftcard,
              size: 60,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No gifts received yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _gifts.length,
      itemBuilder: (context, index) {
        final gift = _gifts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: gift.thumbImage.isNotEmpty && gift.thumbImage.startsWith('http')
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          gift.thumbImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(gift.emoji, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(gift.emoji, style: const TextStyle(fontSize: 28)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (gift.senderName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'From: ${gift.senderName}',
                        style: const TextStyle(
                          color: Color(0xFF06B6D4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Qty: ${gift.qty}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'Value: ${gift.totalValue}',
                          style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const CoinIcon(size: 12, color: Color(0xFF22C55E)),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: gift.qty > 0 ? () => _showSellDialog(gift) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  minimumSize: const Size(70, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Sell',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
