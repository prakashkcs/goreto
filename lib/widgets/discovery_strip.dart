import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Horizontal discovery strip — shows "People you may know" or "Nearby friends".
///
/// Used in the home feed between stories and posts.
class DiscoveryStrip extends StatefulWidget {
  /// 'users' | 'nearby' | 'creators'
  final String type;
  final String title;
  final IconData icon;
  final Color accentColor;

  const DiscoveryStrip({
    super.key,
    required this.type,
    required this.title,
    required this.icon,
    required this.accentColor,
  });

  @override
  State<DiscoveryStrip> createState() => _DiscoveryStripState();
}

class _DiscoveryStripState extends State<DiscoveryStrip> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  final Set<String> _followed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      List<dynamic> result;
      switch (widget.type) {
        case 'nearby':
          result = await _api.getRecommendedNearby();
        case 'creators':
          result = await _api.getRecommendedCreators(limit: 12);
        default:
          result = await _api.getRecommendedUsers(limit: 12);
      }
      if (mounted) {
        setState(() {
          _users = result
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _follow(String userId) async {
    if (_followed.contains(userId)) return;
    setState(() => _followed.add(userId));
    try {
      await _api.followUser(userId);
    } catch (_) {
      if (mounted) setState(() => _followed.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildShimmer();
    }
    if (_users.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: widget.accentColor, size: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _users = [];
                    _loading = true;
                    _load();
                  }),
                  child: Text(
                    'Refresh',
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Horizontal card list
          SizedBox(
            height: 168,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _users.length,
              itemBuilder: (_, i) => _buildCard(_users[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> user) {
    final uid = (user['id'] ?? '').toString();
    final name = (user['name'] ?? '').toString();
    final username = (user['username'] ?? '').toString();
    final avatar = (user['avatar'] ?? '').toString();
    final mutual = (user['mutual_count'] ?? 0) as num;
    final distKm = (user['distance_km'] ?? -1) as num;
    final isFollowed = _followed.contains(uid);

    String subtitle = '';
    if (distKm >= 0) {
      subtitle = distKm < 1 ? 'Less than 1 km' : '${distKm.toStringAsFixed(1)} km away';
    } else if (mutual > 0) {
      subtitle = '$mutual mutual ${mutual == 1 ? 'friend' : 'friends'}';
    } else if (user.containsKey('followers_count')) {
      final fc = (user['followers_count'] as num).toInt();
      subtitle = fc > 0 ? '$fc follower${fc == 1 ? '' : 's'}' : '';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
      ),
      child: Container(
        width: 118,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            // Avatar
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ClipOval(
                child: avatar.isNotEmpty && avatar.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _initials(name),
                      )
                    : _initials(name),
              ),
            ),
            const SizedBox(height: 8),
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name.isNotEmpty ? name : '@$username',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    color: widget.accentColor.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            // Follow button
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: GestureDetector(
                onTap: isFollowed ? null : () => _follow(uid),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: isFollowed
                        ? null
                        : LinearGradient(
                            colors: [
                              widget.accentColor,
                              widget.accentColor.withValues(alpha: 0.7),
                            ],
                          ),
                    color: isFollowed
                        ? Colors.white.withValues(alpha: 0.08)
                        : null,
                    borderRadius: BorderRadius.circular(20),
                    border: isFollowed
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.2))
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      isFollowed ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: isFollowed ? Colors.white54 : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials(String name) => Container(
        color: widget.accentColor.withValues(alpha: 0.3),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      );

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 168,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 5,
          itemBuilder: (_, __) => Container(
            width: 118,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A28),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
