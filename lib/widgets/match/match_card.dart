import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:love_vibe_pro/utils/formatters.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/match_user.dart';

/// Swipe card for the Matches tab.
///
/// The photo is shown whole (BoxFit.contain) over a blurred, zoomed copy of
/// itself, so portrait, square and landscape photos all keep their real ratio
/// instead of being cropped to the card. The action buttons live below the
/// card (in MatchesView), so only the compact info panel overlays the photo.
class MatchCard extends StatelessWidget {
  final MatchUser profile;
  final bool isBackground;
  final double swipeProgress;
  final VoidCallback? onReport;
  /// Tap on the photo: open this person's photo gallery.
  final VoidCallback? onPhotoTap;

  const MatchCard({
    super.key,
    required this.profile,
    this.isBackground = false,
    this.swipeProgress = 0.0,
    this.onReport,
    this.onPhotoTap,
  });

  static const _pink = Color(0xFFFF007F);
  static const _purple = Color(0xFFD946EF);
  static const _cyan = Color(0xFF06B6D4);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: isBackground
          ? const EdgeInsets.fromLTRB(30, 12, 30, 0)
          : const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(1.6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isBackground
                ? [
                    _purple.withValues(alpha: 0.25),
                    _cyan.withValues(alpha: 0.25),
                  ]
                : const [_pink, _purple, _cyan],
          ),
          boxShadow: isBackground
              ? null
              : [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.30),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26.4),
          child: ColoredBox(
            color: const Color(0xFF0D0818),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: isBackground ? null : onPhotoTap,
                  child: _buildPhoto(),
                ),

                // Soft shade at the top (for the ⋮ button) and a stronger
                // one at the bottom where the info panel sits.
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.14, 0.58, 1.0],
                        colors: [
                          Color(0x66000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xE6000000),
                        ],
                      ),
                    ),
                  ),
                ),

                if (!isBackground && profile.matchPercent > 0)
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _glassPill(
                      icon: Icons.favorite_rounded,
                      iconColor: _pink,
                      text: '${profile.matchPercent}% match',
                    ),
                  ),

                if (onPhotoTap != null && !isBackground)
                  Positioned(
                    top: profile.matchPercent > 0 ? 52 : 14,
                    left: 14,
                    child: GestureDetector(
                      onTap: onPhotoTap,
                      child: _glassPill(
                        icon: Icons.photo_library_rounded,
                        iconColor: _cyan,
                        text: 'Photos',
                      ),
                    ),
                  ),

                if (onReport != null && !isBackground)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: onReport,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Icon(Icons.more_horiz_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildInfoPanel(),
                ),

                if (swipeProgress.abs() > 0.05) _buildSwipeOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    if (profile.photoUrl.isEmpty) return _photoFallback();
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred backdrop fills whatever the real photo doesn't cover.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Transform.scale(
            scale: 1.25,
            child: CachedNetworkImage(
              imageUrl: profile.photoUrl,
              fit: BoxFit.cover,
              memCacheWidth: 200,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
        // The real photo, uncropped.
        CachedNetworkImage(
          imageUrl: profile.photoUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: _pink, strokeWidth: 2),
          ),
          errorWidget: (_, __, ___) => _photoFallback(),
        ),
      ],
    );
  }

  Widget _photoFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D1B4E), Color(0xFF0D0818)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Text(
          profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 120,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    final city = profile.city.trim();
    final distance = profile.distanceKm == null
        ? ''
        : Formatters.formatDistance(profile.distanceKm);
    final tags = <Widget>[
      if (profile.interests.isNotEmpty)
        _tag(profile.interests.first, _pink, Icons.favorite_rounded),
      if (profile.lookingFor.isNotEmpty)
        _tag(profile.lookingFor.first, _cyan, Icons.search_rounded),
      if (profile.qualities.isNotEmpty)
        _tag(profile.qualities.first, _purple, Icons.auto_awesome_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name, age, online
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: profile.name,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    if (profile.age > 0)
                      TextSpan(
                        text: '  ${profile.age}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ]),
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -0.4,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.isOnline) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Location · distance · rating
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (city.isNotEmpty)
                _glassPill(
                    icon: Icons.location_on_rounded,
                    iconColor: _pink,
                    text: city),
              if (distance.isNotEmpty)
                _glassPill(
                    icon: Icons.near_me_rounded,
                    iconColor: _cyan,
                    text: '$distance away'),
              if (profile.rating > 0)
                _glassPill(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFFFC83D),
                    text: profile.rating.toStringAsFixed(1)),
            ],
          ),

          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: tags),
          ],
        ],
      ),
    );
  }

  Widget _glassPill({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 13),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeOverlay() {
    final isRight = swipeProgress > 0;
    final opacity = (swipeProgress.abs() * 1.4).clamp(0.0, 1.0);
    final color = isRight ? _pink : const Color(0xFF8E8E9A);

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: color.withValues(alpha: opacity * 0.22),
          child: Align(
            alignment: isRight ? Alignment.topLeft : Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
              child: Transform.rotate(
                angle: isRight ? -0.3 : 0.3,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isRight ? 'PROPOSE' : 'IGNORE',
                      style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
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
