import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/screens/live/live_room_screen.dart';
import 'package:love_vibe_pro/screens/live/live_preview_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';
import 'package:love_vibe_pro/services/engagement_tracker.dart';
import 'package:love_vibe_pro/screens/video_recorder_screen.dart';

import 'package:love_vibe_pro/widgets/reels_video_player.dart';
import 'package:love_vibe_pro/widgets/share_bottom_sheet.dart';
import 'package:love_vibe_pro/screens/gifts/gifts_sheet.dart';
import 'package:love_vibe_pro/widgets/gift_overlay_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/services/eye_blink_service.dart';
import 'package:love_vibe_pro/services/settings_store.dart';

enum ReelsFeedMode { reels, live }

class ReelsScreen extends StatefulWidget {
  final dynamic initialPostId;
  final int? initialIndex;
  final VoidCallback? onBack;
  final ReelsFeedMode initialMode;

  const ReelsScreen({
    super.key,
    this.initialPostId,
    this.initialIndex,
    this.onBack,
    this.initialMode = ReelsFeedMode.reels,
  });

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen>
    with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final PageController _pageController = PageController();

  VideoPlayerController? _currentController;
  int? _currentControllerIndex;

  late TabController _tabController;
  // Tab indices: 0 = Live, 1 = Following, 2 = For You
  static const int _kTabLive = 0;
  static const int _kTabFollowing = 1;
  static const int _kTabForYou = 2;

  List<dynamic> _forYouReels = [];
  List<dynamic> _followingReels = [];
  bool _isLoading = true;
  bool _isForYou = true;
  int _currentIndex = 0;
  late ReelsFeedMode _mode;

  final Set<String> _likedReelIds = {};
  final Set<String> _followedUserIds = {};
  final Set<String> _fetchedFollowUserIds = {}; // Track fetched state
  String? _currentUserId;

  final EngagementTracker _tracker = EngagementTracker();
  DateTime? _reelStartedAt;
  final Set<int> _autoAdvancedIndices = {};

  bool _blinkEnabled = false;

  List<dynamic> get _activeReels => _isForYou ? _forYouReels : _followingReels;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;

