import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';
import 'package:love_vibe_pro/screens/settings/kyc_screen.dart';

/// Overlay shown on subscriber-only posts for non-subscribers.
/// Blurs the content and shows a "Subscribe to Unlock" button.
class SubscriberLockOverlay extends StatelessWidget {
  final int creatorId;
  final String creatorName;
  final String creatorSubscriptionStatus;
  final VoidCallback? onSubscribed;

  const SubscriberLockOverlay({
    super.key,
    required this.creatorId,
    this.creatorName = '',
    this.creatorSubscriptionStatus = 'active',
    this.onSubscribed,
  });

  @override
  Widget build(BuildContext context) {
    final bool canSubscribe = creatorSubscriptionStatus == 'active';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.2),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lock icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: canSubscribe
                          ? [
                              const Color(0xFFFF007F).withValues(alpha: 0.25),
                              const Color(0xFF9C27B0).withValues(alpha: 0.15),
                            ]
                          : [
                              const Color(0xFFF97316).withValues(alpha: 0.25),
                              const Color(0xFFEAB308).withValues(alpha: 0.15),
                            ],
                    ),
                    border: Border.all(
                      color: canSubscribe
                          ? const Color(0xFFFF007F).withValues(alpha: 0.5)
                          : const Color(0xFFF97316).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    canSubscribe
                        ? Icons.lock_rounded
                        : Icons.verified_user_outlined,
                    color: canSubscribe
                        ? const Color(0xFFFF007F)
                        : const Color(0xFFF97316),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  canSubscribe
                      ? 'Subscriber Only'
                      : 'KYC Verification Required',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    canSubscribe
                        ? 'Subscribe to unlock this content'
                        : 'Please verify your identity (KYC) to access subscription features',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Subscribe button OR Verify KYC button
                if (canSubscribe)
                  GestureDetector(
                    onTap: () => _showPlansSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFF9C27B0)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF007F,
                            ).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Subscribe to Unlock',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const KycScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF97316), Color(0xFFEAB308)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFF97316,
                            ).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Verify KYC',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPlansSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111118),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PlansSheet(
        creatorId: creatorId,
        creatorName: creatorName,
        onSubscribed: () {
          Navigator.pop(ctx);
          onSubscribed?.call();
        },
      ),
    );
  }
}

/// Bottom sheet showing the creator's plans with subscribe buttons
class _PlansSheet extends StatefulWidget {
  final int creatorId;
  final String creatorName;
  final VoidCallback? onSubscribed;

  const _PlansSheet({
    required this.creatorId,
    this.creatorName = '',
    this.onSubscribed,
  });

  @override
  State<_PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends State<_PlansSheet> {
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title
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
                  'No plans available',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: _plans.map((plan) {
                      final name = plan['name'] ?? 'Plan';
                      final price =
                          int.tryParse(plan['price_coins'].toString()) ?? 0;
                      final duration =
                          int.tryParse(plan['duration_days'].toString()) ?? 30;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFFF007F,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF007F,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.workspace_premium,
                                color: Color(0xFFFF007F),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const CoinIcon(size: 14, color: Colors.amber),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$price',
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        ' · $duration days',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _isSubscribing
                                  ? null
                                  : () => _subscribe(
                                      int.parse(plan['id'].toString()),
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF007F),
                                      Color(0xFF9C27B0),
                                    ],
                                  ),
                                ),
                                child: _isSubscribing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Subscribe',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
