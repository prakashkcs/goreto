import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:love_vibe_pro/services/secure_screen_service.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/widgets/neon_subscribe_button.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/reels_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/home_screen.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/config/app_env.dart';

import 'package:love_vibe_pro/widgets/share_bottom_sheet.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/gifts/gifts_sheet.dart';
import 'package:love_vibe_pro/widgets/gift_overlay_widget.dart';
import 'package:love_vibe_pro/widgets/subscriber_lock_overlay.dart';
import 'package:love_vibe_pro/screens/report/audio_report_sheet.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/services/analytics_service.dart';

class VideoFeedItem extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onSubscribe;
  final VoidCallback? onDeleted;

  const VideoFeedItem({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onSubscribe,
    this.onDeleted,
  });

  @override
  State<VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends State<VideoFeedItem>
    with SingleTickerProviderStateMixin {
  // ── Static const decorations (never rebuilt) ────────────────────────────
  static const _kDefaultThumbGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0D0D1A), Color(0xFF110820), Color(0xFF000000)],
    ),
  );

  static const _kReelBadgeDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
    ),
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );

  static const _kBottomSheetHandleDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
    ),
    borderRadius: BorderRadius.all(Radius.circular(2)),
  );

  static const _kBottomSheetDark = BoxDecoration(
    color: Color(0xFF1A1A1A),
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  );

  static const _kCaptionStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    shadows: [
      Shadow(color: Colors.black, offset: Offset(0, 1), blurRadius: 6),
      Shadow(color: Color(0xFFEC4899), blurRadius: 14),
    ],
  );

  static const _kViewsCountStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static const _kActionLabelStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    shadows: [Shadow(color: Colors.black, blurRadius: 6)],
  );

  // ────────────────────────────────────────────────────────────────────────

  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;
  late AnimationController _heartController;
  bool _showHeartOverlay = false;
  bool _hasRecordedView = false;
  Uint8List? _generatedThumb;
  bool _thumbRequested = false;
  bool _isMuted = false;

  // Analytics
  DateTime? _impressionStart;
  int _maxWatchPct = 0;

  // Like state
  late bool _isLiked;
  late int _likesCount;
  bool _isFollowing = false;
  bool _feedActionSubscribe = false; // true = Subscribe button, false = Follow
  final ApiService _api = ApiService();
  String? _currentUserId;
  bool _secureAcquired = false;

  @override
  void initState() {
    super.initState();
    // Engage FLAG_SECURE while a subscriber is viewing un-blurred
    // subscriber-only video. Non-subscribers see the blur overlay so don't
    // need protection. Released in dispose.
    final bool subscriberOnly = widget.post['subscriber_only'] == 1 ||
        widget.post['subscriber_only'] == true;
    final bool isLocked = widget.post['is_locked'] == 1 ||
        widget.post['is_locked'] == true;
    _secureAcquired = subscriberOnly && !isLocked;
    if (_secureAcquired) {
      SecureScreenService.instance.acquire();
    }
    // Video init is LAZY — moved to _handleVisibility (first visible)
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadLikeState();
    // Sync userId from cache — no async, no extra setState
    _currentUserId = UserPrefsCache.instance.userId;
    _impressionStart = DateTime.now();
    final userNode = widget.post['user'] ?? widget.post;
    _isFollowing = widget.post['is_following'] == true ||
        widget.post['is_following'] == 1 ||
        userNode['is_following'] == true ||
        userNode['is_following'] == 1;
    _loadFeedActionPref();

    final existingThumb = (widget.post['thumbnail_url'] ?? '').toString().trim();
    if (existingThumb.isNotEmpty && existingThumb.startsWith('http')) {
      // Pre-warm Flutter's ImageCache so the thumbnail appears instantly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          precacheImage(NetworkImage(existingThumb), context).catchError((_) {});
        }
      });
    } else {
      // No stored thumbnail — extract a frame from the video file.
      _fetchCachedThumb();
    }
  }

  Future<void> _fetchCachedThumb() async {
    if (_thumbRequested) return;
    final rawUrl = widget.post['video_url'] ??
        widget.post['file_url'] ??
        widget.post['media_url'];
    if (rawUrl == null || rawUrl.toString().trim().isEmpty) return;
    final url = normalizeMediaUrl(rawUrl, baseUrl: AppEnv.baseUrl, folder: '');
    if (url.isEmpty || !url.startsWith('http')) return;
    // Check cache synchronously first — may already be preloaded
    final cached = ThumbnailCache.instance.get(url);
    if (cached != null) {
      if (mounted) setState(() => _generatedThumb = cached);
      return;
    }
    _thumbRequested = true;
    final bytes = await ThumbnailCache.instance.fetch(url);
    if (mounted && bytes != null) setState(() => _generatedThumb = bytes);
  }

  Future<void> _loadFeedActionPref() async {
    final store = await SettingsStore.getInstance();
    final val = await store.getFeedActionSubscribe();
    if (mounted) setState(() => _feedActionSubscribe = val);
  }

  // _loadCurrentUserId removed â€” now sync via UserPrefsCache in initState

  void _loadLikeState() {
    // Single-pass sync init: server response + local cache, no setState needed
    final serverLiked =
        widget.post['is_liked'] == true || widget.post['is_liked'] == 1;
    _likesCount =
        int.tryParse((widget.post['likes_count'] ?? 0).toString()) ?? 0;
    final postId = widget.post['id'] ?? widget.post['post_id'];
    final locallyLiked = UserPrefsCache.instance.isPostLiked(postId);
    _isLiked = serverLiked || locallyLiked;
  }

  Future<void> _initializeVideo() async {
    final rawUrl = widget.post['video_url'] ??
        widget.post['file_url'] ??
        widget.post['media_url'];
    if (rawUrl == null || rawUrl.toString().trim().isEmpty) return;

    final url = normalizeMediaUrl(rawUrl, baseUrl: AppEnv.baseUrl, folder: '');
    if (url.isEmpty) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();

      if (_controller != controller) return;
      await Future.wait([
        controller.setLooping(true),
        controller.setVolume(_isMuted ? 0.0 : 1.0),
      ]);
      if (!mounted || _controller != controller) return;

      // Track max watch percentage via position listener
      controller.addListener(() {
        final duration = controller.value.duration.inSeconds;
        if (duration > 0) {
          final pct =
              (controller.value.position.inSeconds * 100 ~/ duration)
                  .clamp(0, 100);
          if (pct > _maxWatchPct) _maxWatchPct = pct;
        }
      });

      setState(() => _initialized = true);
      if (!(widget.post['is_locked'] == 1 || widget.post['is_locked'] == true)) {
        controller.play();
        _isPlaying = true;
      }
    } catch (_) {
      if (_controller == controller) {
        _controller = null;
        _initialized = false;
      }
    }
  }

  @override
  void dispose() {
    if (_secureAcquired) {
      _secureAcquired = false;
      SecureScreenService.instance.release();
    }
    if (_impressionStart != null) {
      final ms = DateTime.now().difference(_impressionStart!).inMilliseconds;
      final id = (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
      if (id.isNotEmpty) {
        AnalyticsService.instance.trackImpression(
          postId: id,
          source: 'feed',
          watchPct: _maxWatchPct,
          timeSpentMs: ms,
        );
        if (_maxWatchPct >= 80) {
          AnalyticsService.instance.trackWatchComplete(
            postId: id,
            watchPct: _maxWatchPct,
            durationSec: _controller?.value.duration.inSeconds ?? 0,
          );
        }
      }
    }
    _controller?.dispose();
    _heartController.dispose();
    super.dispose();
  }

  bool get _isOwnPost {
    if (_currentUserId == null) return false;
    final postUserId = (widget.post['user_id'] ??
            widget.post['user']?['id'] ??
            widget.post['user_id'])
        .toString();
    return postUserId == _currentUserId;
  }

  void _handleVisibility(VisibilityInfo info) {
    if (info.visibleFraction >= 0.5 && !_hasRecordedView) {
      final postId = widget.post['id'] ?? widget.post['post_id'];
      if (postId != null) {
        _api.recordView(postId.toString());
        _hasRecordedView = true;
      }
    }
    if (info.visibleFraction > 0.6) {
      // Start loading at >30% (below), play at >60%
      if (!_initialized && _controller == null) {
        _initializeVideo();
      }
      if (_initialized && !_isPlaying && _controller != null) {
        if (!(widget.post['is_locked'] == 1 ||
            widget.post['is_locked'] == true)) {
          _controller?.play();
          _isPlaying = true;
        }
      }
    } else if (info.visibleFraction > 0.3) {
      // Pre-warm the controller while partially visible — don't play yet
      if (!_initialized && _controller == null) {
        _initializeVideo();
      }
    } else if (info.visibleFraction < 0.1) {
      // Auto-dispose controller when scrolled well out of view
      if (_controller != null) {
        _controller!.dispose();
        _controller = null;
        _initialized = false;
        _isPlaying = false;
      }
    } else {
      if (_isPlaying && _controller != null) {
        _controller!.pause();
        _isPlaying = false;
      }
    }
  }

  void _showShareSheet() {
    // Check if the post owner disabled resharing
    final user = widget.post['user'] ?? {};
    final allowReshare = widget.post['allow_reshare'] ??
        user['allow_reshare'] ??
        widget.post['sharing_enabled'] ??
        true;
    if (allowReshare == false || allowReshare == 0 || allowReshare == '0') {
      NeonToast.error(context, 'Sharing Disabled By User');
      return;
    }
    final sharePostId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    if (sharePostId.isNotEmpty) {
      AnalyticsService.instance.trackShare(postId: sharePostId);
    }
    final postUser = widget.post['user'] ?? {};
    final postUsername = (widget.post['author_username'] ??
            widget.post['username'] ??
            postUser['username'] ??
            postUser['name'] ??
            '')
        .toString();
    ShareBottomSheet.show(
      context: context,
      postId: widget.post['id'] ?? widget.post['post_id'],
      username: postUsername,
      onShared: widget.onShare,
    );
  }

  Future<void> _handleLike() async {
    final postId = widget.post['id'] ?? widget.post['post_id'];
    if (postId == null) return;

    setState(() {
      _isLiked = !_isLiked;
      _likesCount =
          _isLiked ? _likesCount + 1 : (_likesCount - 1).clamp(0, 9999999);
    });

    final result = await _api.likePostToggle(postId);
    if (mounted) {
      setState(() {
        _isLiked = result['liked'] as bool? ?? _isLiked;
        if ((result['count'] as int?) != null &&
            (result['count'] as int) >= 0) {
          _likesCount = result['count'] as int;
        }
      });
    }
    widget.onLike?.call();
  }

  Future<void> _handleDoubleTap() async {
    if (!_isLiked) {
      await _handleLike();
    }
    if (mounted) {
      setState(() => _showHeartOverlay = true);
      _heartController.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showHeartOverlay = false);
      });
    }
  }

  Future<void> _handleFollow() async {
    final authorId = _resolvePostAuthorId();
    if (authorId == null) return;

    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !_isFollowing);

    try {
      if (wasFollowing) {
        await _api.unfollowUser(authorId);
      } else {
        await _api.followUser(authorId);
      }
    } catch (_) {
      if (mounted) setState(() => _isFollowing = wasFollowing);
    }
    widget.onSubscribe?.call();
  }

  void _handleLongPress() {
    if (_isOwnPost) {
      _showOwnPostActions();
    } else {
      _showOtherPostActions();
    }
  }

  void _showOwnPostActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: _kBottomSheetDark,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 44,
                height: 4,
                decoration: _kBottomSheetHandleDecoration,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Color(0xFF00E5FF)),
                ),
                title: const Text(
                  'Edit Post',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                title: const Text(
                  'Delete Post',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteConfirmation();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showOtherPostActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: _kBottomSheetDark,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 44,
                height: 4,
                decoration: _kBottomSheetHandleDecoration,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.thumb_up_outlined,
                    color: Color(0xFF00E5FF),
                  ),
                ),
                title: const Text(
                  'Show More Like This',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  NeonToast.success(
                    context,
                    'We\'ll show more posts like this!',
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.thumb_down_outlined,
                    color: Colors.orange,
                  ),
                ),
                title: const Text(
                  'Show Less Like This',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  NeonToast.info(context, 'We\'ll show fewer posts like this!');
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flag, color: Colors.red),
                ),
                title: const Text(
                  'Report Post',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.music_off, color: Color(0xFFD946EF)),
                ),
                title: const Text(
                  'Report Audio',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final postId =
                      (widget.post['id'] ?? widget.post['post_id'] ?? '')
                          .toString();
                  final soundName = (widget.post['sound_name'] ??
                          widget.post['audio_name'] ??
                          '')
                      .toString();
                  AudioReportSheet.show(context,
                      postId: postId, soundName: soundName);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog() {
    final controller = TextEditingController(
      text: widget.post['caption'] ?? widget.post['title'] ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFF007F)),
        ),
        title: const Text('Edit Post', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter new caption...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final postId = widget.post['id'] ?? widget.post['post_id'];
              if (postId == null) return;

              final newCaption = controller.text.trim();
              final success = await _api.editPost(postId, newCaption);

              if (mounted) {
                if (success) {
                  setState(() {
                    widget.post['caption'] = newCaption;
                    widget.post['title'] = newCaption;
                  });
                  NeonToast.success(context, 'Post updated!');
                } else {
                  NeonToast.error(
                    context,
                    'Edit not available - backend endpoint not ready',
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF007F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.red),
        ),
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final postId = widget.post['id'] ?? widget.post['post_id'];
              if (postId != null) {
                final success = await _api.deletePost(postId);
                if (success && mounted) {
                  NeonToast.success(context, 'Post deleted!');
                  widget.onDeleted?.call();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final reasons = [
      'Spam',
      'Nudity',
      'Violence',
      'Hate speech',
      'Harassment',
      'Other',
    ];
    String? selectedReason;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.red),
          ),
          title: const Text(
            'Report Post',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map(
                  (r) => RadioListTile<String>(
                    title: Text(r, style: const TextStyle(color: Colors.white)),
                    value: r,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFFFF007F),
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final postId =
                          widget.post['id'] ?? widget.post['post_id'];
                      if (postId != null) {
                        await _api.reportPost(postId, selectedReason!);
                        if (mounted) {
                          NeonToast.success(context, 'Report submitted!');
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentsSheet() {
    final postId = widget.post['id'] ?? widget.post['post_id'];
    if (postId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (p1_0) => _CommentsSheet(
        postId: postId,
        api: _api,
        onCommentAdded: () {
          setState(() {
            widget.post['comments_count'] =
                (widget.post['comments_count'] ?? 0) + 1;
          });
        },
      ),
    );
    widget.onComment?.call();
  }

  String? _resolvePostAuthorId() {
    final user = widget.post['user'];
    final rawId = widget.post['user_id'] ??
        widget.post['uid'] ??
        (user is Map ? (user['id'] ?? user['user_id'] ?? user['uid']) : null);
    final id = rawId?.toString().trim();
    if (id == null || id.isEmpty || id == '0') return null;
    return id;
  }

  String _cleanUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      final decoded = Uri.decodeComponent(url);
      if (decoded.startsWith('http')) return decoded;
    } catch (_) {}
    return url;
  }

  Widget _buildDefaultThumbnail(String caption, String avatarUrl) {
    return Container(
      decoration: _kDefaultThumbGradient,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white60, size: 38),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      caption,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 12, left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: _kReelBadgeDecoration,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      color: Colors.white, size: 10),
                  SizedBox(width: 3),
                  Text('REEL',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToReels() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReelsScreen(
          initialPostId: widget.post['id'] ?? widget.post['post_id'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.post['user'] ?? {};
    final username = widget.post['author_name'] ??
        widget.post['author_username'] ??
        widget.post['username'] ??
        user['name'] ??
        'User';
    final userAvatar = (widget.post['author_avatar'] ??
            widget.post['user_avatar'] ??
            user['author_avatar'] ??
            user['avatar'] ??
            user['avatar_url'] ??
            user['profile_pic'] ??
            '')
        .toString();
    final location = (widget.post['location']?.toString() ?? '').trim();
    final isSubscribed = widget.post['is_subscribed'] == 1 ||
        widget.post['is_subscribed'] == true;
    // Only use thumbnail_url — image_url on video posts is the video file itself.
    final thumbUrl = (widget.post['thumbnail_url'] ?? '').toString().trim();
    final caption =
        (widget.post['title'] ?? widget.post['caption'] ?? "Show Title")
            .toString();
    final repostOf =
        int.tryParse((widget.post['repost_of'] ?? '0').toString()) ?? 0;
    final isReposted = repostOf > 0;

    // â”€â”€ Resolve original post owner info for reshared reels â”€â”€
    final originalPost = widget.post['original_post'] as Map<String, dynamic>?;
    final origUser = originalPost != null
        ? (originalPost['user'] as Map<String, dynamic>?)
        : null;
    final originalUsername = (widget.post['original_user_name'] ??
            widget.post['original_username'] ??
            origUser?['name'] ??
            origUser?['username'] ??
            '')
        .toString();
    final originalFirstName = originalUsername.isNotEmpty
        ? originalUsername.split(' ').first
        : 'Original Creator';
    final originalAvatar = _cleanUrl(
      origUser?['profile_pic'] ??
          origUser?['avatar_url'] ??
          origUser?['avatar'] ??
          widget.post['original_avatar'] ??
          widget.post['original_user_profile_pic'] ??
          '',
    ); // DO NOT fallback to userAvatar

    final originalUserId = (origUser?['id'] ??
            origUser?['user_id'] ??
            origUser?['uid'] ??
            widget.post['original_user_id'] ??
            '') // DO NOT fallback to _resolvePostAuthorId() because that's the resharer!
        .toString();
    return GestureDetector(
      onLongPress: _handleLongPress,
      child: VisibilityDetector(
        key: Key('video-${widget.post['id']}'),
        onVisibilityChanged: _handleVisibility,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          height: MediaQuery.of(context).size.width * 5 / 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            clipBehavior: Clip.hardEdge,
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: _navigateToReels,
                  onDoubleTap: _handleDoubleTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.post['is_locked'] == 1 ||
                          widget.post['is_locked'] == true)
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 15.0,
                            sigmaY: 15.0,
                          ),
                          child: thumbUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: thumbUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 600,
                                  memCacheHeight: 800,
                                  placeholder: (_, __) => _buildDefaultThumbnail(caption, userAvatar),
                                  errorWidget: (_, __, ___) =>
                                      _buildDefaultThumbnail(
                                          caption, userAvatar),
                                )
                              : _generatedThumb != null
                                  ? Image.memory(_generatedThumb!, fit: BoxFit.cover, gaplessPlayback: true)
                                  : _buildDefaultThumbnail(caption, userAvatar),
                        )
                      else if (thumbUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          memCacheHeight: 800,
                          placeholder: (_, __) => _buildDefaultThumbnail(caption, userAvatar),
                          errorWidget: (_, __, ___) =>
                              _buildDefaultThumbnail(caption, userAvatar),
                        )
                      else if (_generatedThumb != null)
                        Image.memory(_generatedThumb!, fit: BoxFit.cover, gaplessPlayback: true)
                      else
                        _buildDefaultThumbnail(caption, userAvatar),
                      if (_isPlaying && _controller != null)
                        SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _controller!.value.size.width,
                              height: _controller!.value.size.height,
                              child: (widget.post['is_locked'] == 1 ||
                                      widget.post['is_locked'] == true)
                                  ? ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                        sigmaX: 8.0,
                                        sigmaY: 8.0,
                                      ),
                                      child: VideoPlayer(_controller!),
                                    )
                                  : VideoPlayer(_controller!),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Subscriber lock overlay
                if (widget.post['is_locked'] == 1 ||
                    widget.post['is_locked'] == true)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SubscriberLockOverlay(
                        creatorId:
                            int.tryParse(_resolvePostAuthorId() ?? '0') ?? 0,
                        creatorName:
                            widget.post['author_name']?.toString() ?? '',
                        creatorSubscriptionStatus: widget
                                .post['author_subscription_status']
                                ?.toString() ??
                            'inactive',
                        onSubscribed: () {
                          final ownerId = _resolvePostAuthorId();
                          if (ownerId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (p7_0) =>
                                    ProfileScreen(userId: ownerId),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                if (_showHeartOverlay)
                  Center(
                    child: ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _heartController,
                        curve: Curves.elasticOut,
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Color(0xFFFF007F),
                        size: 100,
                      ),
                    ),
                  ),
                // ── Repost attribution banner (top of video, full-width) ──
                if (isReposted)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.82),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                      child: Row(
                        children: [
                          // Repost pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFD946EF), Color(0xFF7C3AED)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.repeat_rounded, size: 11, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Reposted', style: TextStyle(
                                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Original creator tap area
                          GestureDetector(
                            onTap: () {
                              if (originalUserId.isNotEmpty) {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ProfileScreen(userId: originalUserId),
                                ));
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                originalAvatar.isNotEmpty && originalAvatar.startsWith('http')
                                    ? CircleAvatar(
                                        backgroundImage: CachedNetworkImageProvider(originalAvatar),
                                        radius: 12)
                                    : CircleAvatar(
                                        radius: 12,
                                        backgroundColor: const Color(0xFF7C3AED),
                                        child: Text(
                                          originalFirstName.isNotEmpty ? originalFirstName[0].toUpperCase() : '?',
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                const SizedBox(width: 6),
                                Text(
                                  '@$originalFirstName',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
                                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // â”€â”€ Right action column â€” compact TikTok-style â”€â”€
                Positioned(
                  right: 6,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 14),
                      _buildActionBtn(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        "$_likesCount",
                        _isLiked ? const Color(0xFFFF007F) : Colors.white,
                        _handleLike,
                      ),
                      const SizedBox(height: 14),
                      _buildActionBtn(
                        Icons.chat_bubble_outline_rounded,
                        "${widget.post['comments_count'] ?? 0}",
                        Colors.white,
                        _showCommentsSheet,
                      ),
                      const SizedBox(height: 14),
                      _buildActionBtn(
                        Icons.near_me_outlined,
                        "Share",
                        Colors.white,
                        _showShareSheet,
                      ),
                      if (!_isOwnPost) ...[
                        const SizedBox(height: 14),
                        _buildActionBtn(
                          Icons.card_giftcard_rounded,
                          'Gift',
                          const Color(0xFFFFD700),
                          _openGiftsSheet,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _buildRotatingMusicIcon(),
                    ],
                  ),
                ),

                // ── Resharer profile row (hidden on reposts — attribution
                //    banner at top already shows all needed context) ──
                if (!isReposted)
                Positioned(
                  left: 40,
                  right: 40,
                  top: 20,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final profileId =
                                isReposted && originalUserId.isNotEmpty
                                    ? originalUserId
                                    : _resolvePostAuthorId();
                            if (profileId == null ||
                                profileId.isEmpty ||
                                profileId == '0') {
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfileScreen(userId: profileId),
                              ),
                            );
                          },
                          child: userAvatar.isNotEmpty &&
                                  userAvatar.startsWith('http')
                              ? CircleAvatar(
                                  backgroundImage: NetworkImage(userAvatar),
                                  radius: 14,
                                )
                              : CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF3B82F6),
                                  child: Text(
                                    (username.toString().isNotEmpty
                                            ? username.toString()[0]
                                            : '?')
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              final profileId =
                                  isReposted && originalUserId.isNotEmpty
                                      ? originalUserId
                                      : _resolvePostAuthorId();
                              if (profileId == null ||
                                  profileId.isEmpty ||
                                  profileId == '0') {
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProfileScreen(userId: profileId),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black, blurRadius: 4),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (location.isNotEmpty)
                                  Text(
                                    location,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black, blurRadius: 4),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        NeonSubscribeButton(
                          isSubscribed: isSubscribed || _isFollowing,
                          isOwnPost: _isOwnPost,
                          // Show Subscribe only when author has an active plan
                          // AND enabled the feed-subscribe toggle. Otherwise Follow.
                          showSubscribeMode: _feedActionSubscribe &&
                              (widget.post['author_subscription_status']
                                      ?.toString() ??
                                  'inactive') ==
                                  'active',
                          onTap: _handleFollow,
                        ),
                      ],
                    ),
                  ),
                ),
                // â”€â”€ Gift overlay (above profile row) â”€â”€
                Positioned(
                  left: 12,
                  bottom: 90,
                  right: 70,
                  child: _buildGiftOverlay(),
                ),
                // â”€â”€ Caption at bottom-left â”€â”€
                Positioned(
                  left: 12,
                  bottom: 36,
                  right: 70,
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _kCaptionStyle,
                  ),
                ),
                // â”€â”€ Views count at bottom-left â”€â”€
                Positioned(
                  left: 12,
                  bottom: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.remove_red_eye_outlined,
                          color: Colors.white70, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(int.tryParse(
                              '${widget.post['views_unique'] ?? widget.post['views_total'] ?? widget.post['view_count'] ?? widget.post['views_count'] ?? widget.post['views'] ?? 0}',
                            ) ??
                            0),
                        style: _kViewsCountStyle,
                      ),
                      const SizedBox(width: 4),
                      const Text('views',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openGiftsSheet() {
    final uploaderId =
        (widget.post['user_id'] ?? widget.post['user']?['id'] ?? '').toString();
    final postId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    GiftsSheet.show(
      context: context,
      toUserId: uploaderId,
      contextType: 'video',
      contextId: postId,
    );
  }

  List<GiftTx>? _giftOverlayData;
  bool _giftOverlayFetched = false;

  Widget _buildGiftOverlay() {
    final postId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    if (postId.isEmpty) return const SizedBox.shrink();

    if (!_giftOverlayFetched) {
      _giftOverlayFetched = true;
      ApiService().fetchPostGifts(contextType: 'video', contextId: postId).then(
        (raw) {
          if (!mounted) return;
          final gifts = raw.map((e) => GiftTx.fromJson(e)).toList();
          if (gifts.isNotEmpty) {
            setState(() => _giftOverlayData = gifts);
          }
        },
      );
    }

    if (_giftOverlayData == null || _giftOverlayData!.isEmpty) {
      return const SizedBox.shrink();
    }
    return GiftOverlayWidget(gifts: _giftOverlayData!);
  }

  Widget _buildActionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 26,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 8),
              Shadow(color: Colors.black54, blurRadius: 3),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: _kActionLabelStyle,
          ),
        ],
      ),
    );
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() => _isMuted = !_isMuted);
    _controller!.setVolume(_isMuted ? 0.0 : 1.0);
  }

  Widget _buildRotatingMusicIcon() {
    return GestureDetector(
      onTap: _toggleMute,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF222222), width: 3),
          boxShadow: [
            BoxShadow(color: Colors.white.withValues(alpha: 0.1), blurRadius: 8),
          ],
        ),
        child: Icon(
          _isMuted ? Icons.volume_off_rounded : Icons.music_note,
          color: _isMuted ? Colors.white54 : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

String _cleanCommentValue(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

String _firstCommentNonEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final cleaned = _cleanCommentValue(value);
    if (cleaned.isNotEmpty) return cleaned;
  }
  return '';
}

