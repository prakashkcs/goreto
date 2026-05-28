import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:love_vibe_pro/widgets/login_required_sheet.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/providers/match_provider.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/models/match_user.dart';
import 'package:love_vibe_pro/widgets/match/match_card.dart';

import 'package:love_vibe_pro/services/signaling_service.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/chat/call/webrtc_call_screen.dart';
import 'package:love_vibe_pro/services/video_call/video_call_manager.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/widgets/post_call_bottom_sheet.dart';
import 'package:love_vibe_pro/screens/match/proposals_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/match/nearby_user_preview_screen.dart';
import 'package:love_vibe_pro/utils/formatters.dart';

class MatchTab extends StatelessWidget {
  const MatchTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MatchProvider()..loadNearbyUsers(),
      child: const _MatchTabContent(),
    );
  }
}

class _MatchTabContent extends StatefulWidget {
  const _MatchTabContent();

  @override
  State<_MatchTabContent> createState() => _MatchTabContentState();
}

class _MatchTabContentState extends State<_MatchTabContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final matchProvider = Provider.of<MatchProvider>(context);
    final isGuest = !auth.isAuthenticated && auth.isGuest;

    // Task 6: Gating if match profile not set
    if (!matchProvider.hasMatchProfile && !isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0818),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF2D55).withValues(alpha: 0.22),
                        const Color(0xFFBF5AF2).withValues(alpha: 0.22),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFF2D55).withValues(alpha: 0.50),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.28),
                        blurRadius: 26,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_pin_circle_rounded,
                    size: 44,
                    color: Color(0xFFFF2D55),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Complete your Match Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Set up your profile from the Profile Tab to start matching.',
                  style: TextStyle(
                      color: Color(0xFF8E8E93), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                GestureDetector(
                  onTap: () {
                    NeonToast.info(
                      context,
                      'Tap the Profile icon at the bottom right, then "Edit Profile".',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                      ),
                      borderRadius: const BorderRadius.all(Radius.circular(26)),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFFF2D55).withValues(alpha: 0.42),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Text(
                      'How to Set Up',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0818),
      body: Column(
        children: [
          // ── Pinned header (status bar safe) ──
          Container(
            color: const Color(0xFF0D0818),
            padding: EdgeInsets.only(top: topPad + 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactTopBar(context),
                _buildTabBar(),
              ],
            ),
          ),
          // ── Content ──
          Expanded(
            child: isGuest
                ? TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildLockedTab(context, 'find matches'),
                      _buildLockedTab(context, 'discover nearby people'),
                      _buildLockedTab(context, 'make video calls'),
                    ],
                  )
                : TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const MatchesView(),
                      const NearbyView(),
                      const RandomCallView(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 0),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
            ).createShader(bounds),
            child: const Text(
              'Goreto',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Spacer(),
          // Proposals
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProposalsScreen())),
            child: _iconBtn(Icons.favorite_rounded, const Color(0xFFFF2D55)),
          ),
          const SizedBox(width: 6),
          // Filter
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: _iconBtn(Icons.tune_rounded, Colors.white70),
            color: const Color(0xFF1A1A2E),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16))),
            onSelected: (value) {
              final p = Provider.of<MatchProvider>(context, listen: false);
              if (value == 'nearby') p.setSortMode(NearbySortMode.closest);
              if (value == 'age') p.setSortMode(NearbySortMode.newest);
              if (value == 'similarity')
                p.setSortMode(NearbySortMode.highestRated);
            },
            itemBuilder: (_) => [
              _sortItem('similarity', Icons.favorite, 'Similarity',
                  const Color(0xFFFF2D55)),
              _sortItem(
                  'nearby', Icons.near_me, 'Nearby', const Color(0xFF00E5FF)),
              _sortItem('age', Icons.cake, 'Ages', const Color(0xFFD946EF)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }

  PopupMenuEntry<String> _sortItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0818),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: -2,
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF5A5A6E),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(5),
        tabs: const [
          Tab(
            icon: Icon(Icons.favorite_rounded, size: 18),
            text: 'Matches',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.near_me_rounded, size: 18),
            text: 'Nearby',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.shuffle_rounded, size: 18),
            text: 'Random',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedTab(BuildContext context, String feature) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF2D55).withValues(alpha: 0.20),
                  const Color(0xFFBF5AF2).withValues(alpha: 0.20),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2D55).withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.lock_rounded,
                size: 36, color: Color(0xFFFF2D55)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Login Required',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Login to $feature',
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => LoginRequiredSheet.show(context, feature: feature),
            child: Container(
              width: 160,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                ),
                borderRadius: const BorderRadius.all(Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF2D55).withValues(alpha: 0.40),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  MATCHES VIEW
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class MatchesView extends StatefulWidget {
  const MatchesView({super.key});

  @override
  State<MatchesView> createState() => _MatchesViewState();
}

