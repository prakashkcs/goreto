import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../models/match_user.dart';
import '../../providers/match_provider.dart';
import '../../services/api_service.dart';
import '../../utils/formatters.dart';
import '../profile_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();

  // sort: 'closest' | 'top_rated' | 'newest' | 'online'
  String _sort = 'closest';

  // Per-user state
  final Map<String, bool> _following = {};
  final Map<String, bool> _proposalSent = {};
  final Map<String, bool> _loadingFollow = {};
  final Map<String, bool> _loadingProposal = {};

  late AnimationController _headerAnim;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerAnim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MatchProvider>().loadNearbyUsers();
    });
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  List<MatchUser> _sorted(List<MatchUser> users) {
    final list = List<MatchUser>.from(users);
    switch (_sort) {
      case 'top_rated':
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case 'newest':
        list.sort((a, b) => b.id.compareTo(a.id));
      case 'online':
        list.sort((a, b) {
          if (a.isOnline == b.isOnline) return 0;
          return a.isOnline ? -1 : 1;
        });
      default: // closest
        list.sort((a, b) {
          final da = double.tryParse(a.distanceKm ?? '9999') ?? 9999;
          final db = double.tryParse(b.distanceKm ?? '9999') ?? 9999;
          return da.compareTo(db);
        });
    }
    return list;
  }

  Future<void> _toggleFollow(MatchUser user) async {
    final id = user.id;
    if (_loadingFollow[id] == true) return;
    setState(() => _loadingFollow[id] = true);
    final isFollowing = _following[id] ?? false;
    try {
      if (isFollowing) {
        await _api.unfollowUser(id);
      } else {
        await _api.followUser(id);
      }
      if (mounted) setState(() => _following[id] = !isFollowing);
    } catch (_) {}
    if (mounted) setState(() => _loadingFollow[id] = false);
  }

  Future<void> _sendProposal(MatchUser user) async {
    final id = user.id;
    if (_loadingProposal[id] == true || _proposalSent[id] == true) return;
    setState(() => _loadingProposal[id] = true);
    try {
      await _api.sendProposal(targetUserId: id);
      if (mounted) {
        setState(() => _proposalSent[id] = true);
        _showToast('Proposal sent to ${user.name}!', const Color(0xFFE91E63));
      }
    } catch (e) {
      if (mounted)
        _showToast(e.toString().replaceAll('Exception: ', ''), Colors.red);
    }
    if (mounted) setState(() => _loadingProposal[id] = false);
  }

  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      body: Consumer<MatchProvider>(
        builder: (context, provider, _) {
          final users = _sorted(provider.nearbyUsers);
          return CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(child: _buildSortBar()),
              if (provider.isLoading)
                const SliverFillRemaining(child: _LoadingGrid())
              else if (users.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _NearbyCard(
                        user: users[i],
                        isFollowing: _following[users[i].id] ?? false,
                        proposalSent: _proposalSent[users[i].id] ?? false,
                        loadingFollow: _loadingFollow[users[i].id] ?? false,
                        loadingProposal: _loadingProposal[users[i].id] ?? false,
                        onFollow: () => _toggleFollow(users[i]),
                        onProposal: () => _sendProposal(users[i]),
                        onProfile: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(userId: users[i].id)),
                        ),
                        onRatingTap: () => _showRatingSheet(context, users[i]),
                      ),
                      childCount: users.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 110,
      backgroundColor: const Color(0xFF060610),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A0530), Color(0xFF060610)],
            ),
          ),
          child: FadeTransition(
            opacity: _headerFade,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 10),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      colors: [Color(0xFFFF6B9D), Color(0xFFBF5AF2)],
                    ).createShader(r),
                    child: const Text(
                      'Nearby',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.location_on_rounded,
                      color: Color(0xFFFF6B9D), size: 22),
                  const Spacer(),
                  _buildRefreshButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return GestureDetector(
      onTap: () => context.read<MatchProvider>().loadNearbyUsers(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B9D), Color(0xFFBF5AF2)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildSortBar() {
    final options = [
      ('closest', Icons.near_me_rounded, 'Closest'),
      ('top_rated', Icons.star_rounded, 'Top Rated'),
      ('online', Icons.circle, 'Online'),
      ('newest', Icons.access_time_rounded, 'Newest'),
    ];
    return Container(
      height: 46,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: const BouncingScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, icon, label) = options[i];
          final selected = _sort == key;
          return GestureDetector(
            onTap: () => setState(() => _sort = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFFFF6B9D), Color(0xFFBF5AF2)])
                    : null,
                color: selected ? null : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      selected ? Colors.transparent : const Color(0xFF2A2A4A),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: key == 'online' ? 9 : 15,
                      color: selected ? Colors.white : const Color(0xFF8E8E93)),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF8E8E93),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRatingSheet(BuildContext context, MatchUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RatingDetailSheet(user: user, api: _api),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEARBY CARD
// ─────────────────────────────────────────────────────────────────────────────
class _NearbyCard extends StatelessWidget {
  final MatchUser user;
  final bool isFollowing;
  final bool proposalSent;
  final bool loadingFollow;
  final bool loadingProposal;
  final VoidCallback onFollow;
  final VoidCallback onProposal;
  final VoidCallback onProfile;
  final VoidCallback onRatingTap;

  const _NearbyCard({
    required this.user,
    required this.isFollowing,
    required this.proposalSent,
    required this.loadingFollow,
    required this.loadingProposal,
    required this.onFollow,
    required this.onProposal,
    required this.onProfile,
    required this.onRatingTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onProfile,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPhoto(),
            _buildGradient(),
            _buildOnlineDot(),
            _buildContent(),
            _buildRatingBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    return CachedNetworkImage(
      imageUrl: user.photoUrl,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF2D1B4E),
              const Color(0xFF1A0530),
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.person_rounded, color: Color(0xFF4A3060), size: 60),
        ),
      ),
    );
  }

  Widget _buildGradient() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.35, 0.65, 1.0],
            colors: [
              Colors.transparent,
              Color(0x66000000),
              Color(0xEE000000),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineDot() {
    if (!user.isOnline) return const SizedBox.shrink();
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF30D158),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF30D158).withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: Colors.white, size: 6),
            SizedBox(width: 4),
            Text('LIVE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingBadge() {
    final (color, tier) = _tierInfo(user.rating);
    return Positioned(
      top: 10,
      right: 10,
      child: GestureDetector(
        onTap: onRatingTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.9), color],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 10),
              const SizedBox(width: 3),
              Text(
                user.rating.toStringAsFixed(1),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, String) _tierInfo(double rating) {
    if (rating >= 9.0) return (const Color(0xFFFF9500), 'Legendary');
    if (rating >= 7.5) return (const Color(0xFFBF5AF2), 'Elite');
    if (rating >= 6.0) return (const Color(0xFF0A84FF), 'Premium');
    if (rating >= 4.5) return (const Color(0xFF30D158), 'Popular');
    if (rating >= 3.0) return (const Color(0xFFFF6B9D), 'Rising');
    return (const Color(0xFF8E8E93), 'New');
  }

  Widget _buildContent() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${user.name.split(' ').first}, ${user.age}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (user.distanceKm != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: Color(0xFF8E8E93), size: 11),
                  const SizedBox(width: 2),
                  Text(
                    Formatters.formatDistance(user.distanceKm),
                    style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionBtn(
                  icon: isFollowing
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFollowing ? const Color(0xFFFF4569) : Colors.white,
                  loading: loadingFollow,
                  onTap: onFollow,
                ),
                const SizedBox(width: 6),
                _ActionBtn(
                  icon: proposalSent
                      ? Icons.check_rounded
                      : Icons.card_giftcard_rounded,
                  color: proposalSent
                      ? const Color(0xFF30D158)
                      : const Color(0xFFFF6B9D),
                  loading: loadingProposal,
                  onTap: onProposal,
                ),
                const SizedBox(width: 6),
                _ActionBtn(
                  icon: Icons.person_rounded,
                  color: const Color(0xFFBF5AF2),
                  loading: false,
                  onTap: onProfile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(8),
                child:
                    CircularProgressIndicator(strokeWidth: 1.5, color: color))
            : Icon(icon, color: color, size: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RATING DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────
class RatingDetailSheet extends StatefulWidget {
  final MatchUser user;
  final ApiService api;

  const RatingDetailSheet({super.key, required this.user, required this.api});

  @override
  State<RatingDetailSheet> createState() => RatingDetailSheetState();
}

class RatingDetailSheetState extends State<RatingDetailSheet>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.fetchUserQuality(widget.user.id);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
        _anim.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A5C),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          _buildHeader(),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                  color: Color(0xFFBF5AF2), strokeWidth: 2),
            )
          else if (_data != null)
            _buildBody()
          else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Unable to load rating',
                  style: TextStyle(color: Color(0xFF8E8E93))),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final rating = _data?['rating'] as double? ?? widget.user.rating;
    final tier = _data?['tier'] as String? ?? _tierLabel(rating);
    final tierColor = _tierColor(rating);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Avatar
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: widget.user.photoUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: const Color(0xFF2D1B4E),
                child:
                    const Icon(Icons.person_rounded, color: Color(0xFF4A3060)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          tierColor,
                          tierColor.withValues(alpha: 0.7)
                        ]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(tier,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Big score dial
          _ScoreDial(score: rating, color: tierColor, anim: _anim),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final breakdown =
        Map<String, dynamic>.from(_data?['score_breakdown'] as Map? ?? {});

    final factors = [
      _Factor('Followers', 'icons', breakdown['followers'] ?? 0.0, 2.0,
          Icons.people_rounded, const Color(0xFFBF5AF2)),
      _Factor('Proposals Recv', 'icons', breakdown['proposals'] ?? 0.0, 1.5,
          Icons.favorite_rounded, const Color(0xFFFF6B9D)),
      _Factor('Post Reach', 'icons', breakdown['engagement'] ?? 0.0, 1.5,
          Icons.bar_chart_rounded, const Color(0xFF0A84FF)),
      _Factor('KYC Verified', 'icons', breakdown['kyc'] ?? 0.0, 1.0,
          Icons.verified_rounded, const Color(0xFF30D158)),
      _Factor('Activity', 'icons', breakdown['activity'] ?? 0.0, 1.0,
          Icons.bolt_rounded, const Color(0xFFFF9500)),
      _Factor('Income Verify', 'icons', breakdown['income'] ?? 0.0, 0.5,
          Icons.account_balance_rounded, const Color(0xFF64D2FF)),
      _Factor('Gifts Rcvd', 'icons', breakdown['gifts'] ?? 0.0, 0.5,
          Icons.card_giftcard_rounded, const Color(0xFFFF375F)),
      _Factor('Live Streams', 'icons', breakdown['live'] ?? 0.0, 0.5,
          Icons.wifi_tethering_rounded, const Color(0xFFFF453A)),
      _Factor('Posts', 'icons', breakdown['posts'] ?? 0.0, 0.5,
          Icons.grid_on_rounded, const Color(0xFFFF9500)),
      _Factor('Profile', 'icons', breakdown['profile'] ?? 0.0, 0.5,
          Icons.person_rounded, const Color(0xFFBF5AF2)),
      _Factor('Desirability', 'icons', breakdown['desirability'] ?? 0.0, 0.5,
          Icons.auto_awesome_rounded, const Color(0xFFFFCC00)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quality Score Breakdown',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Score grows slowly — harder to earn at higher levels.',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...factors.map((f) => _FactorRow(factor: f, anim: _anim)),
          const SizedBox(height: 20),
          _buildStatsRow(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final cells = [
      (
        '${_data?['followers'] ?? 0}',
        'Followers',
        Icons.people_rounded,
        const Color(0xFFBF5AF2)
      ),
      (
        '${_data?['total_proposals'] ?? 0}',
        'Proposals',
        Icons.favorite_rounded,
        const Color(0xFFFF6B9D)
      ),
      (
        '${_data?['post_count'] ?? 0}',
        'Posts',
        Icons.grid_on_rounded,
        const Color(0xFF0A84FF)
      ),
      (
        '${_data?['total_engagement'] ?? 0}',
        'Likes',
        Icons.thumb_up_rounded,
        const Color(0xFF30D158)
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161625),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Row(
        children: cells
            .map((c) => Expanded(
                  child: Column(
                    children: [
                      Icon(c.$3, color: c.$4, size: 18),
                      const SizedBox(height: 4),
                      Text(c.$1,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(c.$2,
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 10)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  String _tierLabel(double r) {
    if (r >= 9.0) return 'Legendary';
    if (r >= 7.5) return 'Elite';
    if (r >= 6.0) return 'Premium';
    if (r >= 4.5) return 'Popular';
    if (r >= 3.0) return 'Rising';
    return 'New';
  }

  Color _tierColor(double r) {
    if (r >= 9.0) return const Color(0xFFFF9500);
    if (r >= 7.5) return const Color(0xFFBF5AF2);
    if (r >= 6.0) return const Color(0xFF0A84FF);
    if (r >= 4.5) return const Color(0xFF30D158);
    if (r >= 3.0) return const Color(0xFFFF6B9D);
    return const Color(0xFF8E8E93);
  }
}

class _Factor {
  final String label;
  final String type;
  final double score;
  final double maxScore;
  final IconData icon;
  final Color color;
  _Factor(
      this.label, this.type, dynamic raw, this.maxScore, this.icon, this.color)
      : score = (raw is num ? raw.toDouble() : 0.0);
}

class _FactorRow extends StatelessWidget {
  final _Factor factor;
  final AnimationController anim;

  const _FactorRow({required this.factor, required this.anim});

  @override
  Widget build(BuildContext context) {
    final pct = factor.maxScore > 0
        ? (factor.score / factor.maxScore).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: factor.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(factor.icon, color: factor.color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(factor.label,
                        style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      '${factor.score.toStringAsFixed(2)} / ${factor.maxScore.toStringAsFixed(1)}',
                      style: TextStyle(
                          color: factor.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: anim,
                  builder: (_, __) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct * anim.value,
                        minHeight: 5,
                        backgroundColor: const Color(0xFF2A2A4A),
                        valueColor: AlwaysStoppedAnimation<Color>(factor.color),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED SCORE DIAL (circular progress)
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreDial extends StatelessWidget {
  final double score;
  final Color color;
  final AnimationController anim;

  const _ScoreDial(
      {required this.score, required this.color, required this.anim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        return SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(
            painter: _DialPainter(
              progress: (score / 10.0) * anim.value,
              color: color,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    score.toStringAsFixed(1),
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '/ 10',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  final double progress;
  final Color color;

  _DialPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bgPaint = Paint()
      ..color = const Color(0xFF2A2A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final fgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi * progress,
        colors: [color.withValues(alpha: 0.5), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING / EMPTY STATES
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => _ShimmerCard(),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.3 + 0.3 * _anim.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
              color: Color.lerp(
                  const Color(0xFF1A1A2E), const Color(0xFF2A2A4E), opacity)),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D1B4E), Color(0xFF1A0530)],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.location_searching_rounded,
                color: Color(0xFFBF5AF2), size: 44),
          ),
          const SizedBox(height: 24),
          const Text('No one nearby',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Enable location to find people\naround you.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF8E8E93), fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
