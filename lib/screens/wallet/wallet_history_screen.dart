import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class WalletHistoryScreen extends StatefulWidget {
  const WalletHistoryScreen({super.key});

  @override
  State<WalletHistoryScreen> createState() => _WalletHistoryScreenState();
}

class _WalletHistoryScreenState extends State<WalletHistoryScreen> {
  final WalletService _walletService = WalletService();

  bool _isLoading = true;
  List<WalletTransaction> _transactions = <WalletTransaction>[];

  @override
  void initState() {
    super.initState();
    _walletService.getCachedTransactions().then((cached) {
      if (cached.isNotEmpty && mounted && _transactions.isEmpty) {
        setState(() { _transactions = cached; _isLoading = false; });
      }
    });
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (_transactions.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final list = await _walletService.getMergedTransactions(limit: 200);
      if (!mounted) return;
      setState(() => _transactions = list);
    } catch (_) {
      if (!mounted) return;
      NeonToast.error(context, 'Wallet API error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTransactions,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _transactions.isEmpty
                  ? ListView.builder(
                      itemCount: 2,
                      itemBuilder: (context, index) {
                        if (index == 0) return const SizedBox(height: 140);
                        return const Center(
                          child: Text(
                            'No transactions found',
                            style: TextStyle(color: Colors.white60),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _transactions.length,
                      itemBuilder: (context, index) {
                        return _txTile(_transactions[index]);
                      },
                    ),
        ),
      ),
    );
  }

  Widget _txTile(WalletTransaction tx) {
    final color = _statusColor(tx.status);
    final amountWidget = _formatAmount(tx, color);
    final timeText = tx.createdAt == null
        ? 'Unknown time'
        : DateFormat('MMM d, yyyy • h:mm a').format(tx.createdAt!.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(tx.type), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleFromType(tx.type),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeText,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (tx.note.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      tx.note,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              amountWidget,
              if ((tx.rejectReason ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tx.rejectReason!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              const SizedBox(height: 3),
              _statusBadge(tx.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _statusColor(String statusRaw) {
    final status = statusRaw.toLowerCase();
    if (status.contains('approved') || status.contains('completed')) {
      return const Color(0xFF22C55E);
    }
    if (status.contains('review') || status.contains('pending')) {
      return const Color(0xFFF59E0B);
    }
    if (status.contains('reject') || status.contains('failed')) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFF06B6D4);
  }

  IconData _typeIcon(String typeRaw) {
    final type = typeRaw.toLowerCase();
    if (type.contains('deposit')) return Icons.south_west;
    if (type.contains('withdraw')) return Icons.north_east;
    if (type.contains('referral')) return Icons.people_alt_outlined;
    if (type.contains('gift')) return Icons.card_giftcard;
    return Icons.receipt_long_outlined;
  }

  String _titleFromType(String typeRaw) {
    final type = typeRaw.toLowerCase();
    if (type.contains('deposit')) return 'Deposit';
    if (type.contains('withdraw')) return 'Withdraw';
    if (type.contains('referral')) return 'Referral Bonus';
    if (type.contains('gift')) return 'Gift';
    return toBeginningOfSentenceCase(typeRaw.replaceAll('_', ' ')) ??
        'Transaction';
  }

  Widget _formatAmount(WalletTransaction tx, Color color) {
    final type = tx.type.toLowerCase();
    final debit =
        tx.direction.toLowerCase() == 'debit' || type.contains('withdraw');
    final sign = debit ? '-' : '+';

    if (tx.currencyAmount != null) {
      return Text(
        '$sign${tx.currencyAmount!.abs().toStringAsFixed(2)} ${tx.currencyCode}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$sign${tx.coins.abs()}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        CoinIcon(size: 14, color: color),
      ],
    );
  }
}