String getAuthorName(Map c) {
  final user = c['user'] is Map ? c['user'] as Map : const {};
  final name = _firstCommentNonEmpty([
    c['author_name'],
    c['name'],
    c['user_name'],
    c['username'],
    c['author_username'],
    user['author_name'],
    user['name'],
    user['user_name'],
    user['username'],
  ]);
  return name.isEmpty ? 'User' : name;
}

String? getAuthorAvatar(Map c) {
  final user = c['user'] is Map ? c['user'] as Map : const {};
  final avatar = _firstCommentNonEmpty([
    c['author_avatar'],
    c['avatar'],
    c['profile_pic'],
    user['author_avatar'],
    user['avatar'],
    user['profile_pic'],
  ]);
  return avatar.isEmpty ? null : avatar;
}

String? getAuthorId(Map c) {
  final user = c['user'] is Map ? c['user'] as Map : const {};
  final authorId = _firstCommentNonEmpty([
    c['user_id'],
    c['uid'],
    user['user_id'],
    user['uid'],
    user['id'],
  ]);
  return authorId.isEmpty ? null : authorId;
}

// Comment model for video feed
class _VideoCommentModel {
  final String id;
  final String userId;
  final String username;
  final String avatar;
  final String text;
  final DateTime createdAt;
  final String? parentId;
  final List<_VideoCommentModel> replies;

