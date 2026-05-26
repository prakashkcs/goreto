import 'package:flutter/material.dart';
import 'package:love_vibe_pro/utils/formatters.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/match_user.dart';

class MatchCard extends StatelessWidget {
  final MatchUser profile;
  final bool isBackground;
  final double swipeProgress;
  final VoidCallback? onReport;

  const MatchCard({
    super.key,
    required this.profile,
    this.isBackground = false,
    this.swipeProgress = 0.0,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Card is slightly inset so the stack depth is visible
    final double cardWidth = size.width - (isBackground ? 32 : 0);
    final double cardHeight = size.height - (isBackground ? 24 : 0);

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: isBackground
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFFFF2D55).withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Photo ──────────────────────────────────────────────────
            CachedNetworkImage(
              imageUrl: profile.photoUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A0A2E), Color(0xFF0D0818)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF2D55),
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2D1B4E), Color(0xFF0D0818)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),

            // ── Gradient overlay ───────────────────────────────────────
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.18, 0.50, 0.72, 1.0],
                  colors: [
                    Color(0x99000000),
                    Color(0x11000000),
                    Color(0x00000000),
                    Color(0xCC000000),
                    Color(0xF8000000),
                  ],
                ),
              ),
            ),

            // ── Top-right: report button ───────────────────────────────
            if (onReport != null && !isBackground)
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: onReport,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
              ),

            // ── Bottom info panel ──────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildInfoPanel(),
            ),

            // ── Swipe overlay ──────────────────────────────────────────
            if (swipeProgress.abs() > 0.05) _buildSwipeOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 200),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.82),
            Colors.black.withValues(alpha: 0.96),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  profile.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Age badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${profile.age}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Online dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Location + distance row
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFFFF2D55), size: 15),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${profile.city}  ·  ${Formatters.formatDistance(profile.distanceKm)} away',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              // Rating pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      profile.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Tags
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              if (profile.interests.isNotEmpty)
                _tag(profile.interests.first, const Color(0xFFFF2D55),
                    Icons.favorite_rounded),
              if (profile.lookingFor.isNotEmpty)
                _tag(profile.lookingFor.first, const Color(0xFF00E5FF),
                    Icons.search_rounded),
              if (profile.qualities.isNotEmpty)
                _tag(profile.qualities.first, const Color(0xFFBF5AF2),
                    Icons.auto_awesome_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeOverlay() {
    final isRight = swipeProgress > 0;
    final opacity = (swipeProgress.abs() * 1.4).clamp(0.0, 1.0);
    final color = isRight ? const Color(0xFF00E5FF) : const Color(0xFFFF3366);

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: color.withValues(alpha: opacity * 0.28),
          ),
          child: Align(
            alignment: isRight ? Alignment.topLeft : Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Transform.rotate(
                angle: isRight ? 0.35 : -0.35,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isRight ? 'LIKE' : 'NOPE',
                    style: TextStyle(
                      color: color,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
