import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/widgets/login_required_sheet.dart';
import 'package:love_vibe_pro/widgets/neon_ui.dart';

/// Guest Main Screen - Allows browsing home feed but requires login for other tabs
/// Home: Works (read-only browsing)
/// Match/Message/Profile: Shows LoginRequiredSheet
class GuestMainScreen extends StatefulWidget {
  const GuestMainScreen({super.key});

  @override
  State<GuestMainScreen> createState() => _GuestMainScreenState();
}

class _GuestMainScreenState extends State<GuestMainScreen> {
  int _currentIndex = 0;

  void _onTabChange(int index) {
    // Home tab (index 0) is always accessible
    if (index == 0) {
      setState(() => _currentIndex = index);
      return;
    }

    // Other tabs require login
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated) {
      _showLoginRequired(index);
      return;
    }

    setState(() => _currentIndex = index);
  }

  void _showLoginRequired(int tabIndex) {
    String feature;
    switch (tabIndex) {
      case 1:
        feature = 'find matches and connect with people';
        break;
      case 2:
        feature = 'send messages and chat';
        break;
      case 3:
        feature = 'view and edit your profile';
        break;
      default:
        feature = 'use this feature';
    }

    LoginRequiredSheet.show(context, feature: feature);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiquidLoveTokens.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Background
            const LiquidBackgroundBlobs(),

            // Content
            IndexedStack(
              index: _currentIndex,
              children: [
                // Home - Always accessible (read-only)
                const HomeFeedGuestView(),

                // Match - Requires login
                _buildLockedTab(
                  icon: Icons.favorite_border_rounded,
                  title: 'Find Your Match',
                  subtitle: 'Discover people who share your vibe',
                  feature: 'find matches',
                ),

                // Messages - Requires login
                _buildLockedTab(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Messages',
                  subtitle: 'Connect with your matches',
                  feature: 'send messages',
                ),

                // Profile - Requires login
                _buildLockedTab(
                  icon: Icons.person_outline_rounded,
                  title: 'Your Profile',
                  subtitle: 'Customize your profile and settings',
                  feature: 'view and edit your profile',
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LiquidLoveTokens.glassCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: LiquidLoveTokens.accentPink.withValues(alpha: 0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_outlined, 0, 'Home'),
          _buildNavItem(Icons.favorite_border_rounded, 1, 'Match'),
          _buildNavItem(Icons.chat_bubble_outline_rounded, 2, 'Chat'),
          _buildNavItem(Icons.person_outline_rounded, 3, 'Profile'),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabChange(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? LiquidLoveTokens.accentPink : Colors.white54,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? LiquidLoveTokens.accentPink : Colors.white54,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedTab({
    required IconData icon,
    required String title,
    required String subtitle,
    required String feature,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.5),
          radius: 1.2,
          colors: [Color(0x4D2A0A3D), LiquidLoveTokens.background],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lock icon with glow
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    LiquidLoveTokens.accentPink.withValues(alpha: 0.2),
                    LiquidLoveTokens.accentCyan.withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: LiquidLoveTokens.accentPink.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                size: 45,
                color: LiquidLoveTokens.accentPink.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),

            // Login button
            SizedBox(
              width: 200,
              child: NeonButtonPrimary(
                text: 'Login to Access',
                onTap: () => LoginRequiredSheet.show(context, feature: feature),
              ),
            ),
            const SizedBox(height: 16),

            // Sign up prompt
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              child: Text(
                'Or create an account',
                style: TextStyle(
                  color: LiquidLoveTokens.accentCyan.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home Feed View for Guest Users
/// Shows the regular feed but with restricted actions (no like, comment, share)
class HomeFeedGuestView extends StatefulWidget {
  const HomeFeedGuestView({super.key});

  @override
  State<HomeFeedGuestView> createState() => _HomeFeedGuestViewState();
}

class _HomeFeedGuestViewState extends State<HomeFeedGuestView> {
  List<dynamic> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    // Load feed without requiring authentication
    try {
      final posts = await _fetchPostsAsGuest();
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<dynamic>> _fetchPostsAsGuest() async {
    // Mock posts for demo
    final response = await Future.delayed(
      const Duration(milliseconds: 500),
      () {
        return List.generate(
          10,
          (i) => {
            'id': i + 1,
            'caption': 'Post ${i + 1} - Guest view mode 🌟',
            'type': i % 3 == 0 ? 'video' : 'image',
            'file_url': 'https://picsum.photos/400/400?random=$i',
            'likes_count': (i + 1) * 15,
            'comments_count': (i + 1) * 3,
            'views_unique': (i + 1) * 120,
            'created_at':
                DateTime.now().subtract(Duration(hours: i)).toIso8601String(),
            'user': {
              'id': i + 100,
              'name': 'User ${i + 1}',
              'profile_pic': 'https://i.pravatar.cc/150?img=${i + 10}',
            },
          },
        );
      },
    );
    return response;
  }

  void _handleRestrictedAction(String action) {
    LoginRequiredSheet.show(context, feature: action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: LiquidLoveTokens.accentPink,
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.favorite,
                color: LiquidLoveTokens.accentPink,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  LiquidLoveTokens.accentPink,
                  LiquidLoveTokens.accentPurple,
                ],
              ).createShader(bounds),
              child: const Text(
                'Goreto',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Guest indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: LiquidLoveTokens.accentPink.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: LiquidLoveTokens.accentPink.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'Guest',
              style: TextStyle(
                color: LiquidLoveTokens.accentPink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LiquidLoveTokens.accentPink,
              ),
            )
          : RefreshIndicator(
              color: LiquidLoveTokens.accentPink,
              onRefresh: _loadFeed,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _posts.length + 1, // +1 for sign up prompt
                itemBuilder: (context, index) {
                  if (index == _posts.length) {
                    return _buildSignUpPrompt();
                  }
                  return _buildGuestPostCard(_posts[index]);
                },
              ),
            ),
    );
  }

  Widget _buildGuestPostCard(Map<String, dynamic> post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: LiquidLoveTokens.glassCard,
        borderRadius: BorderRadius.circular(LiquidLoveTokens.radiusCard),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(
                    post['user']?['profile_pic'] ?? '',
                  ),
                  backgroundColor: LiquidLoveTokens.glassCard,
                ),
                const SizedBox(width: 10),
                Text(
                  post['user']?['name'] ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${post['views_unique'] ?? 0} views',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Post image
          ClipRRect(
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                post['file_url'] ?? '',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: LiquidLoveTokens.glassCard,
                  child: const Icon(
                    Icons.image,
                    color: Colors.white24,
                    size: 50,
                  ),
                ),
              ),
            ),
          ),

          // Caption
          if (post['caption'] != null && post['caption'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                post['caption'],
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ),

          // Actions (locked for guests)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLockedAction(
                  Icons.favorite_border,
                  'Like',
                  () => _handleRestrictedAction('like posts'),
                ),
                _buildLockedAction(
                  Icons.chat_bubble_outline,
                  'Comment',
                  () => _handleRestrictedAction('comment on posts'),
                ),
                _buildLockedAction(
                  Icons.share_outlined,
                  'Share',
                  () => _handleRestrictedAction('share posts'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54, size: 22),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.lock, color: Colors.white24, size: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSignUpPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LiquidLoveTokens.accentPink.withValues(alpha: 0.1),
            LiquidLoveTokens.accentCyan.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: LiquidLoveTokens.accentPink.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.favorite,
            color: LiquidLoveTokens.accentPink,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'Enjoying Goreto?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an account to like, comment, match, and connect with amazing people!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: NeonButtonPrimary(
                  text: 'Sign Up',
                  onTap: () => LoginRequiredSheet.show(context),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: GlassButton(
                  text: 'Later',
                  isOutlined: true,
                  height: 50,
                  onTap: () {
                    final auth = Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    );
                    auth.enterGuestMode();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
