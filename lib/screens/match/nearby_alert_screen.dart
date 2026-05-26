import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/services/nearby_block_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

class NearbyAlertScreen extends StatefulWidget {
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String senderDistance;
  final String senderAge;

  const NearbyAlertScreen({
    super.key,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    this.senderDistance = '',
    this.senderAge = '',
  });

  @override
  State<NearbyAlertScreen> createState() => _NearbyAlertScreenState();
}

class _NearbyAlertScreenState extends State<NearbyAlertScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _entranceCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));

    _entranceCtrl.forward();
    SoundService().playNearbySound();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSendProposal() async {
    setState(() => _isLoading = true);
    try {
      final result =
          await ApiService().sendProposal(targetUserId: widget.senderId);
      if (!mounted) return;
      final matched = result['matched'] == true;
      NeonToast.show(
        context,
        matched
            ? 'It\'s a Match with ${widget.senderName}! 💕'
            : 'Proposal sent to ${widget.senderName}! 💐',
        type: matched ? NeonToastType.success : NeonToastType.success,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('already')) {
        NeonToast.show(context, 'Already sent a proposal ❤️',
            type: NeonToastType.info);
        Navigator.of(context).pop();
      } else {
        NeonToast.show(context, 'Could not send proposal',
            type: NeonToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmBlock() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF16162A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_rounded,
                  color: Color(0xFFEF4444), size: 42),
              const SizedBox(height: 12),
              const Text(
                'Block from Nearby?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You won\'t see ${widget.senderName}\'s nearby alerts or profile anymore. You can unblock them in Settings.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF2A2A3E)),
                        ),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xAAFFFFFF))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                        ),
                      ),
                      child: const Text('Block',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      await NearbyBlockService.instance.block(
        widget.senderId,
        name: widget.senderName,
        avatar: widget.senderAvatar,
      );
      if (!mounted) return;
      NeonToast.show(
        context,
        '${widget.senderName} blocked from nearby alerts',
        type: NeonToastType.info,
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.senderAvatar.isNotEmpty;
    final hasDistance = widget.senderDistance.isNotEmpty;
    final hasAge = widget.senderAge.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred avatar as full-screen background
          if (hasAvatar)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: widget.senderAvatar,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: const Color(0xFF0D0D1A)),
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF0D0D1A)),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.80),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Radial glow
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF007F).withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                  radius: 0.9,
                ),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  children: [
                    // Top bar — block button in top-right
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white70, size: 18),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _confirmBlock,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFEF4444)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_off_rounded,
                                      color: Color(0xFFEF4444), size: 14),
                                  SizedBox(width: 5),
                                  Text(
                                    'Block Nearby',
                                    style: TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // "Nearby" pill badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFF7C3AED)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded,
                              color: Colors.white, size: 14),
                          SizedBox(width: 5),
                          Text(
                            'NEARBY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Pulsing avatar with gradient ring
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: GestureDetector(
                        onTap: () {
                          if (widget.senderId.isNotEmpty) {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(userId: widget.senderId),
                            ));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF007F),
                                Color(0xFF7C3AED),
                                Color(0xFF00E5FF),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF007F)
                                    .withValues(alpha: 0.55),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 75,
                              backgroundColor: const Color(0xFF1A1A2E),
                              backgroundImage: hasAvatar
                                  ? CachedNetworkImageProvider(
                                      widget.senderAvatar)
                                  : null,
                              child: hasAvatar
                                  ? null
                                  : const Icon(Icons.person,
                                      size: 64, color: Colors.white54),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Name
                    Text(
                      widget.senderName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                              color: Color(0xFFFF007F), blurRadius: 20),
                        ],
                      ),
                    ),

                    // Age + Distance chips
                    if (hasAge || hasDistance)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasAge) ...[
                              _InfoChip(
                                icon: Icons.cake_rounded,
                                label: widget.senderAge,
                              ),
                              if (hasDistance) const SizedBox(width: 8),
                            ],
                            if (hasDistance)
                              _InfoChip(
                                icon: Icons.near_me_rounded,
                                label: widget.senderDistance,
                                color: const Color(0xFF22C55E),
                              ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    const Text(
                      'is near you right now!',
                      style: TextStyle(
                        color: Color(0xAAFFFFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Send Proposal — full width primary
                          SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              onTap:
                                  _isLoading ? null : _handleSendProposal,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 58,
                                decoration: BoxDecoration(
                                  gradient: _isLoading
                                      ? null
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFFFF007F),
                                            Color(0xFF7C3AED),
                                          ],
                                        ),
                                  color: _isLoading
                                      ? const Color(0xFF2A1A2E)
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _isLoading
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: const Color(0xFFFF007F)
                                                .withValues(alpha: 0.4),
                                            blurRadius: 20,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.favorite_rounded,
                                                color: Colors.white,
                                                size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Send Proposal',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Ignore button
                          SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Ignore',
                                    style: TextStyle(
                                      color: Color(0xCCFFFFFF),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // View profile link
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              if (widget.senderId.isNotEmpty) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProfileScreen(
                                        userId: widget.senderId),
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              'View Profile',
                              style: TextStyle(
                                color: Color(0xFF7C3AED),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF7C3AED),
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
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color = const Color(0xFFBF5AF2),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
