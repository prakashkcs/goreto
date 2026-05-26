import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/utils/formatters.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/screens/match/profile_preview_screen.dart';
import 'package:love_vibe_pro/providers/match_provider.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/models/match_user.dart';

/// Premium "Find Match" Screen with swipe deck
class FindMatchScreen extends StatefulWidget {
  const FindMatchScreen({super.key});

  @override
  State<FindMatchScreen> createState() => _FindMatchScreenState();
}

class _FindMatchScreenState extends State<FindMatchScreen>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.5, 0),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _rotateAnim = Tween<double>(begin: 0.0, end: 0.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MatchProvider>(context, listen: false).loadNearbyUsers();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleSwipe(bool right) async {
    if (_animController.isAnimating) return;

    final provider = Provider.of<MatchProvider>(context, listen: false);
    final currentUser = provider.currentUser;

    // Animate
    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(right ? 2.0 : -2.0, 0),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _rotateAnim = Tween<double>(begin: 0.0, end: right ? 0.2 : -0.2).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Play sound & API call
    if (right) {
      SoundService().playReact();
      _showProposalSnackBar();
      if (currentUser != null) {
        try {
          // ignore: unused_local_variable
          final result = await ApiService().sendProposal(targetUserId: currentUser.id);
        } catch (e) {
        }
      }
    } else {
      SoundService().playTap();
    }

    await _animController.forward();

    if (mounted) {
      provider.nextUser();
      _animController.reset();
    }
  }

  void _showProposalSnackBar() {
    NeonToast.success(context, 'Proposal sent! Waiting for response...');
  }

  void _goToMyProfile() {
    NeonToast.info(
      context,
      'Go to the Profile Tab and tap Edit Profile to manage your settings.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MatchProvider>(context);
    final user = provider.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF007F).withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(),

                // Card area
                Expanded(
                  child: provider.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF007F),
                          ),
                        )
                      : user == null
                      ? _buildEmptyState(provider)
                      : _buildCardStack(user),
                ),

                // Action buttons
                if (user != null && !provider.isLoading) _buildActionButtons(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final provider = Provider.of<MatchProvider>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Title
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
            ).createShader(bounds),
            child: const Text(
              'Sathi Match',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const Spacer(),

          // Sort Button
          PopupMenuButton<NearbySortMode>(
            initialValue: provider.sortMode,
            onSelected: (mode) {
              provider.setSortMode(mode);
              provider.loadNearbyUsers();
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(Icons.sort, color: Color(0xFFFF007F), size: 20),
            ),
            color: const Color(0xFF1E1E1E),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: NearbySortMode.closest,
                child: Text('Closest', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: NearbySortMode.highestRated,
                child: Text('Top Rated', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: NearbySortMode.newest,
                child: Text('Newest', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // My Profile button
          GestureDetector(
            onTap: _goToMyProfile,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(Icons.person_outline, color: Color(0xFF00E5FF), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(MatchProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF007F).withValues(alpha: 0.2),
                    const Color(0xFFD946EF).withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.favorite_border_rounded,
                size: 50,
                color: const Color(0xFFFF007F).withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No more matches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Check back soon for new people!',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: provider.reset,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF007F),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack(MatchUser user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          return Transform.translate(
            offset: _slideAnim.value * MediaQuery.of(context).size.width,
            child: Transform.rotate(
              angle: _rotateAnim.value,
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: _buildMatchCard(user),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchCard(MatchUser user) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePreviewScreen(
             user: user,
             onProposal: () => _handleSwipe(true),
          )),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
            BoxShadow(
              color: const Color(0xFFFF007F).withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              CachedNetworkImage(
                imageUrl: user.photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF007F)),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white24,
                    size: 50,
                  ),
                ),
              ),

              // Gradient Overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black26,
                      Colors.black87,
                    ],
                    stops: [0.5, 0.7, 1.0],
                  ),
                ),
              ),

              // Match % Badge
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt,
                        color: Color(0xFF00E5FF),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user.matchPercent}% Match',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // User Info
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${user.name}, ${user.age}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF007F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${user.city}, ${user.country} • ${Formatters.formatDistance(user.distanceKm)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    // Interests & Qualities
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...user.interests.take(2).map((i) => _buildDetailBadge(i, Colors.white.withValues(alpha: 0.15))),
                        ...user.qualities.take(2).map((q) => _buildDetailBadge(q, const Color(0xFF00E5FF).withValues(alpha: 0.15))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildActionButton(
            Icons.close,
            const Color(0xFFFF3366),
            () => _handleSwipe(false),
          ),
          const SizedBox(width: 24),
          _buildActionButton(
            Icons.favorite,
            const Color(0xFF00E5FF),
            () => _handleSwipe(true),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 32),
      ),
    );
  }

  Widget _buildDetailBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