class _MatchesViewState extends State<MatchesView>
    with TickerProviderStateMixin {
  late AnimationController _flyOffController;

  // Drag state (owned here, NOT in the card widget)
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isAnimating = false;

  // Swipe progress for overlay: -1 = left, 0 = center, 1 = right
  double get _swipeProgress => (_dragOffset.dx / 200).clamp(-1.0, 1.0);
  double get _rotation => _dragOffset.dx / 1000;

  @override
  void initState() {
    super.initState();
    _flyOffController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _flyOffController.dispose();
    super.dispose();
  }

  // â”€â”€ Drag handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onPanStart(DragStartDetails _) {
    if (_isAnimating) return;
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isAnimating || !_isDragging) return;
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails _) {
    if (_isAnimating || !_isDragging) return;
    setState(() => _isDragging = false);

    const threshold = 100.0;
    if (_dragOffset.dx > threshold) {
      _handleSwipe(true); // right = propose
    } else if (_dragOffset.dx < -threshold) {
      _handleSwipe(false); // left = reject
    } else {
      _animateReset();
    }
  }

  void _animateReset() {
    final startOffset = _dragOffset;
    _flyOffController.reset();

    late Animation<Offset> resetAnim;
    resetAnim = Tween<Offset>(begin: startOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _flyOffController, curve: Curves.elasticOut),
    );

    _isAnimating = true;
    _flyOffController.addListener(() {
      if (mounted) setState(() => _dragOffset = resetAnim.value);
    });

    _flyOffController.forward().then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
          _isAnimating = false;
        });
        _flyOffController.removeListener(() {});
      }
    });
  }

  // â”€â”€ Core swipe action (button or drag) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _handleSwipe(bool right) async {
    if (_isAnimating) return;
    _isAnimating = true;

    final provider = Provider.of<MatchProvider>(context, listen: false);
    final currentUser = provider.currentUser;

    // Play sound & haptic
    if (right) {
      SoundService().playProposed();
      NeonToast.success(context, 'Proposal sent! 🌹');

      // â”€â”€ Actually call the Proposal API â”€â”€
      if (currentUser != null) {
        try {
          final result =
              await ApiService().sendProposal(targetUserId: currentUser.id);
          final matched = result['matched'] == true;
          if (matched && mounted) {
            _showMutualMatchDialog(currentUser);
          }
        } catch (_) {}
      }
    } else {
      SoundService().playReject();
    }

    // Animate the card flying off screen
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetX = right ? screenWidth * 1.5 : -screenWidth * 1.5;
    final startOffset = _dragOffset;
    final endOffset = Offset(targetX, _dragOffset.dy);

    _flyOffController.reset();
    late Animation<Offset> flyAnim;
    flyAnim = Tween<Offset>(
      begin: startOffset,
      end: endOffset,
    ).animate(CurvedAnimation(parent: _flyOffController, curve: Curves.easeIn));

    void listener() {
      if (mounted) setState(() => _dragOffset = flyAnim.value);
    }

    _flyOffController.addListener(listener);

    await _flyOffController.forward();

    if (mounted) {
      _flyOffController.removeListener(listener);
      provider.nextUser(wasProposal: right);
      setState(() {
        _dragOffset = Offset.zero;
        _isAnimating = false;
      });
      _flyOffController.reset();
    }
  }

  void _showMutualMatchDialog(MatchUser user) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24))),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💕', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                "It's a Match!",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'You and ${user.name} both like each other!',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Keep Swiping',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Navigate to chat with this user
                      Navigator.pushNamed(context, '/chat', arguments: {
                        'userId': user.id,
                        'userName': user.name,
                        'userAvatar': user.photoUrl,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF007F),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(20))),
                    ),
                    child: const Text('Say Hello 👋'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Undo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _handleUndo() {
    final provider = Provider.of<MatchProvider>(context, listen: false);
    if (!provider.canUndo) return;
    SoundService().playTap();
    provider.undoLast();
    NeonToast.show(context, 'Undone â†©', type: NeonToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MatchProvider>(context);
    final currentUser = provider.currentUser;
    final nextUser = provider.nextMatchUser;

    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF007F)),
      );
    }

    if (currentUser == null) {
      return _buildNoMatchesView(provider);
    }

    return Stack(
      children: [
        // Full Screen Cards
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Next Card (behind)
                if (nextUser != null)
                  MatchCard(
                    key: ValueKey('next-${nextUser.id}'),
                    profile: nextUser,
                    isBackground: true,
                  ),
                // Current Card
                Transform.translate(
                  offset: _dragOffset,
                  child: Transform.rotate(
                    angle: _rotation,
                    child: MatchCard(
                      key: ValueKey('current-${currentUser.id}'),
                      profile: currentUser,
                      swipeProgress: _swipeProgress,
                      onReport: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Action Buttons bar — floating over bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.95),
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Undo — amber filled for visibility
                    GestureDetector(
                      onTap: provider.canUndo ? _handleUndo : null,
                      child: AnimatedOpacity(
                        opacity: provider.canUndo ? 1.0 : 0.4,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: provider.canUndo
                                    ? Colors.amber.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: provider.canUndo
                                      ? Colors.amber
                                      : Colors.white24,
                                  width: 2,
                                ),
                                boxShadow: provider.canUndo
                                    ? [
                                        BoxShadow(
                                          color: Colors.amber
                                              .withValues(alpha: 0.55),
                                          blurRadius: 16,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                Icons.undo_rounded,
                                color: provider.canUndo
                                    ? Colors.amber
                                    : Colors.white38,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Undo',
                              style: TextStyle(
                                color: provider.canUndo
                                    ? Colors.amber
                                    : Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildActionButton(
                      Icons.close_rounded,
                      const Color(0xFF8E8E9A),
                      () => _handleSwipe(false),
                      size: 50,
                      label: 'Ignore',
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfilePreviewScreen(
                            user: currentUser,
                            onProposal: () => _handleSwipe(true),
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25)),
                            ),
                            child: const Icon(Icons.person_rounded,
                                color: Colors.white70, size: 19),
                          ),
                          const SizedBox(height: 4),
                          const Text('Profile',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    _buildActionButton(
                      Icons.favorite_rounded,
                      const Color(0xFFFF2D55),
                      () => _handleSwipe(true),
                      size: 50,
                      label: 'Propose',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoMatchesView(MatchProvider provider) {
    return Center(
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
                  const Color(0xFFFF2D55).withValues(alpha: 0.15),
                  const Color(0xFFBF5AF2).withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFFF2D55).withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 44,
              color: Color(0xFFFF2D55),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No more matches',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check back later for new people nearby.',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          if (provider.canUndo)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GestureDetector(
                onTap: _handleUndo,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(Radius.circular(22)),
                    border:
                        Border.all(color: Colors.amber.withValues(alpha: 0.40)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.undo_rounded, color: Colors.amber, size: 18),
                      SizedBox(width: 6),
                      Text('Undo Last',
                          style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: provider.reset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                ),
                borderRadius: const BorderRadius.all(Radius.circular(26)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF2D55).withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Text(
                'Refresh',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    double size = 56,
    String label = '',
  }) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: isDisabled ? 0.65 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isDisabled ? 0.20 : 0.35),
                    color.withValues(alpha: isDisabled ? 0.08 : 0.18),
                  ],
                ),
                border: Border.all(
                  color: color.withValues(alpha: isDisabled ? 0.4 : 0.85),
                  width: 1.8,
                ),
                boxShadow: isDisabled
                    ? null
                    : [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: color.withValues(alpha: 0.20),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
              ),
              child: Icon(
                icon,
                color: color.withValues(alpha: isDisabled ? 0.5 : 1.0),
                size: size * 0.46,
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: isDisabled ? 0.3 : 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  NEARBY VIEW
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class NearbyView extends StatefulWidget {
  const NearbyView({super.key});

  @override
  State<NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<NearbyView> {
  final _api = ApiService();
  final Set<String> _blockedIds = {};
  final Map<String, bool> _following = {};
  final Map<String, bool> _loadingFollow = {};
  final Map<String, bool> _proposalSent = {};
  final Map<String, bool> _loadingProposal = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MatchProvider>();
      if (provider.nearbyUsers.isEmpty && !provider.isLoading) {
        provider.loadNearbyUsers();
      }
    });
  }

  (Color, String) _tier(double r) {
    if (r >= 9.0) return (const Color(0xFFFF9500), 'Legendary');
    if (r >= 7.5) return (const Color(0xFFBF5AF2), 'Elite');
    if (r >= 6.0) return (const Color(0xFF0A84FF), 'Premium');
    if (r >= 4.5) return (const Color(0xFF30D158), 'Popular');
    if (r >= 3.0) return (const Color(0xFFFF6B9D), 'Rising');
    return (const Color(0xFF8E8E93), 'New');
  }

  Future<void> _toggleFollow(MatchUser user) async {
    if (_loadingFollow[user.id] == true) return;
    setState(() => _loadingFollow[user.id] = true);
    final isFollowing = _following[user.id] ?? false;
    try {
      if (isFollowing) {
        await _api.unfollowUser(user.id);
      } else {
        await _api.followUser(user.id);
      }
      if (mounted) setState(() => _following[user.id] = !isFollowing);
    } catch (_) {}
    if (mounted) setState(() => _loadingFollow[user.id] = false);
  }

  Future<void> _sendProposal(BuildContext context, MatchUser user) async {
    if (_loadingProposal[user.id] == true || _proposalSent[user.id] == true)
      return;
    setState(() => _loadingProposal[user.id] = true);
    final scaffoldMsg = ScaffoldMessenger.of(context);
    try {
      final result = await _api.sendProposal(targetUserId: user.id);
      if (mounted) {
        setState(() => _proposalSent[user.id] = true);
        final msg = result['matched'] == true
            ? "It's a Match with ${user.name}! 💕"
            : 'Proposal sent to ${user.name}! 🌹';
        scaffoldMsg.showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFFFF6B9D),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14))),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString().toLowerCase().contains('already')
            ? 'Already sent to ${user.name} ❤️'
            : 'Error sending proposal';
        scaffoldMsg.showSnackBar(SnackBar(
          content: Text(errMsg, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF3A3A3C),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14))),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ));
      }
    }
    if (mounted) setState(() => _loadingProposal[user.id] = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MatchProvider>(context);
    final users =
        provider.nearbyUsers.where((u) => !_blockedIds.contains(u.id)).toList();

    return Column(
      children: [
        Expanded(
          child: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6B9D)))
              : users.isEmpty
                  ? const Center(
                      child: Text('No one nearby yet',
                          style: TextStyle(color: Color(0xFF8E8E93))))
                  : RefreshIndicator(
                      onRefresh: provider.loadNearbyUsers,
                      color: const Color(0xFFFF6B9D),
                      backgroundColor: const Color(0xFF1C1C1E),
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.62,
                        ),
                        itemCount: users.length,
                        itemBuilder: (ctx, i) => _buildGridCard(ctx, users[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, NearbySortMode mode) {
    final provider = Provider.of<MatchProvider>(context);
    final sel = provider.sortMode == mode;
    return GestureDetector(
      onTap: () => provider.setSortMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: sel
              ? const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFBF5AF2)])
              : null,
          color: sel ? null : const Color(0xFF1C1C1E),
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(
            color: sel ? Colors.transparent : const Color(0xFF2A2A3A),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: sel ? Colors.white : const Color(0xFF8E8E93),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }

  void _showNearbyPreview(BuildContext context, MatchUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NearbyUserPreviewScreen(
          user: user,
          proposalSent: _proposalSent[user.id] ?? false,
          onProposal: () => _sendProposal(context, user),
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, MatchUser user) {
    final proposalSent = _proposalSent[user.id] ?? false;
    final loadProposal = _loadingProposal[user.id] ?? false;
    final (tierColor, tierLabel) = _tier(user.rating);

    return GestureDetector(
      onTap: () => _showNearbyPreview(context, user),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: tierColor.withValues(alpha: 0.10),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo
              CachedNetworkImage(
                imageUrl: user.photoUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2D1B4E), Color(0xFF1A0530)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Color(0xFF4A3060), size: 48),
                ),
              ),
              // Gradient overlay
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.45, 1.0],
                      colors: [
                        Colors.transparent,
                        Color(0x55000000),
                        Color(0xEE0D0818),
                      ],
                    ),
                  ),
                ),
              ),
              // Online dot
              if (user.isOnline)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF30D158).withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              // Tier badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    border:
                        Border.all(color: tierColor.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    tierLabel,
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              // Bottom info
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${user.name}, ${user.age}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              size: 11, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              user.distanceKm != null
                                  ? Formatters.formatDistance(user.distanceKm)
                                  : user.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Icon(Icons.bolt_rounded,
                              size: 11, color: Color(0xFF00E5FF)),
                          Text(
                            '${user.matchPercent}%',
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Action row
                      Row(
                        children: [
                          // Ignore
                          GestureDetector(
                            onTap: () =>
                                setState(() => _blockedIds.add(user.id)),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white54, size: 16),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Propose
                          Expanded(
                            child: GestureDetector(
                              onTap: loadProposal || proposalSent
                                  ? null
                                  : () => _sendProposal(context, user),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: proposalSent
                                      ? null
                                      : const LinearGradient(colors: [
                                          Color(0xFFFF6B9D),
                                          Color(0xFFBF5AF2)
                                        ]),
                                  color: proposalSent
                                      ? const Color(0xFF1E8E5A)
                                      : null,
                                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                                ),
                                child: Center(
                                  child: loadProposal
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              proposalSent
                                                  ? Icons.check_rounded
                                                  : Icons.favorite_rounded,
                                              color: Colors.white,
                                              size: 13,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              proposalSent ? 'Sent' : 'Propose',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, MatchUser user) {
    final proposalSent = _proposalSent[user.id] ?? false;
    final loadProposal = _loadingProposal[user.id] ?? false;
    final (tierColor, tierLabel) = _tier(user.rating);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(30)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: tierColor.withValues(alpha: 0.12),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF221035), Color(0xFF120A20)],
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(30)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 420,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: user.photoUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2D1B4E), Color(0xFF1A0530)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Color(0xFF4A3060), size: 96),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.0, 0.35, 0.72, 1.0],
                            colors: [
                              Color(0x22000000),
                              Colors.transparent,
                              Color(0xA6000000),
                              Color(0xF1111117),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          if (user.isOnline)
                            _buildTopPill(
                              icon: Icons.circle,
                              label: 'Online',
                              color: const Color(0xFF30D158),
                            ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text(
                                '${user.name} — Rating: ${user.rating.toStringAsFixed(1)}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: const Color(0xFF1C1C1E),
                              behavior: SnackBarBehavior.floating,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(14))),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            )),
                            child: _buildTopPill(
                              icon: Icons.auto_awesome_rounded,
                              label:
                                  '${user.rating.toStringAsFixed(1)} • $tierLabel',
                              color: tierColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.all(Radius.circular(22)),
                          border: Border.all(
                            color:
                                const Color(0xFF00E5FF).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                color: Color(0xFF00E5FF), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${user.matchPercent}% Match',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${user.name}, ${user.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildInfoChip(
                                icon: Icons.location_on_rounded,
                                label: user.distanceKm != null
                                    ? '${Formatters.formatDistance(user.distanceKm)} away'
                                    : '${user.city}, ${user.country}',
                              ),
                              _buildInfoChip(
                                icon: user.gender == 'male'
                                    ? Icons.male_rounded
                                    : Icons.female_rounded,
                                label: user.gender.toUpperCase(),
                              ),
                              if (user.incomeStatus == 'verified' ||
                                  user.incomeStatus == 'approved')
                                _buildInfoChip(
                                  icon: Icons.verified_rounded,
                                  label: 'Income Verified',
                                  color: const Color(0xFF00E5FF),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.star_rounded,
                            label: 'Rating',
                            value: user.rating.toStringAsFixed(1),
                            color: const Color(0xFFFFC857),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.favorite_rounded,
                            label: 'Match',
                            value: '${user.matchPercent}%',
                            color: const Color(0xFFFF6B9D),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.public_rounded,
                            label: 'Location',
                            value: user.city,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildSection('Interests', user.interests.take(1).toList(),
                        const Color(0xFFFF6B9D)),
                    const SizedBox(height: 10),
                    _buildSection(
                        'Looking For',
                        user.lookingFor.take(1).toList(),
                        const Color(0xFF00E5FF)),
                    const SizedBox(height: 10),
                    _buildSection('Qualities', user.qualities.take(1).toList(),
                        const Color(0xFFBF5AF2)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            label: 'Ignore',
                            icon: Icons.close_rounded,
                            color: const Color(0xFF2A2A36),
                            borderColor: Colors.white.withValues(alpha: 0.10),
                            onTap: () => setState(() {
                              _blockedIds.add(user.id);
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _actionButton(
                            label: proposalSent
                                ? 'Proposal Sent'
                                : 'Send Proposal',
                            icon: proposalSent
                                ? Icons.check_rounded
                                : Icons.favorite_rounded,
                            color: proposalSent
                                ? const Color(0xFF1E8E5A)
                                : const Color(0xFFFF4D8D),
                            borderColor: proposalSent
                                ? const Color(0xFF30D158)
                                : const Color(0xFFFF7AAA),
                            loading: loadProposal,
                            onTap: () => _sendProposal(context, user),
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
      ),
    );
  }

  Widget _buildTopPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    Color color = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
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

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9B9BA7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<String> items, Color color) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Not added yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .take(6)
              .map(
                (item) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color borderColor,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  NEARBY PREVIEW SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _NearbyPreviewSheet extends StatelessWidget {
  final MatchUser user;
  final VoidCallback onProposal;
  final VoidCallback onViewProfile;

  const _NearbyPreviewSheet({
    required this.user,
    required this.onProposal,
    required this.onViewProfile,
  });

  (Color, String) _tier(double r) {
    if (r >= 9.0) return (const Color(0xFFFF9500), 'Legendary');
    if (r >= 7.5) return (const Color(0xFFBF5AF2), 'Elite');
    if (r >= 6.0) return (const Color(0xFF0A84FF), 'Premium');
    if (r >= 4.5) return (const Color(0xFF30D158), 'Popular');
    if (r >= 3.0) return (const Color(0xFFFF6B9D), 'Rising');
    return (const Color(0xFF8E8E93), 'New');
  }

  @override
  Widget build(BuildContext context) {
    final (tierColor, tierLabel) = _tier(user.rating);
    final interest = user.interests.isNotEmpty ? user.interests.first : null;
    final lookingFor =
        user.lookingFor.isNotEmpty ? user.lookingFor.first : null;
    final quality = user.qualities.isNotEmpty ? user.qualities.first : null;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          const SizedBox(
            width: 40,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF3A3A5C),
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Photo + name row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  child: CachedNetworkImage(
                    imageUrl: user.photoUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFF2D1B4E),
                      child: const Icon(Icons.person_rounded,
                          color: Color(0xFF4A3060), size: 36),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${user.name}, ${user.age}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (user.distanceKm != null) ...[
                            const Icon(Icons.location_on_rounded,
                                size: 12, color: Color(0xFF8E8E93)),
                            const SizedBox(width: 3),
                            Text(Formatters.formatDistance(user.distanceKm),
                                style: const TextStyle(
                                    color: Color(0xFF8E8E93), fontSize: 12)),
                            const SizedBox(width: 8),
                          ],
                          if (user.isOnline)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF30D158)
                                    .withValues(alpha: 0.15),
                                borderRadius: const BorderRadius.all(Radius.circular(8)),
                                border: Border.all(
                                    color: const Color(0xFF30D158)
                                        .withValues(alpha: 0.4)),
                              ),
                              child: const Text('Online',
                                  style: TextStyle(
                                      color: Color(0xFF30D158),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Rating badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [tierColor, tierColor.withValues(alpha: 0.7)]),
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Column(
                    children: [
                      Text(user.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text(tierLabel,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Info chips row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (interest != null)
                  Expanded(
                      child: _infoTile(
                    Icons.interests_rounded,
                    'Interest',
                    interest,
                    const Color(0xFFFF6B9D),
                  )),
                if (interest != null && (lookingFor != null || quality != null))
                  const SizedBox(width: 8),
                if (lookingFor != null)
                  Expanded(
                      child: _infoTile(
                    Icons.search_rounded,
                    'Looking For',
                    lookingFor,
                    const Color(0xFF00E5FF),
                  )),
                if (lookingFor != null && quality != null)
                  const SizedBox(width: 8),
                if (quality != null)
                  Expanded(
                      child: _infoTile(
                    Icons.auto_awesome_rounded,
                    'Quality',
                    quality,
                    const Color(0xFFBF5AF2),
                  )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onViewProfile,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_rounded,
                              color: Colors.white70, size: 16),
                          SizedBox(width: 6),
                          Text('View Profile',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onProposal();
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B9D), Color(0xFFBF5AF2)]),
                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF6B9D).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Send Proposal',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class RandomCallView extends StatefulWidget {
  const RandomCallView({super.key});

  @override
  State<RandomCallView> createState() => _RandomCallViewState();
}

class _RandomCallViewState extends State<RandomCallView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _searching = false;
  String? _errorMsg;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    // Cancel queue if still searching
    if (_searching) {
      SignalingService.instance.cancelRandomMatch();
    }
    super.dispose();
  }

  void _cancelSearch() {
    _pollTimer?.cancel();
    SignalingService.instance.cancelRandomMatch();
    if (mounted) {
      setState(() {
        _searching = false;
        _errorMsg = null;
      });
    }
  }

  /// When either side has 'Direct random video calls' disabled the server
  /// puts the call in 'handshake' state. Both users must explicitly tap
  /// Start before WebRTC begins. This method shows the confirm dialog,
  /// sends the accept/decline to the server, then polls until the partner
  /// also accepts (or declines / times out).
  Future<void> _runRandomHandshake(
    Map<String, dynamic> matchedUser,
    int callId,
    String callUuid,
  ) async {
    if (!mounted) return;
    setState(() => _searching = false);

    final name = matchedUser['name']?.toString() ??
        matchedUser['full_name']?.toString() ??
        'a stranger';

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A28),
        title: const Text('Start random call?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'You matched with $name. Tap Start to begin the call. Both of you must tap Start before the call connects.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start',
                style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    final signaling = SignalingService.instance;

    if (accepted != true) {
      // Notify server so partner sees declined immediately.
      try {
        await signaling.randomCallHandshake(
            callId: callId, decision: 'decline');
      } catch (_) {}
      if (mounted) {
        NeonToast.info(context, 'Call declined');
      }
      return;
    }

    // Send our accept, then poll for partner's decision.
    Map<String, dynamic>? myAccept;
    try {
      myAccept = await signaling.randomCallHandshake(
          callId: callId, decision: 'accept');
    } catch (_) {}

    if (myAccept != null && myAccept['handshake_status'] == 'connected') {
      // Partner already accepted earlier — go straight to the call.
      await _navigateToCall(matchedUser, callId, callUuid);
      return;
    }

    // Wait up to 30s for the partner.
    int polls = 0;
    final completer = Completer<String>();
    final pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      polls++;
      try {
        final status =
            await signaling.randomCallHandshakeStatus(callId: callId);
        final s = status?['handshake_status']?.toString() ?? 'waiting';
        if (s == 'connected' || s == 'declined') {
          timer.cancel();
          if (!completer.isCompleted) completer.complete(s);
          return;
        }
      } catch (_) {}
      if (polls > 15) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete('timeout');
      }
    });

    // Optional: show a small "waiting for partner" dialog
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A28),
          content: const Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(width: 16),
              Expanded(
                child: Text('Waiting for partner to accept...',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final outcome = await completer.future;
    pollTimer.cancel();
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (outcome == 'connected') {
      await _navigateToCall(matchedUser, callId, callUuid);
    } else if (outcome == 'declined') {
      if (mounted) NeonToast.info(context, 'Partner declined the call');
    } else {
      if (mounted) NeonToast.info(context, 'Partner did not respond in time');
      try {
        await signaling.randomCallHandshake(
            callId: callId, decision: 'decline');
      } catch (_) {}
    }
  }

  Future<void> _navigateToCall(
    Map<String, dynamic> matchedUser,
    int callId,
    String callUuid,
  ) async {
    // Ensure VideoCallManager is initialized before navigating
    final videoManager = VideoCallManager();
    if (videoManager.activeProvider == null) {
      final userId = UserPrefsCache.instance.userId ?? '';
      final profile = ProfileService.instance.currentProfileNotifier.value;
      final String userName;
      final pName = profile?.name;
      final pUser = profile?.username;
      if (pName != null && pName.isNotEmpty) {
        userName = pName;
      } else {
        userName = pUser ?? 'User';
      }
      await videoManager.initialize(
        currentUserId: userId,
        currentUserName: userName,
      );
    }

    final session = CallSession(
      id: callUuid,
      callerId: '',
      callerName: 'You',
      receiverId: matchedUser['id'].toString(),
      receiverName: matchedUser['name']?.toString() ??
          matchedUser['full_name']?.toString() ??
          'User',
      receiverAvatar: matchedUser['avatar']?.toString(),
      type: CallType.video,
      state: CallState.outgoing,
      isRandomCall: true,
    );

    if (mounted) {
      setState(() => _searching = false);
      final duration = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRTCCallScreen(
            callSession: session,
            isOutgoing: true,
            serverCallId: callId,
          ),
        ),
      );

      if (mounted && duration != null && duration is int && duration >= 0) {
        PostCallBottomSheet.show(context, session, Duration(seconds: duration));
      }
    }
  }

  Future<void> _startCall() async {
    // Check permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      setState(() {
        _searching = true;
        _errorMsg = null;
      });

      final signaling = SignalingService.instance;
      final result = await signaling.randomCallMatch(type: 'video');

      if (!mounted) return;

      if (result == null || result['status'] != 'success') {
        setState(() {
          _searching = false;
          _errorMsg = result?['message'] ?? 'Connection failed. Try again.';
        });
        return;
      }

      // Check if instantly matched (another user was already waiting)
      if (result['matched'] == true) {
        final matchedUser = result['matched_user'] as Map<String, dynamic>;
        final callId = result['call_id'] as int;
        final callUuid = result['call_uuid'] as String;
        final handshakeRequired = result['handshake_required'] == true;
        if (handshakeRequired) {
          await _runRandomHandshake(matchedUser, callId, callUuid);
        } else {
          await _navigateToCall(matchedUser, callId, callUuid);
        }
        return;
      }

      // Not matched yet â€” start polling every 2 seconds
      int pollCount = 0;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        pollCount++;
        if (!mounted || !_searching) {
          timer.cancel();
          return;
        }

        // Timeout after 30 polls (60 seconds)
        if (pollCount > 30) {
          timer.cancel();
          signaling.cancelRandomMatch();
          if (mounted) {
            setState(() {
              _searching = false;
              _errorMsg = 'No one available right now. Try again later.';
            });
          }
          return;
        }

        final pollResult = await signaling.pollRandomMatch();
        if (!mounted || !_searching) {
          timer.cancel();
          return;
        }

        if (pollResult != null && pollResult['matched'] == true) {
          timer.cancel();
          final matchedUser =
              pollResult['matched_user'] as Map<String, dynamic>;
          final callId = pollResult['call_id'] as int;
          final callUuid = pollResult['call_uuid'] as String;
          await _navigateToCall(matchedUser, callId, callUuid);
        } else if (pollResult != null && pollResult['expired'] == true) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _searching = false;
              _errorMsg = 'Search expired. Try again.';
            });
          }
        }
      });
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Permissions Required',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Camera and Microphone are needed for video calls.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Settings'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                return Transform.scale(
                  scale: _searching ? _pulseAnim.value : 1.0,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFF007F).withValues(alpha: 0.2),
                          const Color(0xFFD946EF).withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _searching
                            ? const Color(0xFFFF007F)
                            : const Color(0xFFFF007F).withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF007F,
                          ).withValues(alpha: _searching ? 0.4 : 0.2),
                          blurRadius: _searching ? 40 : 20,
                          spreadRadius: _searching ? 10 : 0,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _searching ? Icons.search : Icons.video_call_rounded,
                        size: 70,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            Text(
              _searching ? 'Finding someone...' : 'Start Random Call',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMsg ??
                  'Connect instantly with people nearby or around the world.',
              style: TextStyle(
                color: _errorMsg != null
                    ? const Color(0xFFFF6B6B)
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            if (_searching)
              ElevatedButton(
                onPressed: _cancelSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(30)),
                  ),
                ),
                child: const Text('Cancel'),
              )
            else
              ElevatedButton(
                onPressed: _startCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF007F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 18,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(30)),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0xFFFF007F).withValues(alpha: 0.5),
                ),
                child: const Text(
                  'Start Call',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