  _VideoCommentModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.text,
    required this.createdAt,
    this.parentId,
    List<_VideoCommentModel>? replies,
  }) : replies = replies ?? [];

  factory _VideoCommentModel.fromJson(Map<String, dynamic> json) {
    return _VideoCommentModel(
      id: (json['id'] ?? json['comment_id'] ?? '').toString(),
      userId: getAuthorId(json) ?? '',
      username: getAuthorName(json),
      avatar: getAuthorAvatar(json) ?? '',
      text: (json['comment'] ?? json['text'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ??
              DateTime.now(),
      parentId: json['parent_id']?.toString(),
    );
  }

  _VideoCommentModel copyWith({String? text}) {
    return _VideoCommentModel(
      id: id,
      userId: userId,
      username: username,
      avatar: avatar,
      text: text ?? this.text,
      createdAt: createdAt,
      parentId: parentId,
      replies: replies,
    );
  }
}

// Comments Sheet for Video Posts
class _CommentsSheet extends StatefulWidget {
  final dynamic postId;
  final ApiService api;
  final VoidCallback? onCommentAdded;

  const _CommentsSheet({
    required this.postId,
    required this.api,
    this.onCommentAdded,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const _kCyan = Color(0xFF00E5FF);
  static const _kPink = Color(0xFFFF007F);
  static const _kPurple = Color(0xFFD946EF);

  static const _kHandleDecoration = BoxDecoration(
    gradient: LinearGradient(colors: [_kPink, _kCyan]),
    borderRadius: BorderRadius.all(Radius.circular(2)),
  );

  List<_VideoCommentModel> _comments = [];
  bool _loading = true;
  final TextEditingController _ctrl = TextEditingController();
  bool _posting = false;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  _VideoCommentModel? _replyTarget;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadCurrentUserId() {
    _currentUserId = UserPrefsCache.instance.userId;
  }

  Future<void> _load() async {
    final c = await widget.api.listComments(widget.postId);

    // Parse and organize into parent/child structure
    final List<_VideoCommentModel> parentComments = [];
    final Map<String, _VideoCommentModel> allComments = {};

    for (final json in c) {
      final comment = _VideoCommentModel.fromJson(json);
      allComments[comment.id] = comment;
    }

    for (final comment in allComments.values) {
      if (comment.parentId != null &&
          allComments.containsKey(comment.parentId)) {
        allComments[comment.parentId]!.replies.add(comment);
      } else {
        parentComments.add(comment);
      }
    }

    if (mounted) {
      setState(() {
        _comments = parentComments;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);

    // Optimistic insert
    final tempComment = _VideoCommentModel(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      userId: _currentUserId ?? 'unknown',
      username: 'You',
      avatar: '',
      text: text,
      createdAt: DateTime.now(),
      parentId: _replyTarget?.id,
    );

    setState(() {
      if (_replyTarget != null) {
        final parentIdx = _comments.indexWhere((c) => c.id == _replyTarget!.id);
        if (parentIdx != -1) {
          _comments[parentIdx].replies.add(tempComment);
        }
      } else {
        _comments.add(tempComment);
      }
    });

    _ctrl.clear();
    _replyTarget = null;

    final newComment = await widget.api.postComment(widget.postId, text);

    if (mounted) {
      if (newComment != null) {
        final serverComment = _VideoCommentModel.fromJson(newComment);
        setState(() {
          if (tempComment.parentId != null) {
            final parentIdx = _comments.indexWhere(
              (c) => c.id == tempComment.parentId,
            );
            if (parentIdx != -1) {
              _comments[parentIdx].replies.removeWhere(
                    (r) => r.id == tempComment.id,
                  );
              _comments[parentIdx].replies.add(serverComment);
            }
          } else {
            _comments.removeWhere((c) => c.id == tempComment.id);
            _comments.add(serverComment);
          }
          _posting = false;
        });
        widget.onCommentAdded?.call();
        SoundService().playNotification();
      } else {
        setState(() => _posting = false);
      }
    }
  }

  void _setReplyTarget(_VideoCommentModel comment) {
    setState(() => _replyTarget = comment);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  void _editComment(
    _VideoCommentModel comment,
    int parentIndex, {
    int? replyIndex,
  }) {
    final controller = TextEditingController(text: comment.text);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _kCyan, width: 1),
        ),
        title: const Text(
          'Edit Comment',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Edit your comment...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final newText = controller.text.trim();
              if (newText.isEmpty) return;

              setState(() {
                if (replyIndex != null) {
                  _comments[parentIndex].replies[replyIndex] = comment.copyWith(
                    text: newText,
                  );
                } else {
                  _comments[parentIndex] = comment.copyWith(text: newText);
                }
              });

              final success = await widget.api.editComment(comment.id, newText);
              if (!success && mounted) {
                NeonToast.error(context, 'Failed to edit comment');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(
    _VideoCommentModel comment,
    int parentIndex, {
    int? replyIndex,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.red, width: 1),
        ),
        title: const Text(
          'Delete Comment?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      if (replyIndex != null) {
        _comments[parentIndex].replies.removeAt(replyIndex);
      } else {
        _comments.removeAt(parentIndex);
      }
    });

    await widget.api.deleteComment(comment.id);
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _isOwnComment(_VideoCommentModel comment) {
    return _currentUserId != null && comment.userId == _currentUserId;
  }

  void _openAuthorProfile(String? authorId) {
    final userId = (authorId ?? '').trim();
    if (userId.isEmpty) return;
    if (_currentUserId != null && userId == _currentUserId) {
      HomeScreen.switchToProfileTab?.call();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (p9_0) => ProfileScreen(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0020),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: _kCyan.withValues(alpha: 0.5), width: 1.5),
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4,
              decoration: _kHandleDecoration,
            ),
            const Text(
              'Comments',
              style: TextStyle(
                color: _kCyan,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: _kCyan, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 6),
            Divider(color: _kCyan.withValues(alpha: 0.15), height: 1),

            // Reply indicator
            if (_replyTarget != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _kPink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kPink.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply, color: _kPink, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to ${_replyTarget!.username}',
                        style: const TextStyle(color: _kPink, fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _kCyan,
                        strokeWidth: 2,
                      ),
                    )
                  : _comments.isEmpty
                      ? Center(
                          child: Text(
                            'No comments yet. Be first! 💬',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) =>
                              _buildCommentItem(_comments[i], i),
                        ),
            ),
            SafeArea(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  8 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF12003A),
                  border: Border(
                    top: BorderSide(color: _kCyan.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _replyTarget != null
                              ? 'Reply to ${_replyTarget!.username}...'
                              : 'Write a comment...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: _kCyan.withValues(alpha: 0.4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: _kCyan.withValues(alpha: 0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: _kCyan,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (p10_0) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _submit,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_kPink, _kCyan],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kPink.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: _posting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(
    _VideoCommentModel comment,
    int parentIndex, {
    int? replyIndex,
  }) {
    final isOwn = _isOwnComment(comment);
    final neonColor = isOwn ? _kPink : _kCyan;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: neonColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: neonColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openAuthorProfile(comment.userId),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: comment.avatar.isNotEmpty
                                ? NetworkImage(comment.avatar)
                                : null,
                            backgroundColor: neonColor.withValues(alpha: 0.2),
                            child: comment.avatar.isEmpty
                                ? Icon(Icons.person, color: neonColor, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comment.username,
                                  style: TextStyle(
                                    color: neonColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _formatTime(comment.createdAt),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _setReplyTarget(comment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _kPurple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.reply, color: _kPurple, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Reply',
                          style: TextStyle(
                            color: _kPurple,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  color: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _kCyan.withValues(alpha: 0.3)),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editComment(
                        comment,
                        parentIndex,
                        replyIndex: replyIndex,
                      );
                    } else if (value == 'delete') {
                      _deleteComment(
                        comment,
                        parentIndex,
                        replyIndex: replyIndex,
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (isOwn) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: _kCyan, size: 18),
                            SizedBox(width: 10),
                            Text('Edit', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 18),
                            SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag, color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Text(
                              'Report',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (comment.replies.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...comment.replies.asMap().entries.map((entry) {
                final reply = entry.value;
                final replyIdx = entry.key;
                final isReplyOwn = _isOwnComment(reply);
                final replyColor = isReplyOwn ? _kPink : _kPurple;

                return Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: replyColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: replyColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _openAuthorProfile(reply.userId),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: reply.avatar.isNotEmpty
                                        ? NetworkImage(reply.avatar)
                                        : null,
                                    backgroundColor: replyColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    child: reply.avatar.isEmpty
                                        ? Icon(
                                            Icons.person,
                                            color: replyColor,
                                            size: 12,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              reply.username,
                                              style: TextStyle(
                                                color: replyColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatTime(reply.createdAt),
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          reply.text,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isReplyOwn)
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_horiz,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 16,
                            ),
                            color: const Color(0xFF1A1A1A),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editComment(
                                  reply,
                                  parentIndex,
                                  replyIndex: replyIdx,
                                );
                              } else if (value == 'delete') {
                                _deleteComment(
                                  reply,
                                  parentIndex,
                                  replyIndex: replyIdx,
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, color: _kCyan, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
