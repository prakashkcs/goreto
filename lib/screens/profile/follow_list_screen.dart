import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

class FollowListScreen extends StatefulWidget {
  final dynamic userId;
  final String type; // 'followers' or 'following'
  final String displayName;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.displayName,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final _api = ApiService();
  final _scrollController = ScrollController();

  final List<_FollowUser> _users = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _initialLoad = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final res = await _api.getFollowList(
      userId: widget.userId,
      type: widget.type,
      page: _page,
    );
    if (!mounted) return;
    if (res != null) {
      final list = (res['users'] as List? ?? [])
          .map((u) => _FollowUser.fromJson(u as Map<String, dynamic>))
          .toList();
      setState(() {
        _users.addAll(list);
        _hasMore = res['has_more'] == true;
        _page++;
        _loading = false;
        _initialLoad = false;
      });
    } else {
      setState(() {
        _loading = false;
        _initialLoad = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _users.clear();
      _page = 1;
      _hasMore = true;
      _initialLoad = true;
    });
    await _loadMore();
  }

  Future<void> _toggleFollow(_FollowUser user) async {
    final idx = _users.indexOf(user);
    if (idx == -1) return;
    setState(() => _users[idx] = user.copyWith(isFollowLoading: true));
    final res = user.isFollowing
        ? await _api.unfollowUser(user.id)
        : await _api.followUser(user.id);
    if (!mounted) return;
    if (res != null) {
      setState(() => _users[idx] = user.copyWith(
            isFollowing: !user.isFollowing,
            isFollowLoading: false,
          ));
    } else {
      setState(() => _users[idx] = user.copyWith(isFollowLoading: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0B14),
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.type == 'followers' ? 'Followers' : 'Following',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.displayName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _initialLoad
          ? _buildSkeletons()
          : _users.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: const Color(0xFFE91E8C),
                  backgroundColor: const Color(0xFF0D0B14),
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: _users.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => Divider(
                      color: Colors.white.withValues(alpha: 0.04),
                      height: 1,
                      indent: 72,
                      endIndent: 16,
                    ),
                    itemBuilder: (ctx, i) {
                      if (i == _users.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE91E8C),
                              ),
                            ),
                          ),
                        );
                      }
                      return _UserTile(
                        user: _users[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: _users[i].id.toString()),
                          ),
                        ),
                        onFollowTap: () => _toggleFollow(_users[i]),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildSkeletons() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 10,
      itemBuilder: (_, __) => const _SkeletonTile(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.type == 'followers' ? Icons.people_outline : Icons.person_add_outlined,
            size: 56,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            widget.type == 'followers' ? 'No followers yet' : 'Not following anyone',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final _FollowUser user;
  final VoidCallback onTap;
  final VoidCallback onFollowTap;

  const _UserTile({
    required this.user,
    required this.onTap,
    required this.onFollowTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: const Color(0xFFE91E8C).withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar with neon ring
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE91E8C), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E8C).withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0D0B14),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF1A1525),
                  backgroundImage: user.avatar.isNotEmpty
                      ? CachedNetworkImageProvider(user.avatar)
                      : null,
                  child: user.avatar.isEmpty
                      ? Text(
                          (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFE91E8C),
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Name + username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Follow button
            _FollowButton(
              isFollowing: user.isFollowing,
              isLoading: user.isFollowLoading,
              onTap: onFollowTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onTap;

  const _FollowButton({
    required this.isFollowing,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: isFollowing
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFE91E8C), Color(0xFF7C3AED)],
                ),
          color: isFollowing ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(20),
          border: isFollowing
              ? Border.all(color: Colors.white.withValues(alpha: 0.2))
              : null,
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFE91E8C),
                ),
              )
            : Text(
                isFollowing ? 'Following' : 'Follow',
                style: TextStyle(
                  color: isFollowing
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 11,
                  width: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUser {
  final dynamic id;
  final String name;
  final String username;
  final String avatar;
  final bool isFollowing;
  final bool isFollowLoading;

  const _FollowUser({
    required this.id,
    required this.name,
    required this.username,
    required this.avatar,
    required this.isFollowing,
    this.isFollowLoading = false,
  });

  factory _FollowUser.fromJson(Map<String, dynamic> j) => _FollowUser(
        id: j['id'],
        name: j['name']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        avatar: j['avatar']?.toString() ?? '',
        isFollowing: j['is_following'] == 1 || j['is_following'] == true,
      );

  _FollowUser copyWith({bool? isFollowing, bool? isFollowLoading}) => _FollowUser(
        id: id,
        name: name,
        username: username,
        avatar: avatar,
        isFollowing: isFollowing ?? this.isFollowing,
        isFollowLoading: isFollowLoading ?? this.isFollowLoading,
      );
}
