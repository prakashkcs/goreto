import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/screens/profile/widgets/neon_button.dart';
import 'package:love_vibe_pro/screens/profile/widgets/social_links_row.dart';
import 'package:love_vibe_pro/screens/match/proposals_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/gifter_badge.dart';

/// Profile header with cover photo, avatar, bio, and action buttons
/// Fixed: No overflow, uses Wrap for buttons, handles nulls properly
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onEditCover;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onEditBio;
  final VoidCallback? onFollow;
  final VoidCallback? onSubscribe;
  final VoidCallback? onInbox;
  final VoidCallback? onLogout;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final bool isFollowLoading;
  final bool isSubscribeLoading;

  const ProfileHeader({
    super.key,
    required this.profile,
    this.onEditCover,
    this.onEditAvatar,
    this.onEditBio,
    this.onFollow,
    this.onSubscribe,
    this.onInbox,
    this.onLogout,
    this.onFollowersTap,
    this.onFollowingTap,
    this.isFollowLoading = false,
    this.isSubscribeLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final String avatarUrl =
        profile.avatar.isNotEmpty ? profile.avatar : profile.profilePicUrl;
    final String coverUrl =
        profile.cover.isNotEmpty ? profile.cover : profile.coverPicUrl;

    return Column(
      children: [
        // Cover Photo + Avatar — LayoutBuilder lets us extend the Stack's
        // hit-test bounds to include the full avatar so the pencil button is
        // always tappable (Positioned(bottom:-52) put the pencil outside the
        // old Stack's bounds, silently swallowing taps).
        LayoutBuilder(
          builder: (context, constraints) {
            final coverHeight = constraints.maxWidth * 9.0 / 16.0;
            // Avatar total radius: CircleAvatar(52) + inner padding(2) + outer padding(4) = 58
            const double avatarOuterRadius = 58.0;

            return SizedBox(
              height: coverHeight + avatarOuterRadius,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Cover image ──────────────────────────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: coverHeight,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: coverUrl.isNotEmpty
                            ? (coverUrl.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 900,
                                    errorWidget: (_, __, ___) =>
                                        _buildCoverPlaceholder(),
                                  )
                                : Image.file(File(coverUrl), fit: BoxFit.cover))
                            : _buildCoverPlaceholder(),
                      ),
                    ),
                  ),

                  // ── Dark overlay (cover only) ─────────────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: coverHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.12),
                              Colors.black.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Cover edit button ────────────────────────────────
                  if (profile.isOwnProfile)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onEditCover,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFF007F)
                                  .withValues(alpha: 0.85),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF007F)
                                    .withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),

                  // ── Avatar — Positioned(bottom:0) keeps it fully within
                  //    Stack bounds so every tap is hit-testable.
                  //    bottom:0 → avatar bottom = Stack bottom = coverHeight+58
                  //    avatar top = coverHeight+58-116 = coverHeight-58
                  //    → avatar is centred on the cover's bottom edge ✓
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: profile.isOwnProfile ? onEditAvatar : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Neon ring + border
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF007F),
                                    Color(0xFF00E5FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF007F)
                                        .withValues(alpha: 0.6),
                                    blurRadius: 25,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 30,
                                    spreadRadius: -5,
                                  ),
                                ],
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black,
                                ),
                                child: _buildAvatar(avatarUrl),
                              ),
                            ),
                            if (profile.isOwnProfile)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF007F),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF007F)
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 16,
                                  ),
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
          },
        ),

        // Name & Username
        const SizedBox(height: 10),
        Text(
          profile.name.isNotEmpty ? profile.name : 'User',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26, // Increased size
            fontWeight: FontWeight.w900, // Heavier weight
            letterSpacing: -0.5,
            shadows: [
              Shadow(color: Color(0xFFFF007F), blurRadius: 15),
              Shadow(color: Color(0xFFFF007F), blurRadius: 5),
            ],
          ),
        ),
        if (profile.username != null && profile.username!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            profile.username!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Compact Info Bar (Location, Rating, Proposals, Income)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.location.isNotEmpty)
                _buildCompactBadge(
                  Icons.location_on,
                  profile.location,
                  const Color(0xFF00E5FF),
                ),
              _buildCompactBadge(
                Icons.star_rounded,
                profile.rating.toStringAsFixed(1),
                const Color(0xFFFFD700),
              ),
              if (profile.isOwnProfile)
                _ProposalBadge(
                  proposalsCount: profile.proposalsCount,
                  buildCompactBadge: _buildCompactBadge,
                ),
              if (profile.income > 0 &&
                  (profile.incomeStatus == 'verified' ||
                      profile.incomeStatus == 'approved'))
                _buildIncomeBadge(profile.income, true),
              if (profile.gifterLevel > 0)
                GifterBadge(
                  level: profile.gifterLevel,
                  size: GifterBadgeSize.pill,
                  animated: true,
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Public Relationship Badge
        _buildRelationshipBadge(context),

        // Bio with edit
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  profile.bio.isNotEmpty
                      ? profile.bio
                      : (profile.isOwnProfile ? 'Add a bio...' : ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: profile.bio.isNotEmpty ? 0.8 : 0.4,
                    ),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Stats Row — compact inline
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onFollowersTap,
                    behavior: HitTestBehavior.opaque,
                    child: _buildStatItem(
                      _formatCount(profile.followersCount),
                      'Followers',
                      const Color(0xFFFF007F),
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.1)),
                Expanded(
                  child: GestureDetector(
                    onTap: onFollowingTap,
                    behavior: HitTestBehavior.opaque,
                    child: _buildStatItem(
                      _formatCount(profile.followingCount),
                      'Following',
                      const Color(0xFF7C3AED),
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.1)),
                Expanded(
                  child: _buildStatItem(
                    _formatCount(profile.postsCount),
                    'Posts',
                    const Color(0xFF00E5FF),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Social Links Row
        const SizedBox(height: 10),
        SocialLinksRow(links: profile.socialLinks),

        const SizedBox(height: 30),

        // Action Buttons - Using Wrap to prevent overflow
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: profile.isOwnProfile
              ? Column(
                  children: [
                    GestureDetector(
                      onTap: onEditBio,
                      child: Container(
                        width: 240,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF)
                                  .withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Edit Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onLogout,
                      child: Container(
                        width: 240,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout_rounded,
                                color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Logout',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Follow button:
                    //   mutual (you follow + they follow) → Friends
                    //   you follow only                  → Following
                    //   they follow you only             → Follow Back
                    //   neither                          → Follow
                    Expanded(
                      flex: 4,
                      child: NeonButton(
                        label: (profile.isFollowing && profile.isFollowedBy)
                            ? 'Friends'
                            : (profile.isFollowing
                                ? 'Following'
                                : (profile.isFollowedBy
                                    ? 'Follow Back'
                                    : 'Follow')),
                        neonColor: profile.isFollowing
                            ? Colors.white.withValues(alpha: 0.6)
                            : (profile.isSubscribed
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFF3B82F6)),
                        isFilled:
                            profile.isFollowing ? false : !profile.isSubscribed,
                        onTap: onFollow,
                        isLoading: isFollowLoading,
                        height: 38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Subscribe button — disabled when creator has no plan
                    Expanded(
                      flex: 5,
                      child: NeonButton(
                        label: 'Subscribe',
                        isFilled: true,
                        isPremium: true,
                        onTap: profile.subscriptionStatus == 'active'
                            ? onSubscribe
                            : null,
                        isDisabled: profile.subscriptionStatus != 'active',
                        isLoading: isSubscribeLoading,
                        height: 38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Inbox button
                    Expanded(
                      flex: 3,
                      child: NeonButton(
                        label: 'Inbox',
                        icon: Icons.mail_outline,
                        neonColor: const Color(0xFFD946EF),
                        onTap: onInbox,
                        height: 38,
                      ),
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 24),

        // Match Profile Details underneath actions
        _buildMatchInfo(),

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildMatchInfo() {
    if (profile.interests.isEmpty &&
        profile.lookingFor.isEmpty &&
        profile.qualities.isEmpty) {
      return const SizedBox.shrink();
    }
    return MatchInfoSection(profile: profile);
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image,
          color: Colors.white.withValues(alpha: 0.1),
          size: 60,
        ),
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl) {
    return CircleAvatar(
      radius: 52,
      backgroundColor: const Color(0xFF1A1A1A),
      backgroundImage: avatarUrl.isNotEmpty
          ? (avatarUrl.startsWith('http')
              ? CachedNetworkImageProvider(avatarUrl)
              : null)
          : null,
      child: avatarUrl.isEmpty
          ? const Icon(Icons.person, color: Colors.white54, size: 40)
          : (!avatarUrl.startsWith('http')
              ? ClipOval(
                  child: Image.file(
                    File(avatarUrl),
                    width: 104,
                    height: 104,
                    fit: BoxFit.cover,
                  ),
                )
              : null),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildStatItem(String value, String label, Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 6)],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: accent.withValues(alpha: 0.75),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBadge(
    IconData icon,
    String label,
    Color color, {
    bool isVerified = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A), // Elegant dark background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Color(0xFF00E5FF), size: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildIncomeBadge(double income, bool isVerified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isVerified
              ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
              : const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
        boxShadow: isVerified
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet,
            color: Color(0xFF00E5FF),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'Npr. ${income.toStringAsFixed(0)}/mo',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (isVerified) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Color(0xFF00E5FF), size: 12),
                  SizedBox(width: 3),
                  Text(
                    'Verified',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelationshipBadge(BuildContext context) {
    if (profile.publicPartner == null) return const SizedBox.shrink();

    final p = profile.publicPartner!;

    // Only show if BOTH sides have connected (mutual connection).
    // The backend should set both_connected=1 only when both users accepted.
    final bothConnected = p['both_connected'];
    bool isMutual = false;
    if (bothConnected == null) {
      isMutual = true; // legacy: trust backend
    } else if (bothConnected is bool) {
      isMutual = bothConnected;
    } else {
      final s = bothConnected.toString().toLowerCase().trim();
      isMutual = s == '1' || s == 'true';
    }
    if (!isMutual) return const SizedBox.shrink();

    // Resolve partner name — try every possible key the API might return
    final rawName = p['partner_name'] ??
        p['name'] ??
        p['username'] ??
        p['display_name'] ??
        p['full_name'] ??
        '';
    final partnerName =
        rawName.toString().trim().isNotEmpty ? rawName.toString().trim() : null;

    // Resolve partner avatar
    final partnerAvatar = p['partner_avatar'] ??
        p['avatar'] ??
        p['avatar_url'] ??
        p['profile_pic'];

    // Resolve partner id
    final partnerId = p['partner_id'] ?? p['user_id'] ?? p['id'];

    // Resolve partner gender from API
    final partnerGender = (p['partner_gender'] ?? p['gender'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    // Determine title based on PARTNER's gender (not owner's).
    // If partner is male → "He Is My King"
    // If partner is female → "She Is My Queen"
    // Default to "They" for non-binary/unknown
    final isPartnerMale = partnerGender == 'male' || partnerGender == 'm';
    final isPartnerFemale = partnerGender == 'female' || partnerGender == 'f';
    final String title;
    if (isPartnerMale) {
      title = "♛ He Is My King";
    } else if (isPartnerFemale) {
      title = "♚ She Is My Queen";
    } else {
      title = "💕 Connected With";
    }

    // Choose colors based on partner gender for consistent visual pairing
    final primaryColor = isPartnerMale
        ? const Color(0xFF00E5FF)
        : (isPartnerFemale ? const Color(0xFFFF007F) : const Color(0xFFD946EF));
    final shadowColor = primaryColor.withValues(alpha: 0.5);

    return InkWell(
      onTap: () {
        if (partnerId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (p2_0) => ProfileScreen(userId: partnerId.toString()),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: primaryColor.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 15,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.black26,
              backgroundImage: partnerAvatar != null &&
                      partnerAvatar.toString().startsWith('http')
                  ? CachedNetworkImageProvider(partnerAvatar)
                  : null,
              child: (partnerAvatar == null ||
                      !partnerAvatar.toString().startsWith('http'))
                  ? const Icon(Icons.favorite, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  "${partnerName ?? 'Partner'} ❤️",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.favorite, color: primaryColor, size: 14),
          ],
        ),
      ),
    );
  }
}

class MatchInfoSection extends StatefulWidget {
  final UserProfile profile;

  const MatchInfoSection({super.key, required this.profile});

  @override
  State<MatchInfoSection> createState() => _MatchInfoSectionState();
}

class _MatchInfoSectionState extends State<MatchInfoSection> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> sections = [];
    if (widget.profile.lookingFor.isNotEmpty) {
      sections.add({
        'title': 'Looking For',
        'icon': Icons.search_rounded,
        'color': const Color(0xFF00E5FF),
        'items': widget.profile.lookingFor,
      });
    }
    if (widget.profile.interests.isNotEmpty) {
      sections.add({
        'title': 'Interests',
        'icon': Icons.local_fire_department,
        'color': const Color(0xFFFF007F),
        'items': widget.profile.interests,
      });
    }
    if (widget.profile.qualities.isNotEmpty) {
      sections.add({
        'title': 'Qualities',
        'icon': Icons.auto_awesome,
        'color': const Color(0xFFD946EF),
        'items': widget.profile.qualities,
      });
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    if (_selectedIndex >= sections.length) _selectedIndex = 0;
    final currentSection = sections[_selectedIndex];
    final color = currentSection['color'] as Color;
    final items = currentSection['items'] as List<String>;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Column: Category Selectors
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(sections.length, (index) {
                  final section = sections[index];
                  final isSelected = _selectedIndex == index;
                  final sectionColor = section['color'] as Color;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? sectionColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? sectionColor.withValues(alpha: 0.5)
                              : Colors.white10,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            section['icon'] as IconData,
                            size: 14,
                            color: isSelected ? sectionColor : Colors.white38,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              section['title'] as String,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.white38,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 16),
            // Divider
            Container(width: 1, color: Colors.white10),
            const SizedBox(width: 16),
            // Right Column: Elements List
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Column(
                  key: ValueKey<int>(_selectedIndex),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stateful widget for the proposals badge that fetches unread count
class _ProposalBadge extends StatefulWidget {
  final int proposalsCount;
  final Widget Function(IconData, String, Color, {bool isVerified})
      buildCompactBadge;

  const _ProposalBadge({
    required this.proposalsCount,
    required this.buildCompactBadge,
  });

  @override
  State<_ProposalBadge> createState() => _ProposalBadgeState();
}

class _ProposalBadgeState extends State<_ProposalBadge> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchBadgeCount();
  }

  Future<void> _fetchBadgeCount() async {
    try {
      final count = await ApiService().getProposalBadgeCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (p3_0) => const ProposalsScreen()),
        );
        _fetchBadgeCount();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.buildCompactBadge(
            Icons.favorite_rounded,
            widget.proposalsCount.toString(),
            const Color(0xFFFF007F),
          ),
          if (_unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
