import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/services/subscription_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _isLoading = true;
  List<SubscriptionItem> _items = <SubscriptionItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final items = await _subscriptionService.getSubscriptions();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      NeonToast.error(context, 'Wallet API error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelSubscription(SubscriptionItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Cancel Subscription',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Do you want to cancel subscription for ${item.modelName}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await _subscriptionService.cancelSubscription(
      subscriptionId: item.id,
    );

    if (!mounted) return;
    NeonToast.info(context, result.message);

    if (result.endpointUnavailable) {
      NeonToast.error(
        context,
        'Backend cancel endpoint not ready (TODO handler).',
      );
      return;
    }

    if (result.success) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Subscriptions'),
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? ListView.builder(
                      itemCount: 2,
                      itemBuilder: (context, index) {
                        if (index == 0) return const SizedBox(height: 140);
                        return const Center(
                          child: Text(
                            'No active subscriptions',
                            style: TextStyle(color: Colors.white60),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _items.length,
                      itemBuilder: (context, index) => _itemCard(_items[index]),
                    ),
        ),
      ),
    );
  }

  Widget _itemCard(SubscriptionItem item) {
    final status = item.status.toLowerCase();
    final statusColor = _statusColor(status);

    String formatDate(DateTime? date) {
      if (date == null) return '—';
      return DateFormat('MMM d, yyyy').format(date.toLocal());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.modelName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  item.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.planName,
            style: const TextStyle(
              color: Color(0xFF06B6D4),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Start: ${formatDate(item.startDate)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  'End: ${formatDate(item.endDate)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed:
                  status == 'active' ? () => _cancelSubscription(item) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Text('Cancel Subscription'),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    if (status == 'active') return const Color(0xFF22C55E);
    if (status.contains('cancel')) return const Color(0xFFF97316);
    if (status.contains('expire')) return const Color(0xFFEF4444);
    if (status == 'inactive') return const Color(0xFF6B7280);
    return const Color(0xFF06B6D4);
  }
}
