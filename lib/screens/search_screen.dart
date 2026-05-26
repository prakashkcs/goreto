import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';
import 'package:love_vibe_pro/screens/reels_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';

// ── URL helpers ────────────────────────────────────────────────────────────────

bool _isVideoUrl(String url) {
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.mkv');
}


// ── Screen ────────────────────────────────────────────────────────────────────

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  String _query = '';
  Timer? _debounce;

  List<dynamic> _people = [];
  List<dynamic> _posts = [];
  List<dynamic> _reels = [];
  List<dynamic> _trending = [];

  bool _loadingPeople = false;
  bool _loadingPosts = false;
  bool _loadingTrending = true;

  final List<Map<String, dynamic>> _categories = [
    {'label': '#love', 'icon': Icons.favorite_rounded, 'color': 0xFFFF295C},
    {'label': '#viral', 'icon': Icons.trending_up_rounded, 'color': 0xFFFF6B35},
    {'label': '#trending', 'icon': Icons.local_fire_department_rounded, 'color': 0xFFFF9500},
    {'label': '#reels', 'icon': Icons.movie_filter_rounded, 'color': 0xFFBF5AF2},
    {'label': '#fashion', 'icon': Icons.style_rounded, 'color': 0xFFFF2D55},
    {'label': '#music', 'icon': Icons.music_note_rounded, 'color': 0xFF0A84FF},
    {'label': '#travel', 'icon': Icons.flight_rounded, 'color': 0xFF30D158},
    {'label': '#food', 'icon': Icons.restaurant_rounded, 'color': 0xFFFF9F0A},
    {'label': '#fitness', 'icon': Icons.fitness_center_rounded, 'color': 0xFF64D2FF},
    {'label': '#beauty', 'icon': Icons.face_retouching_natural_rounded, 'color': 0xFFFF6EC7},
  ];

  // Cache for video thumbnails in the grid
  final Map<String, Uint8List?> _videoThumbCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _focusNode.addListener(() => setState(() {}));
    _loadTrending();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    try {
      final reels = await _api.getReels(type: 'trending');
      if (mounted) {
        setState(() {
          _trending = reels.take(18).toList();
          _loadingTrending = false;
        });
        _prefetchVideoThumbs(_trending);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTrending = false);
    }
  }

  void _prefetchVideoThumbs(List<dynamic> items) {
    for (final item in items) {
      final videoUrl =
          (item['file_url'] ?? item['video_url'] ?? '').toString().trim();
      if (videoUrl.isNotEmpty && _isVideoUrl(videoUrl)) {
        ThumbnailCache.instance.fetch(videoUrl).then((bytes) {
          if (mounted) setState(() => _videoThumbCache[videoUrl] = bytes);
        }).catchError((_) {});
      }
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _query = val.trim());
        if (_query.isNotEmpty) _runSearch();
      }
    });
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (q.isEmpty) return;

    setState(() {
      _loadingPeople = true;
      _loadingPosts = true;
      _people = [];
      _posts = [];
      _reels = [];
    });

    try {
      final users = await _api.searchUsers(q);
      if (mounted && _query == q) {
        setState(() { _people = users; _loadingPeople = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPeople = false);
    }

    try {
      final results = await _api.searchPosts(q);
      if (mounted && _query == q) {
        final videos = results.where((p) {
          final type = (p['type'] ?? '').toString().toLowerCase();
          final url = (p['file_url'] ?? p['video_url'] ?? '').toString();
          return type == 'video' || type == 'reel' || _isVideoUrl(url);
        }).toList();
        final photos = results.where((p) => !videos.contains(p)).toList();
        setState(() {
          _posts = photos;
          _reels = videos;
          _loadingPosts = false;
        });
        _prefetchVideoThumbs(videos);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _focusNode.unfocus();
    setState(() { _query = ''; _people = []; _posts = []; _reels = []; });
  }

  String _resolveAvatar(dynamic item) {
    final raw = (item['avatar'] ??
            item['avatar_url'] ??
            item['profile_pic'] ??
            item['user_avatar'] ??
            item['author_avatar'] ??
            '')
        .toString();
    return normalizeMediaUrl(raw, baseUrl: AppEnv.baseUrl, folder: 'profiles');
  }

  /// Returns an image-only URL for thumbnails — never a video file URL.
  String _resolveThumb(dynamic item) {
    final candidates = [
      item['thumbnail_url'],
      item['image_url'],
      item['media_url'],
      item['image'],
    ];
    for (final raw in candidates) {
      if (raw == null || raw.toString().isEmpty) continue;
      final url =
          normalizeMediaUrl(raw.toString(), baseUrl: AppEnv.baseUrl, folder: '');
      if (url.isEmpty) continue;
      // Skip anything that looks like a video file.
      if (_isVideoUrl(url)) continue;
      return url;
    }
    return '';
  }

  /// For video items: returns cached frame bytes if available.
  Uint8List? _videoThumb(dynamic item) {
    final url =
        (item['file_url'] ?? item['video_url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    return _videoThumbCache[url] ??
        ThumbnailCache.instance.get(url);
  }

  String _formatCount(dynamic val) {
    final n = int.tryParse(val?.toString() ?? '0') ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  void _openPost(dynamic item, {bool isVideo = false}) {
    final postId = (item['id'] ?? item['post_id'] ?? '').toString();
    if (postId.isEmpty) return;
    if (isVideo) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) =>
            ReelsScreen(initialPostId: postId, initialMode: ReelsFeedMode.reels),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId, initialPost: item),
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            if (_query.isNotEmpty) _buildTabBar(),
            Expanded(
              child: _query.isEmpty
                  ? _buildExplore()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPeopleResults(),
                        _buildGridResults(_posts, isReels: false),
                        _buildGridResults(_reels, isReels: true),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final focused = _focusNode.hasFocus || _query.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          if (focused)
            GestureDetector(
              onTap: _clearSearch,
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white70, size: 20),
              ),
            ),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF13131F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: focused
                      ? const Color(0xFFFF007F).withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFF007F).withValues(alpha: 0.18),
                          blurRadius: 20,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.search_rounded,
                    color: focused
                        ? const Color(0xFFFF007F)
                        : Colors.white.withValues(alpha: 0.35),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search people, posts, reels…',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(Icons.cancel_rounded,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      height: 40,
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFF007F), Color(0xFFBF5AF2)]),
          borderRadius: BorderRadius.circular(20),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        tabs: [
          _tab('People', _people.length, Icons.people_rounded),
          _tab('Posts', _posts.length, Icons.grid_view_rounded),
          _tab('Reels', _reels.length, Icons.movie_filter_rounded),
        ],
      ),
    );
  }

  Tab _tab(String label, int count, IconData icon) => Tab(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  count > 0 ? '$label ($count)' : label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  // ── Explore (no query) ─────────────────────────────────────────────────────

  Widget _buildExplore() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFFBF5AF2)],
                  ).createShader(r),
                  child: const Text(
                    'Discover',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Explore trending content',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        // Category chips
        SliverToBoxAdapter(
          child: SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final color = Color(cat['color'] as int);
                return GestureDetector(
                  onTap: () {
                    _searchCtrl.text = cat['label'] as String;
                    setState(() => _query = cat['label'] as String);
                    _runSearch();
                    _focusNode.unfocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: color.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat['icon'] as IconData, color: color, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          cat['label'] as String,
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // Section label
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Trending Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFFBF5AF2)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'For You',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Grid
        if (_loadingTrending)
          const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFFFF007F), strokeWidth: 2),
            ),
          )
        else if (_trending.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                'No trending content yet',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildTrendingCell(_trending[i], i),
                childCount: _trending.length,
              ),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 0.62,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTrendingCell(dynamic item, int index) {
    final imageThumb = _resolveThumb(item);
    final videoUrl =
        (item['file_url'] ?? item['video_url'] ?? '').toString().trim();
    final isVideo = _isVideoUrl(videoUrl) ||
        (item['type'] ?? '').toString().toLowerCase() == 'reel' ||
        (item['type'] ?? '').toString().toLowerCase() == 'video';
    final videoBytes = isVideo ? _videoThumb(item) : null;
    final likes = _formatCount(item['likes_count'] ?? item['likes'] ?? 0);

    Widget imageWidget;
    if (imageThumb.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageThumb,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _videoPlaceholder(isVideo),
      );
    } else if (videoBytes != null) {
      imageWidget = Image.memory(videoBytes, fit: BoxFit.cover);
    } else {
      imageWidget = _videoPlaceholder(isVideo);
    }

    return GestureDetector(
      onTap: () => _openPost(item, isVideo: isVideo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageWidget,
            // Bottom gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Video badge
            if (isVideo)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.play_circle_filled_rounded,
                    color: Colors.white, size: 20),
              ),
            // Likes
            Positioned(
              bottom: 6,
              left: 7,
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: Color(0xFFFF295C), size: 12),
                  const SizedBox(width: 3),
                  Text(
                    likes,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoPlaceholder(bool isVideo) {
    return Container(
      color: const Color(0xFF13131F),
      child: Center(
        child: Icon(
          isVideo ? Icons.play_circle_outline_rounded : Icons.image_outlined,
          color: Colors.white.withValues(alpha: 0.15),
          size: 32,
        ),
      ),
    );
  }

  // ── Search result grids ────────────────────────────────────────────────────

  Widget _buildGridResults(List<dynamic> items, {required bool isReels}) {
    if (_loadingPosts) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFFBF5AF2), strokeWidth: 2));
    }
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReels
                  ? Icons.movie_filter_outlined
                  : Icons.grid_view_rounded,
              color: Colors.white.withValues(alpha: 0.1),
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              isReels ? 'No reels found' : 'No posts found',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.65,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildGridCell(items[i], isReels: isReels),
    );
  }

  Widget _buildGridCell(dynamic item, {required bool isReels}) {
    final imageThumb = _resolveThumb(item);
    final videoUrl =
        (item['file_url'] ?? item['video_url'] ?? '').toString().trim();
    final isVideo = isReels || _isVideoUrl(videoUrl);
    final videoBytes = isVideo ? _videoThumb(item) : null;
    final likes = _formatCount(item['likes_count'] ?? item['likes'] ?? 0);

    Widget imageWidget;
    if (imageThumb.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageThumb,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _videoPlaceholder(isVideo),
      );
    } else if (videoBytes != null) {
      imageWidget = Image.memory(videoBytes, fit: BoxFit.cover);
    } else {
      imageWidget = _videoPlaceholder(isVideo);
    }

    return GestureDetector(
      onTap: () => _openPost(item, isVideo: isVideo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageWidget,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            if (isVideo)
              const Positioned(
                top: 5,
                right: 5,
                child: Icon(Icons.play_circle_filled_rounded,
                    color: Colors.white, size: 18),
              ),
            Positioned(
              bottom: 5,
              left: 6,
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: Color(0xFFFF295C), size: 11),
                  const SizedBox(width: 3),
                  Text(
                    likes,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── People results ─────────────────────────────────────────────────────────

  Widget _buildPeopleResults() {
    if (_loadingPeople) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFFFF007F), strokeWidth: 2));
    }
    if (_people.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded,
                color: Colors.white.withValues(alpha: 0.1), size: 56),
            const SizedBox(height: 12),
            Text(
              'No people found',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _people.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildPersonCard(_people[i]),
    );
  }

  Widget _buildPersonCard(dynamic user) {
    final userId = (user['id'] ?? user['user_id'] ?? '').toString();
    final name = (user['name'] ?? user['username'] ?? 'User').toString();
    final username = (user['username'] ?? '').toString();
    final bio = (user['bio'] ?? user['about'] ?? '').toString();
    final followers =
        _formatCount(user['followers_count'] ?? user['followers'] ?? 0);
    final posts = _formatCount(user['posts_count'] ?? user['posts'] ?? 0);
    final avatar = _resolveAvatar(user);

    return GestureDetector(
      onTap: () {
        if (userId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.07), width: 1),
        ),
        child: Row(
          children: [
            // Gradient avatar ring
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFF007F), Color(0xFFBF5AF2)],
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF1A1A2E),
                backgroundImage: avatar.isNotEmpty
                    ? CachedNetworkImageProvider(avatar)
                    : null,
                child: avatar.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 13),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12),
                    ),
                  if (bio.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        bio,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _statChip(Icons.people_rounded, followers, 'followers'),
                      const SizedBox(width: 8),
                      _statChip(Icons.grid_view_rounded, posts, 'posts'),
                    ],
                  ),
                ],
              ),
            ),
            // View button
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFFBF5AF2)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text(
                'View',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.35)),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
        ),
      ],
    );
  }
}
