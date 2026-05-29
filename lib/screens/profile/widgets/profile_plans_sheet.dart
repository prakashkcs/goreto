import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Bottom-sheet plan picker shown when a user taps Subscribe on a profile.
/// Plans are presented as a horizontal carousel — one tall card at a time —
/// so multiple plans don't push the Subscribe button under the system nav
/// bar. Each card has a gradient background, animated tier icon, feature
/// list, and a wide Subscribe action pinned inside the card itself (so it
/// stays visible regardless of the system inset).
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
  final PageController _pageController =
      PageController(viewportFraction: 0.88);
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  int _isSubscribingPlanId = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage && mounted) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    if (_isSubscribingPlanId != 0) return;
    setState(() => _isSubscribingPlanId = planId);
    final result = await _service.subscribeToPlan(planId);
    if (!mounted) return;
    setState(() => _isSubscribingPlanId = 0);

    if (result['status'] == 'success') {
      NeonToast.success(context, result['message'] ?? 'Subscribed!');
      widget.onSubscribed?.call();
    } else {
      NeonToast.error(context, result['message'] ?? 'Failed to subscribe');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Carousel height tuned so a single plan with full feature list fits
    // without scrolling, and the bottom inset of the system nav bar is
    // respected (no Subscribe button hidden behind gesture area).
    final carouselHeight = (mq.size.height * 0.62).clamp(420.0, 560.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          top: 20,
          bottom: 20 + mq.viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.creatorName.isNotEmpty
                  ? 'Subscribe to ${widget.creatorName}'
                  : 'Choose your plan',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Unlock subscriber-only content',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: CircularProgressIndicator(color: Color(0xFFFF007F)),
              )
            else if (_plans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.workspace_premium_outlined,
                        color: Colors.white.withValues(alpha: 0.3), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'No plans available yet',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 14),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: carouselHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    final isActive = index == _currentPage;
                    return AnimatedScale(
                      scale: isActive ? 1.0 : 0.92,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: isActive ? 1.0 : 0.55,
                        duration: const Duration(milliseconds: 250),
                        child: _buildPlanCard(plan, index),
                      ),
                    );
                  },
                ),
              ),
              if (_plans.length > 1) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_plans.length, (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFFF007F)
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, int index) {
    final name = (plan['name'] ?? 'Plan').toString();
    final price = int.tryParse(plan['price_coins'].toString()) ?? 0;
    final duration = int.tryParse(plan['duration_days'].toString()) ?? 30;
    final planId = int.tryParse(plan['id'].toString()) ?? 0;
    final canMessage = plan['can_message_first'] == 1 ||
        plan['can_message_first'] == true;

    final customFeaturesRaw = plan['custom_features'];
    List<String> features = [];
    if (customFeaturesRaw != null) {
      try {
        if (customFeaturesRaw is String) {
          features = List<String>.from(jsonDecode(customFeaturesRaw));
        } else if (customFeaturesRaw is List) {
          features = List<String>.from(customFeaturesRaw);
        }
      } catch (_) {}
    }

    // Different gradient per tier so 2-plan carousels visually distinguish.
    final List<List<Color>> palette = [
      [const Color(0xFFFF007F), const Color(0xFFD946EF)],
      [const Color(0xFF00E5FF), const Color(0xFF0A84FF)],
      [const Color(0xFFFFB800), const Color(0xFFFF6A00)],
      [const Color(0xFF22C55E), const Color(0xFF06B6D4)],
    ];
    final colors = palette[index % palette.length];
    final isLoadingThis = _isSubscribingPlanId == planId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A28),
            const Color(0xFF0E0E16),
          ],
        ),
        border: Border.all(
          color: colors.first.withValues(alpha: 0.4),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Top gradient flair
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.first.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.first.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const CoinIcon(size: 18, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        '$price',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '/ $duration days',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (canMessage) _featureRow(
                            'Message creator first',
                            Icons.chat_bubble_rounded,
                            const Color(0xFF00E5FF),
                          ),
                          ...features.map(
                            (f) => _featureRow(
                              f,
                              Icons.check_circle_rounded,
                              colors.first,
                            ),
                          ),
                          if (features.isEmpty && !canMessage)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Subscriber-only access',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoadingThis ? null : () => _subscribe(planId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.first,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(colors: colors),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: isLoadingThis
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Subscribe Now',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