    final initialTab = _mode == ReelsFeedMode.live ? _kTabLive : _kTabForYou;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialTab,
    );
    _tabController.addListener(_onTabChanged);

    _loadCurrentUserId();
    if (_mode == ReelsFeedMode.reels) {
      _fetchForYouReels();
    } else {
      _isLoading = false;
    }

    _initBlinkService();
  }

  Future<void> _initBlinkService() async {
    final store = await SettingsStore.getInstance();
    final enabled = await store.getEyeBlinkScrollEnabled();
    if (!enabled || !mounted) return;

    final svc = EyeBlinkService.instance;
    svc.closedThreshold = await store.getBlinkClosedThreshold();
    svc.openThreshold   = await store.getBlinkOpenThreshold();
    svc.cooldownMs      = await store.getBlinkCooldownMs();
    svc.doubleWindowMs  = await store.getBlinkDoubleWindowMs();

    final started = await svc.start(
      onSingleBlink: _blinkNext,
      onDoubleBlink: _blinkPrev,
    );
    if (mounted) setState(() => _blinkEnabled = started);
  }

  void _blinkNext() {
    if (!mounted || !_pageController.hasClients) return;
    final next = _currentIndex + 1;
    if (next < _activeReels.length) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _blinkPrev() {
    if (!mounted || !_pageController.hasClients) return;
    final prev = _currentIndex - 1;
    if (prev >= 0) {
      _pageController.animateToPage(
        prev,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _loadCurrentUserId() {
    _currentUserId = UserPrefsCache.instance.userId;
  }

  bool _isOwnReel(dynamic reel) {
    if (_currentUserId == null) return false;
    final ownerId = (reel['user_id'] ?? reel['user']?['id'] ?? '').toString();
    return ownerId == _currentUserId;
  }

  bool _hasCustomSound(dynamic reel) {
    final sn = reel['sound_name'] ?? reel['audio_name'] ?? reel['music_name'];
    return sn != null && sn.toString().trim().isNotEmpty;
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    _disposeCurrentControllerCache();
    final idx = _tabController.index;
    setState(() {
      if (idx == _kTabLive) {
        _mode = ReelsFeedMode.live;
        _isLoading = false;
        _liveFetched = false; // allow fresh fetch every time live tab is opened
      } else if (idx == _kTabFollowing) {
        _mode = ReelsFeedMode.reels;
        _isForYou = false;
        _currentIndex = 0;
      } else {
        _mode = ReelsFeedMode.reels;
        _isForYou = true;
        _currentIndex = 0;
      }
    });

    if (idx == _kTabFollowing) {
      _fetchFollowingReels();
    } else if (idx == _kTabForYou) {
      if (_forYouReels.isEmpty) {
        _fetchForYouReels();
      } else {
        _jumpToIndex(0);
      }
    }
  }


  Future<void> _fetchForYouReels() async {
    setState(() => _isLoading = true);
    try {
      final reels = await _apiService.getReels(type: 'trending');
      if (!mounted) return;

      setState(() {
        _forYouReels = reels;
        for (final r in reels) {
          final isFollowing = r['is_following'] == true ||
              r['is_following'] == 1 ||
              r['is_following'] == '1';
          if (isFollowing) {
            final uid = (r['user_id'] ?? r['user']?['id'] ?? '').toString();
            if (uid.isNotEmpty) _followedUserIds.add(uid);
          }
        }
        _isLoading = false;
      });
      _jumpToInitialReel();
      _checkFollowStatusForCurrentReel();
      _recordViewForCurrentReel();
      _prefetchThumbnails(reels);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _prefetchThumbnails(List<dynamic> reels) {
    final videoUrlsForExtraction = <String>[];

    for (final r in reels) {
      final thumbUrl = (r['thumbnail_url'] ?? '').toString().trim();
      final videoUrl = (r['file_url'] ?? r['video_url'] ?? '').toString().trim();

      if (thumbUrl.isNotEmpty && thumbUrl.startsWith('http')) {
        // Network thumbnail — push into Flutter's ImageCache so it's ready
        // before the reel is ever scrolled to.
        precacheImage(NetworkImage(thumbUrl), context).catchError((_) {});
      } else if (videoUrl.isNotEmpty) {
        // No stored thumbnail — queue frame extraction from the video file.
        videoUrlsForExtraction.add(videoUrl);
      }
    }

    // ThumbnailCache deduplicates concurrent requests for the same URL.
    ThumbnailCache.instance.preload(videoUrlsForExtraction);
  }

  Future<void> _fetchFollowingReels() async {
    if (_followingReels.isNotEmpty) return;

    setState(() => _isLoading = true);
    try {
      final reels = await _apiService.getFollowingReels();
      if (!mounted) return;
      setState(() {
        _followingReels = reels;
        for (final r in reels) {
          final uid = (r['user_id'] ?? r['user']?['id'] ?? '').toString();
          if (uid.isNotEmpty) _followedUserIds.add(uid);
        }
        _isLoading = false;
      });
      _currentIndex = 0;
      _jumpToIndex(0);
      _checkFollowStatusForCurrentReel();
      _recordViewForCurrentReel();
      _prefetchThumbnails(reels);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _jumpToInitialReel() {
    if (_activeReels.isEmpty) return;

    int targetIndex = 0;
    if (widget.initialPostId != null) {
      final match = _activeReels.indexWhere(
        (item) =>
            (item['id'] ?? item['post_id']).toString() ==
            widget.initialPostId.toString(),
      );
      if (match >= 0) {
        targetIndex = match;
      }
    } else if (widget.initialIndex != null &&
        widget.initialIndex! >= 0 &&
        widget.initialIndex! < _activeReels.length) {
      targetIndex = widget.initialIndex!;
    }

    _currentIndex = targetIndex;
    _jumpToIndex(targetIndex);
  }

  void _jumpToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(index);
    });
  }

  void _disposeCurrentControllerCache() {
    final controller = _currentController;
    if (controller != null) {
      try {
        controller.pause();
      } catch (_) {}
      try {
        controller.dispose();
      } catch (_) {}
    }
    _currentController = null;
    _currentControllerIndex = null;
  }

  void _autoAdvanceToNext(int fromIndex) {
    if (!mounted) return;
    if (_autoAdvancedIndices.contains(fromIndex)) return;
    _autoAdvancedIndices.add(fromIndex);
    final nextIndex = fromIndex + 1;
    if (nextIndex < _activeReels.length) {
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handlePageChanged(int index) {
    if (index == _currentIndex) return;

    // Flush watch-time for the reel we're leaving
    _flushWatchTime(_currentIndex);

    // Critical hardware fix: dispose before moving to next reel.
    _disposeCurrentControllerCache();

    if (mounted) {
      setState(() => _currentIndex = index);
      _checkFollowStatusForCurrentReel();
      _recordViewForCurrentReel();
    }
  }

  Future<void> _checkFollowStatusForCurrentReel() async {
    if (_activeReels.isEmpty || _currentIndex >= _activeReels.length) return;
    final reel = _activeReels[_currentIndex];
    final userId = (reel['user_id'] ?? reel['user']?['id'] ?? '').toString();

    if (userId.isEmpty || userId == _currentUserId) return;
    if (_fetchedFollowUserIds.contains(userId)) return;

    _fetchedFollowUserIds.add(userId);

    try {
      final status = await _apiService.getFollowStatus(userId);
      if (status != null && mounted) {
        final isFollowing =
            status['is_following'] == true || status['following'] == true;
        setState(() {
          if (isFollowing) {
            _followedUserIds.add(userId);
          } else {
            _followedUserIds.remove(userId);
          }
        });
      }
    } catch (_) {}
  }

  void _handleBack() {
    EyeBlinkService.instance.stop();
    _disposeCurrentControllerCache();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    widget.onBack?.call();
  }

  void _recordViewForCurrentReel() {
    if (_activeReels.isEmpty || _currentIndex >= _activeReels.length) return;
    final reel = _activeReels[_currentIndex];
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (postId.isNotEmpty) {
      _apiService.recordView(postId);
    }
    _reelStartedAt = DateTime.now();
    _tracker.recordImpression(reel);
  }

  void _flushWatchTime(int fromIndex) {
    if (_activeReels.isEmpty || fromIndex >= _activeReels.length) return;
    final start = _reelStartedAt;
    if (start == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    final reel = _activeReels[fromIndex];
    if (seconds < 2) {
      _tracker.recordSkip(reel);
    } else {
      _tracker.recordWatchTime(reel, seconds);
    }
    _reelStartedAt = null;
  }

  @override
  void deactivate() {
    _disposeCurrentControllerCache();
    super.deactivate();
  }


  bool _isReelLiked(dynamic reel) {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (_likedReelIds.contains(postId)) return true;
    return reel['is_liked'] == true || reel['is_liked'] == 1;
  }

  Future<void> _handleLike(
    dynamic reel, {
    bool withSound = true,
    bool fromDoubleTap = false,
  }) async {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (postId.isEmpty) return;

    final alreadyLiked = _isReelLiked(reel);

    // Double-tap: only like, never unlike
    if (fromDoubleTap && alreadyLiked) return;

    if (withSound) {
      await SoundService().playReact();
    }

    // Optimistic UI update
    setState(() {
      if (alreadyLiked) {
        _likedReelIds.remove(postId);
        reel['is_liked'] = false;
        final count = int.tryParse(
              (reel['likes_count'] ?? reel['likes'] ?? 0).toString(),
            ) ??
            0;
        reel['likes_count'] = (count - 1).clamp(0, 9999999);
      } else {
        _likedReelIds.add(postId);
        reel['is_liked'] = true;
        final count = int.tryParse(
              (reel['likes_count'] ?? reel['likes'] ?? 0).toString(),
            ) ??
            0;
        reel['likes_count'] = count + 1;
      }
    });

    // Track engagement
    if (!alreadyLiked) _tracker.recordInteraction(reel, action: 'like');

    // Confirm with server
    final result = await _apiService.likePostToggle(postId);
    if (mounted) {
      setState(() {
        // Parse liked field robustly â€” server may return bool, int, or string
        final rawLiked = result['liked'];
        final serverLiked = rawLiked == true ||
            rawLiked == 1 ||
            rawLiked == '1' ||
            (rawLiked == null ? _isReelLiked(reel) : false);
        if (serverLiked) {
          _likedReelIds.add(postId);
        } else {
          _likedReelIds.remove(postId);
        }
        reel['is_liked'] = serverLiked;
        // Update count only when server returns a valid value
        final rawCount = result['count'];
        if (rawCount != null) {
          final parsedCount = int.tryParse(rawCount.toString());
          if (parsedCount != null && parsedCount >= 0) {
            reel['likes_count'] = parsedCount;
          }
        }
      });
    }
  }

  Future<void> _handleFollow(dynamic reel) async {
    final userId = (reel['user_id'] ?? reel['user']?['id'] ?? '').toString();
    if (userId.isEmpty) return;

    final alreadyFollowing = _followedUserIds.contains(userId);
    await SoundService().playReact();

    // Track follow engagement
    if (!alreadyFollowing && _currentIndex < _activeReels.length) {
      _tracker.recordFollow(_activeReels[_currentIndex]);
    }

    setState(() {
      if (alreadyFollowing) {
        _followedUserIds.remove(userId);
      } else {
        _followedUserIds.add(userId);
      }
    });

    try {
      if (alreadyFollowing) {
        await _apiService.unfollowUser(userId);
      } else {
        await _apiService.followUser(userId);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (alreadyFollowing) {
            _followedUserIds.add(userId);
          } else {
            _followedUserIds.remove(userId);
          }
        });
      }
    }
  }

  bool _isFollowingUser(dynamic reel) {
    final userId = (reel['user_id'] ?? reel['user']?['id'] ?? '').toString();
    return _followedUserIds.contains(userId);
  }

  Future<void> _openProfileFromSwipe(dynamic reel) async {
    final userId = (reel['user_id'] ?? reel['user']?['id'] ?? '').toString();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProfileScreen(userId: userId.isNotEmpty ? userId : null),
      ),
    );
  }

  Future<void> _refreshActiveReelsAfterShare() async {
    try {
      final updated = _isForYou
          ? await _apiService.getReels(type: 'trending')
          : await _apiService.getFollowingReels();

      if (!mounted) return;

      final safeIndex =
          updated.isEmpty ? 0 : _currentIndex.clamp(0, updated.length - 1);

      setState(() {
        if (_isForYou) {
          _forYouReels = updated;
        } else {
          _followingReels = updated;
        }
        _currentIndex = safeIndex;
      });

      if (updated.isNotEmpty) {
        _jumpToIndex(safeIndex);
      }
    } catch (_) {}
  }

  Future<void> _showShareSheet(dynamic reel) async {
    final postId = reel['id'] ?? reel['post_id'];
    if (postId == null) return;
    final reelUser = reel['user'] ?? {};
    final reelUsername = (reel['author_username'] ??
            reel['username'] ??
            reelUser['username'] ??
            reelUser['name'] ??
            '')
        .toString();

    ShareBottomSheet.show(
      context: context,
      postId: postId,
      username: reelUsername,
      onShared: _refreshActiveReelsAfterShare,
    );
  }

  Future<void> _showCommentsOverlay(dynamic reel) async {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (postId.isEmpty) return;

    final comments = (reel['comments'] is List)
        ? List<dynamic>.from(reel['comments'] as List)
        : <dynamic>[];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _ReelCommentsSheet(
          postId: postId,
          initialComments: comments,
          apiService: _apiService,
          onCommentAdded: () {
            if (mounted) {
              setState(() {
                final count = int.tryParse(
                      (reel['comments_count'] ?? reel['comments'] ?? 0)
                          .toString(),
                    ) ??
                    0;
                reel['comments_count'] = count + 1;
              });
            }
          },
        );
      },
    );
  }

  String _firstCharacter(String value) {
    if (value.trim().isEmpty) return '?';
    return value.trim()[0].toUpperCase();
  }

  String _formatCount(dynamic value, String fallback) {
    if (value == null) return fallback;
    final intValue = int.tryParse(value.toString());
    if (intValue == null) return fallback;
    if (intValue >= 1000000) {
      return '${(intValue / 1000000).toStringAsFixed(1)}M';
    }
    if (intValue >= 1000) {
      return '${(intValue / 1000).toStringAsFixed(1)}K';
    }
    return intValue.toString();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    EyeBlinkService.instance.stop();
    _disposeCurrentControllerCache();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: null,
      body: Stack(
        children: [
          // â”€â”€ Fullscreen tab views (video behind everything) â”€â”€
          Positioned.fill(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildLiveTab(),
                _buildReelsFeed(isForYou: false),
                _buildReelsFeed(isForYou: true),
              ],
            ),
          ),

          // â”€â”€ Floating top bar â”€â”€
          Positioned(
            top: topPad + 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _handleBack,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            height: 38,
                            constraints: const BoxConstraints(maxWidth: 240),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0B14).withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: const Color(0xFFFF295C).withValues(alpha: 0.18),
                                width: 0.8,
                              ),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF295C), Color(0xFFBF5AF2)],
                                ),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white54,
                              labelStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              dividerColor: Colors.transparent,
                              tabAlignment: TabAlignment.fill,
                              padding: EdgeInsets.zero,
                              tabs: const [
                                Tab(text: 'Live', height: 36),
                                Tab(text: 'Following', height: 36),
                                Tab(text: 'For You', height: 36),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      _currentController?.pause();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VideoRecorderScreen(),
                        ),
                      );
                      if (mounted) _currentController?.play();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF007F)
                                  .withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: Color(0xFFFF007F),
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Blink-active indicator ──
          if (_blinkEnabled)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              right: 16,
              child: const _BlinkIndicator(),
            ),
        ],
      ),
    );
  }

  //â”€â”€ Reels feed body (shared by Following & For You tabs) â”€â”€
  Widget _buildReelsFeed({required bool isForYou}) {
    final reels = isForYou ? _forYouReels : _followingReels;
    final isActiveTab = (isForYou && _tabController.index == _kTabForYou) ||
        (!isForYou && _tabController.index == _kTabFollowing);

    if (_isLoading && isActiveTab) {
      return const Center(
        child: CircularProgressIndicator(color: GalacticTheme.laserPink),
      );
    }

    if (reels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForYou ? Icons.movie_filter_outlined : Icons.people_outline,
              color: Colors.white24,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isForYou ? 'No Reels found' : 'No Following',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!isForYou) ...[
              const SizedBox(height: 8),
              const Text(
                'Follow people to see their videos here',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ],
        ),
      );
    }

    if (!isActiveTab) {
      return const SizedBox.shrink();
    }

    return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: true,
          onPageChanged: _handlePageChanged,
          itemCount: reels.length,
          itemBuilder: (context, index) {
            final reel = reels[index];
            final videoUrl =
                reel['file_url'] ?? reel['video_url'] ?? reel['image'] ?? '';

            final user = reel['user'];
            final bool isSubscribed = (user is Map &&
                    ((user['has_plan'] ?? user['has_subscription']) == true)) ||
                reel['has_plan'] == true ||
                reel['has_subscription'] == true;

            return RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -250) {
                      _openProfileFromSwipe(reel);
                    }
                  },
                  child: ReelsVideoPlayer(
                    videoUrl: videoUrl,
                    thumbnailUrl: (reel['thumbnail_url'] ?? '').toString(),
                    isActive: _currentIndex == index && isActiveTab,
                    preload: !isActiveTab
                        ? false
                        : index == _currentIndex + 1,
                    onDoubleTapLike: () => _handleLike(
                      reel,
                      withSound: false,
                      fromDoubleTap: true,
                    ),
                    onControllerReady: (controller) {
                      if (_currentIndex == index) {
                        _currentController = controller;
                        _currentControllerIndex = index;
                        controller.addListener(() {
                          if (!mounted) return;
                          final v = controller.value;
                          if (v.isInitialized &&
                              !v.isPlaying &&
                              v.duration > Duration.zero &&
                              v.position >= v.duration) {
                            _autoAdvanceToNext(index);
                          }
                        });
                      }
                    },
                    onControllerDisposed: (controller) {
                      if (identical(_currentController, controller) ||
                          _currentControllerIndex == index) {
                        _currentController = null;
                        _currentControllerIndex = null;
                      }
                    },
                  ),
                ),

                // Gift overlay above caption
                Builder(
                  builder: (ctx) {
                    final navPad = MediaQuery.of(ctx).padding.bottom + 12;
                    return Positioned(
                      left: 16,
                      right: 86,
                      bottom: navPad + 100,
                      child: _buildGiftOverlay(reel),
                    );
                  },
                ),
                // Bottom Center Info (Profile & Sound)
                Builder(
                  builder: (ctx) {
                    final navPad = MediaQuery.of(ctx).padding.bottom;
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: navPad,
                      child: _buildOwnerMeta(reel, isSubscribed),
                    );
                  },
                ),
                // Right Interaction Column – bottom right
                Builder(
                  builder: (ctx) {
                    final navPad = MediaQuery.of(ctx).padding.bottom + 12;
                    return Positioned(
                      right: 10,
                      bottom: navPad,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildNeonInteractionBtn(
                            _isReelLiked(reel)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            _formatCount(
                              reel['likes_count'] ?? reel['likes'],
                              'Like',
                            ),
                            _isReelLiked(reel)
                                ? const Color(0xFFFF007F)
                                : Colors.pinkAccent,
                            () => _handleLike(reel),
                          ),
                          const SizedBox(height: 18),
                          _buildNeonInteractionBtn(
                            Icons.comment,
                            _formatCount(
                              reel['comments_count'] ?? reel['comments'],
                              'Comment',
                            ),
                            Colors.cyanAccent,
                            () => _showCommentsOverlay(reel),
                          ),
                          const SizedBox(height: 18),
                          _buildNeonInteractionBtn(
                            Icons.share,
                            'Share',
                            Colors.white,
                            () => _showShareSheet(reel),
                          ),
                          if (!_isOwnReel(reel)) ...[
                            const SizedBox(height: 18),
                            _buildNeonInteractionBtn(
                              Icons.card_giftcard,
                              'Gift',
                              Colors.amberAccent,
                              () {
                                final uploaderId = (reel['user_id'] ??
                                        reel['user']?['id'] ??
                                        '')
                                    .toString();
                                final postId =
                                    (reel['id'] ?? reel['post_id'] ?? '')
                                        .toString();
                                GiftsSheet.show(
                                  context: context,
                                  toUserId: uploaderId,
                                  contextType: 'reels',
                                  contextId: postId,
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: () => _openSoundDetails(reel),
                            child: _buildSoundDisc(reel),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Black bar that covers the transparent system nav bar
                Builder(
                  builder: (ctx) {
                    final navH = MediaQuery.of(ctx).padding.bottom;
                    if (navH == 0) return const SizedBox.shrink();
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: navH,
                      child: const ColoredBox(color: Colors.black),
                    );
                  },
                ),
                ],
              ),
            );
          },
        );
  }

  // ── Live tab: list of live user cards ──
  List<Map<String, dynamic>> _liveUsers = [];
  bool _liveLoading = true;
  bool _liveFetched = false;

  Future<void> _fetchLiveUsers() async {
    if (_liveFetched) return;
    _liveFetched = true;
    setState(() => _liveLoading = true);
    try {
      final profiles = await _apiService.getLiveUsers();
      if (!mounted) return;
      final live = <Map<String, dynamic>>[];
      for (final p in profiles) {
        live.add({
          'user_id': (p['user_id'] ?? p['id'] ?? '').toString(),
          'name': (p['name'] ?? p['user_name'] ?? 'User').toString(),
          'avatar': (p['avatar'] ?? p['profile_pic'] ?? p['avatar_url'] ?? '')
              .toString(),
          'viewers':
              (p['viewers'] ?? p['followers_count'] ?? p['followers'] ?? 0),
        });
      }
      setState(() {
        _liveUsers = live;
        _liveLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _liveLoading = false);
    }
  }

  Widget _buildLiveTab() {
    // Fetch live users on first build
    if (!_liveFetched) {
      _fetchLiveUsers();
    }

    Widget content;
    if (_liveLoading) {
      content = const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF007F)),
      );
    } else if (_liveUsers.isEmpty) {
      content = const Center(
        child: Text(
          'No Live streams right now',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    } else {
      content = PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _liveUsers.length,
        itemBuilder: (context, index) {
          final user = _liveUsers[index];
          return _buildFullscreenLiveCard(user);
        },
      );
    }

    return Stack(
      children: [
        content,
        // ── Go Live button ──
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 20,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _goLive,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: const Color(0xFFD946EF).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_tethering, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Go Live',
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
          ),
        ),
      ],
    );
  }

  void _goLive() {
    final userId = UserPrefsCache.instance.userId ?? '';
    final profile = ProfileService.instance.currentProfileNotifier.value;
    final profileName = profile?.name;
    final userName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (profile?.username ?? 'You');
    final profileAvatar = profile?.avatar;
    final userAvatar = (profileAvatar != null && profileAvatar.isNotEmpty)
        ? profileAvatar
        : (profile?.profilePicUrl ?? '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePreviewScreen(
          userId: userId,
          userName: userName,
          userAvatar: userAvatar.isNotEmpty ? userAvatar : null,
        ),
      ),
    );
  }

  Widget _buildFullscreenLiveCard(Map<String, dynamic> user) {
    final name = (user['name'] ?? 'User').toString();
    final avatar = (user['avatar'] ?? '').toString();
    final viewers = int.tryParse(user['viewers']?.toString() ?? '') ?? 0;
    final userId = (user['user_id'] ?? '').toString();
    return _LiveUserCard(
      user: user,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveRoomScreen(
            userId: userId,
            userName: name,
            userAvatar: avatar.isNotEmpty ? avatar : null,
            viewerCount: viewers,
          ),
        ),
      ),
    );
  }



  Widget _buildOwnerMeta(dynamic reel, bool isSubscribed) {
    final rawUsername = (reel['author_name'] ??
            reel['author_username'] ??
            reel['user_name'] ??
            reel['username'] ??
            'User')
        .toString();
    final username = rawUsername.startsWith('@') ? rawUsername : '@$rawUsername';
    final user = reel['user'];
    final rawAvatar = (reel['author_avatar'] ??
            reel['user_avatar'] ??
            user?['author_avatar'] ??
            user?['avatar_url'] ??
            user?['profile_pic'] ??
            '')
        .toString();
    final avatar = normalizeMediaUrl(rawAvatar,
        baseUrl: AppEnv.baseUrl, folder: 'profiles');
    final rawCaption = (reel['caption'] ?? '').toString();
    final caption = rawCaption
        .replaceAll(RegExp(r'\s*#\w+'), '')
        .trim()
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    final displayCaption = caption.length > 90
        ? '${caption.substring(0, 88).trimRight()}…'
        : caption;

    final soundName =
        (reel['sound_name'] ?? reel['audio_name'] ?? reel['music_name'] ?? '')
            .toString();
    final soundAuthor =
        (reel['sound_author_username'] ?? '').toString().trim();
    final posterName =
        (reel['author_username'] ?? reel['user_name'] ?? reel['username'] ?? 'User')
            .toString();
    final soundCredit =
        soundName.isNotEmpty ? '$soundName  •  ${soundAuthor.isNotEmpty ? soundAuthor : posterName}' : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.15),
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.18, 0.50, 0.80, 1.0],
        ),
      ),
      // Right padding 92px clears the action-button column (right: 10, width ~62px)
      padding: const EdgeInsets.fromLTRB(16, 22, 92, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Caption ─────────────────────────────────────────────────
          if (displayCaption.isNotEmpty && displayCaption != 'New Post') ...[
            Text(
              displayCaption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 1)),
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 11),
          ],

          // ── Sound strip ───────────────────────────────────────────────
          if (_hasCustomSound(reel) && soundCredit.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _openSoundDetails(reel),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: Colors.white, size: 12),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      soundCredit,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
          ],

          // ── Profile row ──────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar — larger, 3-color gradient ring
              GestureDetector(
                onTap: () => _openProfileFromSwipe(reel),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF007F),
                        Color(0xFFFF6B35),
                        Color(0xFF7C3AED),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0D0D0D),
                    ),
                    child: avatar.isNotEmpty && avatar.startsWith('http')
                        ? CircleAvatar(
                            radius: 20,
                            backgroundImage: CachedNetworkImageProvider(avatar),
                          )
                        : CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF7C3AED),
                            child: Text(
                              _firstCharacter(rawUsername),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 11),

              // @username
              Expanded(
                child: GestureDetector(
                  onTap: () => _openProfileFromSwipe(reel),
                  child: Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: 0.15,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 1)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              if (!_isOwnReel(reel)) ...[
                const SizedBox(width: 10),
                _buildSmartSubscriptionButton(reel),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSoundDetails(dynamic reel) async {
    _currentController?.pause();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => _SoundDetailsScreen(reel: reel)),
    );

    if (result is Map && result['use_sound'] == true && mounted) {
      final soundName = result['sound_name']?.toString();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoRecorderScreen(initialSoundName: soundName),
        ),
      );
    }

    if (mounted) _currentController?.play();
  }

  Widget _buildSmartSubscriptionButton(dynamic reel) {
    final following = _isFollowingUser(reel);
    return GestureDetector(
      onTap: () => _handleFollow(reel),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: following
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.50),
                  width: 1.2,
                ),
              )
            : BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
        child: Text(
          following ? 'Following' : 'Follow',
          style: TextStyle(
            color: following
                ? Colors.white.withValues(alpha: 0.90)
                : const Color(0xFFD10060),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  /// Cache of fetched gift overlays per post id to avoid re-fetching.
  final Map<String, List<GiftTx>> _giftOverlayCache = {};

  Widget _buildGiftOverlay(dynamic reel) {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (postId.isEmpty) return const SizedBox.shrink();

    // Trigger fetch if not cached
    if (!_giftOverlayCache.containsKey(postId)) {
      _giftOverlayCache[postId] = []; // mark as loading
      ApiService().fetchPostGifts(contextType: 'reels', contextId: postId).then(
        (raw) {
          if (!mounted) return;
          final gifts = raw.map((e) => GiftTx.fromJson(e)).toList();
          setState(() => _giftOverlayCache[postId] = gifts);
        },
      );
    }

    final gifts = _giftOverlayCache[postId] ?? [];
    if (gifts.isEmpty) return const SizedBox.shrink();
    return GiftOverlayWidget(gifts: gifts);
  }

  /// TikTok-style rotating disc showing owner avatar with music note overlay
  Widget _buildSoundDisc(dynamic reel) {
    final user = reel['user'];
    final rawAvatar = (reel['author_avatar'] ??
            reel['user_avatar'] ??
            user?['author_avatar'] ??
            user?['avatar_url'] ??
            user?['profile_pic'] ??
            '')
        .toString();
    final avatar = normalizeMediaUrl(rawAvatar,
        baseUrl: AppEnv.baseUrl, folder: 'profiles');
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFF007F), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF1A1A1A),
        ),
        child: Stack(
        alignment: Alignment.center,
        children: [
          avatar.isNotEmpty
              ? CircleAvatar(
                  radius: 16,
                  backgroundImage: CachedNetworkImageProvider(avatar),
                )
              : const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFF7C3AED),
                  child: Icon(Icons.music_note, color: Colors.white, size: 14),
                ),
          // Music note overlay badge
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Icon(
                Icons.music_note,
                color: Colors.white,
                size: 10,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildNeonInteractionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Animated Live Card ───────────────────────────────────────────────────────

class _LiveUserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onTap;
  const _LiveUserCard({required this.user, required this.onTap});
  @override
  State<_LiveUserCard> createState() => _LiveUserCardState();
}

