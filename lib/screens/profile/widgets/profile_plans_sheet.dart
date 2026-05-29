import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class ProfilePlansSheet extends StatefulWidget {
  final int creatorId;
  final String creatorName;
  final VoidCallback? onSubscribed;

  const ProfilePlansSheet({
    super.key,
    required this.creatorId,
    this.creatorName = '',
    this.onSubscribed,
  });

  @override
  State<ProfilePlansSheet> createState() => _ProfilePlansSheetState();
}

class _ProfilePlansSheetState extends State<ProfilePlansSheet> {
  final SubscriptionPlanService _service = SubscriptionPlanService();
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  bool _isSubscribing = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final plans = await _service.getCreatorPlans(widget.creatorId);
    if (mounted) {
      setState(() {
        _plans = plans;
        _isLoading = false;
      });
    }
  }

  Future<void> _subscribe(int planId) async {
    setState(() => _isSubscribing = true);
    final result = await _service.subscribeToPlan(planId);
    if (!mounted) return;
    setState(() => _isSubscribing = false);

    if (result['status'] == 'success') {
      NeonToast.success(context, result['message'] ?? 'Subscribed!');
      widget.onSubscribed?.call();
    } else {
      NeonToast.error(context, result['message'] ?? 'Failed to subscribe');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scroll + clamp height so multi-plan creators don't overflow the bottom
    // sheet (was producing the yellow/black overflow stripe). Use 80% of
    // screen height as the upper bound; the actual height collapses to the
    // content when fewer plans are present thanks to mainAxisSize.min.
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.creatorName.isNotEmpty
                ? 'Subscribe to ${widget.creatorName}'
                : 'Subscribe',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock subscriber-only content',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFFFF007F)),
            )
          else if (_plans.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No subscription plans available',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            )
          else
            ..._plans.map((plan) {
              final name = plan['name'] ?? 'Plan';
              final price = int.tryParse(plan['price_coins'].toString()) ?? 0;
              final duration =
                  int.tryParse(plan['duration_days'].toString()) ?? 30;

              final customFeaturesRaw = plan['custom_features'];
              List<String> features = [];
              if (customFeaturesRaw != null) {
                try {
                  if (customFeaturesRaw is String) {
                    features = List<String>.from(jsonDecode(customFeaturesRaw));
                  } else if (customFeaturesRaw is List) {
                    features = List<String>.from(customFeaturesRaw);
                  }
                } catch (e) {
                }
              }

              final canMessage =
                  plan['can_message_first'] == 1 ||
                  plan['can_message_first'] == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1E2A), Color(0xFF111118)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF007F,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFFF007F),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const CoinIcon(size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$price coins',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      ' / $duration days',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 
                                          0.5,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (features.isNotEmpty || canMessage)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (canMessage)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_rounded,
                                      color: Color(0xFF00E5FF),
                                      size: 16,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Can message creator first',
                                      style: TextStyle(
                                        color: Color(0xFF00E5FF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ...features.map(
                              (f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFFFF007F),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        f,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSubscribing
                                    ? null
                                    : () => _subscribe(
                                        int.parse(plan['id'].toString()),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF007F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isSubscribing
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Subscribe Now',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
        ],
        ),
      ),
    );
  }
}