class _LiveUserCardState extends State<_LiveUserCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _glowRadius;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _glowRadius = Tween<double>(begin: 6.0, end: 24.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.user['name'] ?? 'User').toString();
    final avatar = (widget.user['avatar'] ?? '').toString();
    final viewers = int.tryParse(widget.user['viewers']?.toString() ?? '') ?? 0;
    final hasAvatar = avatar.isNotEmpty && avatar.startsWith('http');

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background
            if (hasAvatar)
              Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                  imageUrl: avatar,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  memCacheHeight: 400,
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF0D0D1A)),
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF0D0D1A)),
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(color: Colors.black.withValues(alpha: 0.5)),
                ),
              ])
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1a0533),
                      Color(0xFF0d1b4b),
                      Color(0xFF190a2e),
                    ],
                  ),
                ),
              ),

            // Bottom fade
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 340,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black,
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),

            // Pulsing LIVE badge
            Positioned(
              top: 52,
              left: 0,
              right: 0,
              child: Center(
                child: ScaleTransition(
                  scale: _pulseScale,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFFF007F).withValues(alpha: 0.65),
                          blurRadius: 22,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 9),
                        SizedBox(width: 6),
                        Text('LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 2.5,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Avatar with animated glow ring
            Center(
              child: AnimatedBuilder(
                animation: _glowRadius,
                builder: (_, __) => Container(
                  width: 134,
                  height: 134,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(colors: [
                      Color(0xFFFF007F),
                      Color(0xFFD946EF),
                      Color(0xFF3B82F6),
                      Color(0xFF8B5CF6),
                      Color(0xFFFF007F),
                    ]),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF007F).withValues(alpha: 0.6),
                        blurRadius: _glowRadius.value,
                        spreadRadius: _glowRadius.value * 0.3,
                      ),
                      BoxShadow(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.35),
                        blurRadius: _glowRadius.value * 2.2,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.5),
                    child: Container(
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.black),
                      child: CircleAvatar(
                        backgroundColor: const Color(0xFF2D1B69),
                        backgroundImage: hasAvatar
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: !hasAvatar
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Name + viewer count
            Positioned(
              bottom: 180,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.remove_red_eye_outlined,
                          color: Colors.white60, size: 15),
                      const SizedBox(width: 5),
                      Text('${_fmt(viewers)} watching',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),

            // JOIN LIVE gradient button
            Positioned(
              bottom: 96,
              left: 52,
              right: 52,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.55),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 24),
                      SizedBox(width: 6),
                      Text('JOIN LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.8,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sound Details Screen ─────────────────────────────────────────────────────

class _SoundDetailsScreen extends StatefulWidget {
  final dynamic reel;
  const _SoundDetailsScreen({required this.reel});
  @override
  State<_SoundDetailsScreen> createState() => _SoundDetailsScreenState();
}

class _SoundDetailsScreenState extends State<_SoundDetailsScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _soundReels = [];
  bool _isLoading = true;
  late AnimationController _discCtrl;
  final Map<String, Uint8List?> _thumbCache = {};

  String get _soundName => (widget.reel['sound_name'] ??
          widget.reel['audio_name'] ??
          widget.reel['music_name'] ??
          'Original Audio')
      .toString();

  String get _creatorName {
    final soundAuthor = (widget.reel['sound_author_username'] ?? '').toString().trim();
    if (soundAuthor.isNotEmpty) return soundAuthor;
    return (widget.reel['author_username'] ??
            widget.reel['author_name'] ??
            widget.reel['user_name'] ??
            widget.reel['username'] ??
            'Original Creator')
        .toString();
  }

  String get _creatorAvatarRaw {
    final user = widget.reel['user'];
    return (widget.reel['author_avatar'] ??
            widget.reel['user_avatar'] ??
            widget.reel['avatar'] ??
            user?['author_avatar'] ??
            user?['avatar'] ??
            user?['avatar_url'] ??
            user?['profile_pic'] ??
            '')
        .toString();
  }

  String get _creatorAvatar => normalizeMediaUrl(
        _creatorAvatarRaw,
        baseUrl: AppEnv.baseUrl,
        folder: 'profiles',
      );

  String get _thumbnail {
    final raw = (widget.reel['thumbnail_url'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      return normalizeMediaUrl(raw, baseUrl: AppEnv.baseUrl);
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _discCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
    _fetchSoundReels();
  }

  @override
  void dispose() {
    _discCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSoundReels() async {
    try {
      final sn = _soundName;
      List<dynamic> reels;

      // If this reel uses original audio (no custom sound), the server can't
      // filter by sound — just show the current reel only.
      if (sn == 'Original Audio') {
        reels = [widget.reel];
      } else {
        final all = await ApiService().getReels(type: 'trending', soundName: sn);
        if (!mounted) return;
        // Client-side filter: only keep reels that actually match this sound.
        final filtered = all.where((r) {
          final rSnd = (r['sound_name'] ?? r['audio_name'] ?? r['music_name'] ?? '').toString();
          return rSnd == sn || rSnd.isEmpty;
        }).toList();
        final ids = filtered.map((r) => r['id']?.toString()).toSet();
        reels = [
          ...filtered,
          if (!ids.contains(widget.reel['id']?.toString())) widget.reel,
        ];
        if (reels.isEmpty) reels = [widget.reel];
      }

      if (!mounted) return;
      setState(() {
        _soundReels = reels;
        _isLoading = false;
      });
      _loadSoundThumbs(reels);
    } catch (_) {
      if (mounted) {
        setState(() {
          _soundReels = [widget.reel];
          _isLoading = false;
        });
        _loadSoundThumbs([widget.reel]);
      }
    }
  }

  void _loadSoundThumbs(List<dynamic> reels) {
    for (final r in reels) {
      final videoUrl = (r['file_url'] ?? r['video_url'] ?? '').toString().trim();
      if (videoUrl.isEmpty) continue;
      if (_thumbCache.containsKey(videoUrl)) continue;
      ThumbnailCache.instance.fetch(videoUrl).then((bytes) {
        if (mounted) setState(() => _thumbCache[videoUrl] = bytes);
      }).catchError((_) {});
    }
  }

  Future<void> _showReportSoundSheet() async {
    final reasons = [
      'Copyright infringement',
      'Unauthorized full song',
      'Wrong artist / metadata',
      'Abusive or illegal audio',
      'Other',
    ];
    String selectedReason = reasons.first;
    final detailsController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final _si = MediaQuery.of(sheetContext).viewInsets;
            final _sp = MediaQuery.of(sheetContext).padding;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                _si.bottom + (_si.bottom == 0 ? _sp.bottom : 0) + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Report sound',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _soundName,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...reasons.map(
                    (reason) => RadioListTile<String>(
                      value: reason,
                      groupValue: selectedReason,
                      activeColor: const Color(0xFFFF007F),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        reason,
                        style: const TextStyle(color: Colors.white),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedReason = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Extra details (optional)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF007F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              try {
                                final postId = (widget.reel['id'] ??
                                        widget.reel['post_id'] ??
                                        '')
                                    .toString();
                                if (postId.isEmpty) {
                                  throw Exception('Invalid reel');
                                }
                                final result = await ApiService().reportSound(
                                  postId: postId,
                                  reason: selectedReason,
                                  soundName: _soundName,
                                  details: detailsController.text.trim(),
                                );
                                if (!mounted) return;
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      (result['message'] ??
                                              'Sound report submitted')
                                          .toString(),
                                    ),
                                  ),
                                );
                              } catch (e) {
                                setSheetState(() => isSubmitting = false);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit report'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '${_soundReels.length} Reels',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF007F))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final r = _soundReels[index];
                    final rawThumb = (r['thumbnail_url'] ?? '').toString().trim();
                    final networkThumb = rawThumb.isNotEmpty
                        ? normalizeMediaUrl(rawThumb, baseUrl: AppEnv.baseUrl)
                        : '';
                    final videoUrl = (r['file_url'] ?? r['video_url'] ?? '').toString().trim();
                    final cachedThumb = _thumbCache[videoUrl];

                    Widget thumbWidget;
                    if (networkThumb.isNotEmpty) {
                      thumbWidget = CachedNetworkImage(
                        imageUrl: networkThumb,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        memCacheHeight: 500,
                        errorWidget: (_, __, ___) => cachedThumb != null
                            ? Image.memory(cachedThumb, fit: BoxFit.cover)
                            : _buildGridPlaceholder(r),
                      );
                    } else if (cachedThumb != null) {
                      thumbWidget = Image.memory(cachedThumb, fit: BoxFit.cover);
                    } else {
                      thumbWidget = _buildGridPlaceholder(r);
                    }

                    return GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReelsScreen(
                            initialPostId: r['id'],
                            initialMode: ReelsFeedMode.reels,
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: thumbWidget,
                      ),
                    );
                  },
                  childCount: _soundReels.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.6,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final hasCreatorAvatar = _creatorAvatar.isNotEmpty;
    return Container(
      padding: const EdgeInsets.only(top: 52, bottom: 28, left: 20, right: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a0533), Color(0xFF0A0A0A)],
        ),
      ),
      child: Column(
        children: [
          // Back button
          Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Spinning disc
          RotationTransition(
            turns: _discCtrl,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(colors: [
                  Color(0xFFFF007F),
                  Color(0xFFD946EF),
                  Color(0xFF3B82F6),
                  Color(0xFF8B5CF6),
                  Color(0xFFFF007F),
                ]),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF0A0A0A)),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_thumbnail.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: _thumbnail,
                            fit: BoxFit.cover,
                            memCacheWidth: 300,
                            memCacheHeight: 300,
                          )
                        else
                          Container(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(colors: [
                                Color(0xFF2D1B69),
                                Color(0xFF0A0A0A),
                              ]),
                            ),
                            child: const Icon(Icons.music_note,
                                color: Color(0xFFFF007F), size: 38),
                          ),
                        Center(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF0A0A0A)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Sound name
          Text(
            _soundName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Original creator credits
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: const Color(0xFF2D1B69),
                backgroundImage: hasCreatorAvatar
                    ? CachedNetworkImageProvider(_creatorAvatar)
                    : null,
                child: !hasCreatorAvatar
                    ? Text(
                        _creatorName.isNotEmpty
                            ? _creatorName[0].toUpperCase()
                            : '?',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Original audio',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('@$_creatorName',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          GestureDetector(
            onTap: _showReportSoundSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flag_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Report This Sound',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Use This Sound button
          GestureDetector(
            onTap: () => Navigator.pop(
              context,
              {'use_sound': true, 'sound_name': _soundName},
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007F).withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_note, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Use This Sound',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridPlaceholder(Map<String, dynamic> r) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0D1A), Color(0xFF110820), Color(0xFF000000)],
        ),
      ),
      child: Center(
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1),
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white54, size: 22),
        ),
      ),
    );
  }
}

class _ReelCommentsSheet extends StatefulWidget {
  final String postId;
  final List<dynamic> initialComments;
  final ApiService apiService;
  final VoidCallback? onCommentAdded;
  const _ReelCommentsSheet(
      {required this.postId,
      required this.initialComments,
      required this.apiService,
      this.onCommentAdded});
  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  late List<dynamic> _comments;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.initialComments);
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    if (mounted) setState(() => _loading = true);
    try {
      final fresh = await widget.apiService.listComments(widget.postId);
      if (mounted) setState(() => _comments = fresh);
    } catch (_) {
      // keep initialComments on error
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
          color: Color(0xFF101010),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const Text('Comments',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final c = _comments[index];
                return ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.grey),
                  title: Text(c['user_name'] ?? 'User',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(c['comment'] ?? '',
                      style: const TextStyle(color: Colors.white70)),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
                // viewInsets.bottom = keyboard; padding.bottom = nav bar (0 when keyboard up)
                bottom: MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    10,
                left: 10,
                right: 10),
            child: Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            hintText: 'Add comment...',
                            hintStyle: TextStyle(color: Colors.white54)))),
                IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: () async {
                      if (_controller.text.isEmpty || _sending) return;
                      setState(() => _sending = true);
                      try {
                        await widget.apiService
                            .addComment(widget.postId, _controller.text);
                        if (mounted) {
                          setState(() {
                            _comments.add({
                              'user_name': 'You',
                              'comment': _controller.text
                            });
                            _controller.clear();
                          });
                          widget.onCommentAdded?.call();
                        }
                      } finally {
                        if (mounted) setState(() => _sending = false);
                      }
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pulsing eye badge shown in the corner when blink-to-scroll is active.
class _BlinkIndicator extends StatefulWidget {
  const _BlinkIndicator();

  @override
  State<_BlinkIndicator> createState() => _BlinkIndicatorState();
}

class _BlinkIndicatorState extends State<_BlinkIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFD946EF).withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.remove_red_eye_outlined, color: Color(0xFFD946EF), size: 14),
            SizedBox(width: 5),
            Text(
              'Blink to scroll',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
