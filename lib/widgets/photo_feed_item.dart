import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/widgets/neon_subscribe_button.dart';

import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/home_screen.dart';
import 'package:love_vibe_pro/widgets/gifter_badge.dart';

import 'package:love_vibe_pro/widgets/share_bottom_sheet.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/gifts/gifts_sheet.dart';
import 'package:love_vibe_pro/widgets/gift_overlay_widget.dart';
import 'package:love_vibe_pro/widgets/subscriber_lock_overlay.dart';
import 'package:love_vibe_pro/widgets/secure_content_area.dart';
import 'package:love_vibe_pro/services/analytics_service.dart';

class PhotoFeedItem extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onSubscribe;
  final VoidCallback? onDeleted;

  const PhotoFeedItem({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onSubscribe,
    this.onDeleted,
  });

  @override
  State<PhotoFeedItem> createState() => _PhotoFeedItemState();
}

class _PhotoFeedItemState extends State<PhotoFeedItem>
    with SingleTickerProviderStateMixin {
  // ── Static const decorations (never rebuilt) ────────────────────────────
  static const _kTextPostInnerGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2D1A2D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const _kBottomSheetHandleDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
    ),
    borderRadius: BorderRadius.all(Radius.circular(2)),
  );

  static const _kThoughtsButtonDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
    ),
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  static const _kFullscreenCloseBtnDecoration = BoxDecoration(
    color: Colors.black54,
    shape: BoxShape.circle,
  );

  static const _kCaptionStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    shadows: [
      Shadow(color: Colors.black, offset: Offset(0, 1), blurRadius: 6),
      Shadow(color: Color(0xFFEC4899), blurRadius: 14),
    ],
  );

  static const _kReshareBadgeTextStyle = TextStyle(
    color: Color(0xFF00E5FF),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  static const _kActionLabelStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    shadows: [Shadow(color: Colors.black, blurRadius: 6)],
  );

  static const _kGifterNameStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
  );
  // ────────────────────────────────────────────────────────────────────────

  late AnimationController _heartController;
  bool _showHeartOverlay = false;

  // Task 2: real like state
  late bool _isLiked;
  late int _likesCount;
  bool _isFollowing = false;
  bool _hasRecordedView = false;
  final ApiService _api = ApiService();
  String? _currentUserId;

  // Analytics: track how long this photo was visible
  DateTime? _impressionStart;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadLikeState();
    // Sync userId from cache — no async, no extra setState
    _currentUserId = UserPrefsCache.instance.userId;
    final userNode = widget.post['user'] ?? widget.post;
    _isFollowing = widget.post['is_following'] == true ||
        widget.post['is_following'] == 1 ||
        userNode['is_following'] == true ||
        userNode['is_following'] == 1;
    _impressionStart = DateTime.now();
  }

  // _loadCurrentUserId removed â€” now sync via UserPrefsCache in initState

  void _loadLikeState() {
    // Single-pass sync init: server + local cache, no setState needed (before first build)
    final serverLiked =
        widget.post['is_liked'] == true || widget.post['is_liked'] == 1;
    _likesCount =
        int.tryParse((widget.post['likes_count'] ?? 0).toString()) ?? 0;
    final postId = widget.post['id'] ?? widget.post['post_id'];
    final locallyLiked = UserPrefsCache.instance.isPostLiked(postId);
    _isLiked = serverLiked || locallyLiked;
  }

  @override
  void dispose() {
    _heartController.dispose();
    if (_impressionStart != null) {
      final ms = DateTime.now().difference(_impressionStart!).inMilliseconds;
      final id = (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
      if (id.isNotEmpty && ms > 500) {
        AnalyticsService.instance.trackImpression(
          postId: id,
          source: 'feed',
          timeSpentMs: ms,
        );
      }
    }
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
    final postUsername = (widget.post['author_username'] ??
            widget.post['username'] ??
            user['username'] ??
            user['name'] ??
            '')
        .toString();
    final sharePostId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    if (sharePostId.isNotEmpty) {
      AnalyticsService.instance.trackShare(postId: sharePostId);
    }
    ShareBottomSheet.show(
      context: context,
      postId: widget.post['id'] ?? widget.post['post_id'],
      username: postUsername,
      onShared: widget.onShare,
    );
  }

  // â”€â”€ Task 2: toggle like with neon-pink state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleLike() async {
    final postId = widget.post['id'] ?? widget.post['post_id'];
    if (postId == null) return;

    // Optimistic UI update
    setState(() {
      _isLiked = !_isLiked;
      _likesCount =
          _isLiked ? _likesCount + 1 : (_likesCount - 1).clamp(0, 9999999);
    });

    // Confirm with server
    final result = await _api.likePostToggle(postId);
    if (mounted) {
      setState(() {
        // Parse liked field robustly â€” server may return bool, int, or string
        final rawLiked = result['liked'];
        if (rawLiked != null) {
          _isLiked = rawLiked == true || rawLiked == 1 || rawLiked == '1';
        }
        // Only update count if server returned a valid count
        final rawCount = result['count'];
        if (rawCount != null) {
          final parsedCount = int.tryParse(rawCount.toString());
          if (parsedCount != null && parsedCount >= 0) {
            _likesCount = parsedCount;
          }
        }
      });
    }
    widget.onLike?.call();
  }

  // â”€â”€ Task 2: real comments BottomSheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
          // Update comment count optimistically
          setState(() {
            widget.post['comments_count'] =
                (widget.post['comments_count'] ?? 0) + 1;
          });
        },
      ),
    );
    widget.onComment?.call();
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

  // â”€â”€ Task 6: Long Press Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: const Color(0xFFFF007F).withValues(alpha: 0.3),
          ),
        ),
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
                subtitle: const Text(
                  'Update caption',
                  style: TextStyle(color: Colors.white54),
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
                subtitle: const Text(
                  'Remove this post permanently',
                  style: TextStyle(color: Colors.white54),
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
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: const Color(0xFFFF007F).withValues(alpha: 0.3),
          ),
        ),
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
                subtitle: const Text(
                  'Report inappropriate content',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog();
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
      text: widget.post['caption'] ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFF007F), width: 1),
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
                  // Update local post immediately
                  setState(() {
                    widget.post['caption'] = newCaption;
                  });
                  NeonToast.success(context, 'Post updated!');
                } else {
                  // API returned false - show appropriate message
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
          side: const BorderSide(color: Colors.red, width: 1),
        ),
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action cannot be undone. Are you sure you want to delete this post?',
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
      'Spam or misleading',
      'Nudity or sexual content',
      'Violence or harmful content',
      'Hate speech',
      'Harassment or bullying',
      'Other',
    ];
    String? selectedReason;
    final detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.red, width: 1),
          ),
          title: const Text(
            'Report Post',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why are you reporting this post?',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ...reasons.map(
                  (reason) => RadioListTile<String>(
                    title: Text(
                      reason,
                      style: const TextStyle(color: Colors.white),
                    ),
                    value: reason,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFFFF007F),
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                  ),
                ),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Please provide details...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],
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
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final postId =
                          widget.post['id'] ?? widget.post['post_id'];
                      if (postId != null) {
                        final success = await _api.reportPost(
                          postId,
                          selectedReason!,
                          details: detailsController.text,
                        );
                        if (success && mounted) {
                          NeonToast.success(
                            context,
                            'Report submitted. Thank you!',
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
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

  void _navigateToProfile() {
    final authorId = _resolvePostAuthorId();
    if (authorId == null) return;
    final postId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    if (postId.isNotEmpty) {
      AnalyticsService.instance
          .trackProfileVisit(postId: postId, creatorId: authorId);
    }
    if (_currentUserId != null && authorId == _currentUserId) {
      HomeScreen.switchToProfileTab?.call();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (p2_0) => ProfileScreen(userId: authorId)),
    );
  }

  String _cleanUrl(dynamic url) {
    if (url == null) return '';
    String urlString = url.toString();
    if (urlString.startsWith('[') && urlString.endsWith(']')) {
      try {
        final List<dynamic> list = jsonDecode(urlString);
        if (list.isNotEmpty) {
          return list[0].toString();
        }
      } catch (e) {}
    }
    return urlString;
  }

  String? _resolveMediaUrl(Map<String, dynamic> post) {
    final mediaUrl = post["file_url"] ??
        post["image_url"] ??
        post["media_url"] ??
        post["image"] ??
        post["photo"] ??
        post["raw_file_url"];

    final cleaned = _cleanUrl(mediaUrl);
    final normalized = normalizeMediaUrl(
      cleaned,
      baseUrl: AppEnv.baseUrl,
      folder: '',
    );

    if (normalized.isEmpty) {
      // Optional: handle empty media URL gracefully if needed
    }
    return normalized;
  }

  Widget _buildImageError(dynamic error, String mediaUrl) {
    return Container(
      color: const Color(0xFF1A1A1A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, color: Color(0xFFFF007F), size: 38),
          const SizedBox(height: 8),
          Text(
            'IMG ERR: $error',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Text(
              mediaUrl,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
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
    final userAvatar = _cleanUrl(
      widget.post['author_avatar'] ??
          widget.post['user_avatar'] ??
          user['author_avatar'] ??
          user['avatar'] ??
          user['avatar_url'] ??
          user['profile_pic'] ??
          '',
    );
    final location = (widget.post['location']?.toString() ?? '').trim();
    final imageUrl = _resolveMediaUrl(widget.post) ?? '';
    final isSubscribed = widget.post['is_subscribed'] == 1 ||
        widget.post['is_subscribed'] == true;
    final isReposted = (widget.post['is_repost'] == 1 ||
            widget.post['is_repost'] == true) ||
        (int.tryParse((widget.post['repost_of'] ?? '0').toString()) ?? 0) > 0;
    final repostCaption =
        (widget.post['repost_caption'] ?? '').toString().trim();
    final caption = isReposted && repostCaption.isNotEmpty
        ? repostCaption
        : (widget.post['caption'] ?? '').toString();
    final repostOf =
        int.tryParse((widget.post['repost_of'] ?? '0').toString()) ?? 0;
    final hasRepostOf = repostOf > 0;

    // Check if it's a "Text Post" (no valid image URL or placeholder)
    final bool isTextPost = imageUrl.isEmpty && caption.isNotEmpty;
    final isLocked =
        widget.post['is_locked'] == 1 || widget.post['is_locked'] == true;
    // Engage FLAG_SECURE when the subscriber is actually viewing the un-blurred
    // subscriber-only content. No need to block screenshots on locked content
    // because non-subscribers only see the blur overlay.
    final bool isSubscriberOnlyContent = (widget.post['subscriber_only'] == 1 ||
            widget.post['subscriber_only'] == true) &&
        !isLocked;
    final String authorSubscriptionStatus =
        widget.post['author_subscription_status']?.toString() ?? 'inactive';
    final authorId = int.tryParse(
          (widget.post['user_id'] ?? widget.post['uid'] ?? '0').toString(),
        ) ??
        0;
    final authorName =
        (widget.post['author_name'] ?? widget.post['username'] ?? '')
            .toString();

    // â”€â”€ Reshared / Reposted layout â”€â”€
    if (isReposted || hasRepostOf) {
      return _buildResharedLayout(
        username: username,
        userAvatar: userAvatar,
        location: location,
        imageUrl: imageUrl,
        caption: caption,
        isSubscribed: isSubscribed,
        isTextPost: isTextPost,
      );
    }

    // â”€â”€ Normal (non-reposted) layout â”€â”€
    final BoxBorder postBorder = isTextPost
        ? Border.all(color: const Color(0xFFFF007F), width: 1.5)
        : Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            width: 1.5,
          );

    return GestureDetector(
      onLongPress: _handleLongPress,
      child: Container(
        height: MediaQuery.of(context).size.width * 5 / 4,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: postBorder,
        ),
        child: ClipRRect(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(18),
          child: VisibilityDetector(
            key: Key('photo_${widget.post['id'] ?? widget.post['post_id']}'),
            onVisibilityChanged: (info) {
              if (info.visibleFraction >= 0.5 && !_hasRecordedView) {
                final postId = widget.post['id'] ?? widget.post['post_id'];
                if (postId != null) {
                  _api.recordView(postId.toString());
                  _hasRecordedView = true;
                }
              }
            },
            child: Container(
              color: Colors.black,
              child: SecureContentArea(
                enabled: isSubscriberOnlyContent,
                child: Stack(
                fit: StackFit.expand,
                children: [
                  // â”€â”€ Background & Image â”€â”€
                  if (isTextPost)
                    GestureDetector(
                      onDoubleTap: _handleDoubleTap,
                      child: _TextPostBackground(
                        bgStyle: (widget.post['bg_style'] ?? '').toString(),
                        caption: caption,
                      ),
                    )
                  else
                    GestureDetector(
                      onDoubleTap: _handleDoubleTap,
                      child: imageUrl.isEmpty
                          ? _buildImageError('empty media url', imageUrl)
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              memCacheWidth: 600,
                              memCacheHeight: 800,
                              placeholder: (p3_0, p3_1) =>
                                  Container(color: const Color(0xFF1E1E1E)),
                              errorWidget: (_, __, error) =>
                                  _buildImageError(error, imageUrl),
                            ),
                    ),

                  // 2b. Subscriber lock overlay
                  if (isLocked)
                    SubscriberLockOverlay(
                      creatorId: authorId,
                      creatorName: authorName,
                      creatorSubscriptionStatus: authorSubscriptionStatus,
                      onSubscribed: () {
                        if (mounted) setState(() {});
                      },
                    ),

                  // 3. Heart overlay
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

                  // 4. Top Overlay (User & Subscribe) — frosted gradient header
                  Positioned(
                    top: 0,
                    left: 40,
                    right: 40,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.65),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _navigateToProfile,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFFF2D55)
                                      .withValues(alpha: 0.65),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2D55)
                                        .withValues(alpha: 0.28),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: userAvatar.isNotEmpty &&
                                      userAvatar.startsWith('http')
                                  ? CircleAvatar(
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                              userAvatar),
                                      radius: 20,
                                    )
                                  : CircleAvatar(
                                      radius: 20,
                                      backgroundColor: const Color(0xFF3B82F6),
                                      child: Text(
                                        (username.toString().isNotEmpty
                                                ? username.toString()[0]
                                                : '?')
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _navigateToProfile,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black, blurRadius: 4),
                                      ],
                                    ),
                                  ),
                                  if (location.isNotEmpty)
                                    Text(
                                      location,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        fontSize: 11,
                                        shadows: const [
                                          Shadow(
                                              color: Colors.black,
                                              blurRadius: 4),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NeonSubscribeButton(
                                isSubscribed: isSubscribed || _isFollowing,
                                isOwnPost: _isOwnPost,
                                // Only show Subscribe style when the creator has
                                // an active plan AND explicitly turned on the
                                // feed-subscribe toggle. Otherwise show Follow.
                                showSubscribeMode:
                                    (widget.post['author_subscription_status']
                                                ?.toString() ??
                                            'inactive') ==
                                        'active' &&
                                    (widget.post['author_feed_action_subscribe'] ==
                                            1 ||
                                        widget.post['author_feed_action_subscribe'] ==
                                            true),
                                onTap: _handleFollow,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.post['views_unique'] ?? widget.post['views_total'] ?? widget.post['view_count'] ?? widget.post['views_count'] ?? widget.post['views'] ?? 0} Views',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4)
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 5. Right action column â€” compact
                  Positioned(
                    right: 6,
                    bottom: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionBtn(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          '$_likesCount',
                          _isLiked ? const Color(0xFFFF007F) : Colors.white,
                          _handleLike,
                        ),
                        const SizedBox(height: 14),
                        _buildActionBtn(
                          Icons.chat_bubble_outline_rounded,
                          '${widget.post['comments_count'] ?? 0}',
                          Colors.white,
                          _showCommentsSheet,
                        ),
                        const SizedBox(height: 14),
                        _buildActionBtn(
                          Icons.near_me_outlined,
                          'Share',
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
                      ],
                    ),
                  ),

                  // 5b. Gift overlay
                  Positioned(
                    left: 15,
                    bottom: 50,
                    right: 80,
                    child: _buildGiftOverlay(),
                  ),

                  // 5c. Gifter ticker (scrolling names + avatars sorted by value)
                  if (_giftOverlayData != null && _giftOverlayData!.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: _buildGifterTicker(),
                    ),

                  // 6. Caption
                  if (!isTextPost && caption.isNotEmpty)
                    Positioned(
                      left: 15,
                      bottom: 20,
                      right: 80,
                      child: Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _kCaptionStyle,
                      ),
                    ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Reshared / Reposted photo layout
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildResharedLayout({
    required String username,
    required String userAvatar,
    required String location,
    required String imageUrl,
    required String caption,
    required bool isSubscribed,
    required bool isTextPost,
  }) {
    // Resolve original post data (embedded by API)
    final originalPost = widget.post['original_post'] as Map<String, dynamic>?;
    final origUser = originalPost != null
        ? (originalPost['user'] as Map<String, dynamic>?)
        : null;

    // Original author info â€” from original_post.user, then fallbacks
    final originalUsername = (widget.post['original_user_name'] ??
            widget.post['original_username'] ??
            origUser?['name'] ??
            origUser?['username'] ??
            '')
        .toString();
    final originalFirstName = originalUsername.split(' ').first;
    final originalAvatar = _cleanUrl(
      origUser?['profile_pic'] ??
          origUser?['avatar_url'] ??
          origUser?['avatar'] ??
          widget.post['original_avatar'] ??
          // Fallback: use the resharer's own avatar
          userAvatar,
    );
    final originalUserId = (origUser?['id'] ??
            origUser?['user_id'] ??
            origUser?['uid'] ??
            widget.post['original_user_id'])
        ?.toString(); // DO NOT fallback to _resolvePostAuthorId() — that returns the resharer's ID

    // Image url for fullscreen viewer
    final viewerImageUrl =
        _resolveMediaUrl(originalPost ?? widget.post) ?? imageUrl;

    return GestureDetector(
      onLongPress: _handleLongPress,
      child: Container(
        height: MediaQuery.of(context).size.width * 5 / 4,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // â”€â”€ 1. Profile header â”€â”€
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final profileId = (originalUserId != null &&
                              originalUserId.isNotEmpty &&
                              originalUserId != '0')
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
                          builder: (_) => ProfileScreen(userId: profileId),
                        ),
                      );
                    },
                    child:
                        userAvatar.isNotEmpty && userAvatar.startsWith('http')
                            ? CircleAvatar(
                                backgroundImage: CachedNetworkImageProvider(
                                  userAvatar,
                                ),
                                radius: 20,
                              )
                            : CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF3B82F6),
                                child: Text(
                                  (username.toString().isNotEmpty
                                          ? username.toString()[0]
                                          : '?')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final profileId = (originalUserId != null &&
                                originalUserId.isNotEmpty &&
                                originalUserId != '0')
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
                            builder: (_) => ProfileScreen(userId: profileId),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            location.isNotEmpty
                                ? '$location · Reshare'
                                : 'Reshare',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeonSubscribeButton(
                        isSubscribed: isSubscribed || _isFollowing,
                        isOwnPost: _isOwnPost,
                        showSubscribeMode:
                            (widget.post['author_subscription_status']
                                        ?.toString() ??
                                    'inactive') ==
                                'active' &&
                            (widget.post['author_feed_action_subscribe'] == 1 ||
                                widget.post['author_feed_action_subscribe'] ==
                                    true),
                        onTap: _handleFollow,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.post['views_unique'] ?? widget.post['views_total'] ?? widget.post['view_count'] ?? widget.post['views_count'] ?? widget.post['views'] ?? 0} Views',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // â”€â”€ 2. Inner image card with white border â”€â”€
              Expanded(
                child: Stack(
                  children: [
                    // Photo card â€” tap opens fullscreen viewer
                    GestureDetector(
                      onDoubleTap: _handleDoubleTap,
                      onTap: () {
                        final url = viewerImageUrl;
                        if (url.isNotEmpty) {
                          showDialog(
                            context: context,
                            barrierColor: Colors.black87,
                            builder: (p4_0) => GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Scaffold(
                                backgroundColor: Colors.transparent,
                                body: Stack(
                                  children: [
                                    Center(
                                      child: InteractiveViewer(
                                        minScale: 0.5,
                                        maxScale: 4.0,
                                        child: CachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.contain,
                                          placeholder: (p5_0, p5_1) =>
                                              const Center(
                                            child: CircularProgressIndicator(
                                              color: Color(0xFF00E5FF),
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) =>
                                              const Icon(
                                            Icons.broken_image,
                                            color: Colors.white54,
                                            size: 48,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Close button
                                    Positioned(
                                      top: MediaQuery.of(context).padding.top +
                                          10,
                                      right: 16,
                                      child: GestureDetector(
                                        onTap: () => Navigator.pop(context),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: _kFullscreenCloseBtnDecoration,
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 22,
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
                      },
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: isTextPost
                              ? Container(
                                  decoration: _kTextPostInnerGradient,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        caption,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          shadows: [
                                            Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 6),
                                            Shadow(color: Color(0xFFEC4899), blurRadius: 16),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : imageUrl.isEmpty
                                  ? _buildImageError(
                                      'empty media url', imageUrl)
                                  : (widget.post['is_locked'] == 1 ||
                                          widget.post['is_locked'] == true)
                                      ? ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                            sigmaX: 8.0,
                                            sigmaY: 8.0,
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: imageUrl,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            memCacheWidth: 600,
                                            memCacheHeight: 800,
                                            errorWidget: (_, __, error) =>
                                                _buildImageError(
                                                    error, imageUrl),
                                          ),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          memCacheWidth: 600,
                                          memCacheHeight: 800,
                                          placeholder: (p6_0, p6_1) =>
                                              Container(
                                                  color:
                                                      const Color(0xFF1E1E1E)),
                                          errorWidget: (_, __, error) =>
                                              _buildImageError(error, imageUrl),
                                        ),
                        ),
                      ),
                    ),

                    // "Reshared from" badge â€” tap navigates to original user profile
                    Positioned(
                      top: 10,
                      left: 10,
                      child: GestureDetector(
                        onTap: () {
                          final profileId =
                              originalUserId ?? _resolvePostAuthorId();
                          if (profileId != null && profileId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (p7_0) =>
                                    ProfileScreen(userId: profileId),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.only(
                            left: 4,
                            right: 10,
                            top: 4,
                            bottom: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(
                                0xFF00E5FF,
                              ).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Original user avatar
                              originalAvatar.isNotEmpty &&
                                      originalAvatar.startsWith('http')
                                  ? CircleAvatar(
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                        originalAvatar,
                                      ),
                                      radius: 10,
                                    )
                                  : CircleAvatar(
                                      radius: 10,
                                      backgroundColor: const Color(0xFF3B82F6),
                                      child: Text(
                                        originalFirstName.isNotEmpty
                                            ? originalFirstName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                              const SizedBox(width: 6),
                              Text(
                                'Reshared from $originalFirstName',
                                style: _kReshareBadgeTextStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Heart animation overlay
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
                            size: 80,
                          ),
                        ),
                      ),

                    // Subscribe lock overlay
                    if (widget.post['is_locked'] == 1 ||
                        widget.post['is_locked'] == true)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SubscriberLockOverlay(
                            creatorId:
                                int.tryParse(_resolvePostAuthorId() ?? '0') ??
                                    0,
                            creatorName:
                                widget.post['author_name']?.toString() ?? '',
                            creatorSubscriptionStatus:
                                (widget.post['author_subscription_status'] ??
                                        'inactive')
                                    .toString(),
                            onSubscribed: () {
                              final ownerId = _resolvePostAuthorId();
                              if (ownerId != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (p8_0) =>
                                        ProfileScreen(userId: ownerId),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),

                    // Right action column â€” compact TikTok-style
                    Positioned(
                      right: 6,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionBtn(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            '$_likesCount',
                            _isLiked ? const Color(0xFFFF007F) : Colors.white,
                            _handleLike,
                          ),
                          const SizedBox(height: 14),
                          _buildActionBtn(
                            Icons.chat_bubble_outline_rounded,
                            '${widget.post['comments_count'] ?? 0}',
                            Colors.white,
                            _showCommentsSheet,
                          ),
                          const SizedBox(height: 14),
                          _buildActionBtn(
                            Icons.near_me_outlined,
                            'Share',
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
                        ],
                      ),
                    ),

                    // Gift overlay
                    Positioned(
                      left: 10,
                      bottom: 10,
                      right: 60,
                      child: _buildGiftOverlay(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // â”€â”€ 3. "Add your thoughts..." input â”€â”€
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showCommentsSheet,
                        child: const Text(
                          'Add your thoughts...',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showCommentsSheet,
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: _kThoughtsButtonDecoration,
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
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

  void _openGiftsSheet() {
    final uploaderId =
        (widget.post['user_id'] ?? widget.post['user']?['id'] ?? '').toString();
    final postId =
        (widget.post['id'] ?? widget.post['post_id'] ?? '').toString();
    GiftsSheet.show(
      context: context,
      toUserId: uploaderId,
      contextType: 'post',
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
      _api.fetchPostGifts(contextType: 'post', contextId: postId).then((raw) {
        if (!mounted) return;
        final gifts = raw.map((e) => GiftTx.fromJson(e)).toList();
        if (gifts.isNotEmpty) {
          setState(() => _giftOverlayData = gifts);
        }
      });
    }

    if (_giftOverlayData == null || _giftOverlayData!.isEmpty) {
      return const SizedBox.shrink();
    }
    return GiftOverlayWidget(gifts: _giftOverlayData!);
  }

  /// Horizontal auto-scrolling ticker strip showing gifters sorted by value
  Widget _buildGifterTicker() {
    if (_giftOverlayData == null || _giftOverlayData!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort by gift coins descending (most expensive first)
    final sorted = List<GiftTx>.from(_giftOverlayData!)
      ..sort((a, b) => b.coinPrice.compareTo(a.coinPrice));

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final g = sorted[index];
          final avatar = g.senderAvatar;
          final name = g.senderName.split(' ').first;
          final iconUrl = g.gifUrl;
          final senderId = g.senderId;
          return GestureDetector(
            onTap: () {
              if (senderId.isNotEmpty && senderId != '0') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (p9_0) => ProfileScreen(userId: senderId),
                  ),
                );
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gift icon
                if (iconUrl.isNotEmpty && iconUrl.startsWith('http'))
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CachedNetworkImage(
                      imageUrl: iconUrl,
                      memCacheWidth: 80,
                      memCacheHeight: 80,
                    ),
                  )
                else
                  const Icon(
                    Icons.card_giftcard,
                    color: Colors.amberAccent,
                    size: 16,
                  ),
                const SizedBox(width: 4),
                // Sender avatar
                avatar.isNotEmpty && avatar.startsWith('http')
                    ? CircleAvatar(
                        radius: 12,
                        backgroundImage: CachedNetworkImageProvider(avatar),
                      )
                    : CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFF3B82F6),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                const SizedBox(width: 4),
                // Sender first name
                Text(
                  name,
                  style: _kGifterNameStyle,
                ),
              ],
            ),
          );
        },
      ),
    );
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
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Task 2: _CommentsSheet â€” real comments with neon UI, reply, edit, delete
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

String _cleanValue(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

String _firstNonEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final cleaned = _cleanValue(value);
    if (cleaned.isNotEmpty) return cleaned;
  }
  return '';
}

String getAuthorName(Map c) {
  final user = c['user'] is Map ? c['user'] as Map : const {};
  final name = _firstNonEmpty([
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
  final avatar = _firstNonEmpty([
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
  final authorId = _firstNonEmpty([
    c['user_id'],
    c['uid'],
    user['user_id'],
    user['uid'],
    user['id'],
  ]);
  return authorId.isEmpty ? null : authorId;
}

/// Comment model for local state management
class _CommentModel {
  final String id;
  final String userId;
  final String username;
  final String avatar;
  final String text;
  final DateTime createdAt;
  final String? parentId; // For replies
  final List<_CommentModel> replies;
  final int gifterLevel;

  _CommentModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.text,
    required this.createdAt,
    this.parentId,
    List<_CommentModel>? replies,
    this.gifterLevel = 0,
  }) : replies = replies ?? [];

  factory _CommentModel.fromJson(Map<String, dynamic> json) {
    final totalCoins =
        int.tryParse((json['total_coins_sent'] ?? '0').toString()) ?? 0;
    final rawLevel =
        int.tryParse((json['gifter_level'] ?? '0').toString()) ?? 0;
    int level = rawLevel;
    if (rawLevel == 0 && totalCoins > 0) {
      if (totalCoins >= 5000000) { level = 6; }
      else if (totalCoins >= 1500000) { level = 5; }
      else if (totalCoins >= 500000)  { level = 4; }
      else if (totalCoins >= 200000)  { level = 3; }
      else if (totalCoins >= 50000)   { level = 2; }
      else if (totalCoins >= 10000)   { level = 1; }
    }
    return _CommentModel(
      id: (json['id'] ?? json['comment_id'] ?? '').toString(),
      userId: getAuthorId(json) ?? '',
      username: getAuthorName(json),
      avatar: getAuthorAvatar(json) ?? '',
      text: (json['comment'] ?? json['text'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ??
              DateTime.now(),
      parentId: json['parent_id']?.toString(),
      gifterLevel: level,
    );
  }

  _CommentModel copyWith({String? text}) {
    return _CommentModel(
      id: id,
      userId: userId,
      username: username,
      avatar: avatar,
      text: text ?? this.text,
      createdAt: createdAt,
      parentId: parentId,
      replies: replies,
      gifterLevel: gifterLevel,
    );
  }
}

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
  static const _kDark = Color(0xFF0D0020);

  static const _kHandleDecoration = BoxDecoration(
    gradient: LinearGradient(colors: [_kPink, _kCyan]),
    borderRadius: BorderRadius.all(Radius.circular(2)),
  );

  List<_CommentModel> _comments = [];
  bool _loading = true;
  final TextEditingController _ctrl = TextEditingController();
  bool _posting = false;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Reply state
  _CommentModel? _replyTarget;

  // Current user ID for ownership check
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

    // Parse comments and organize replies
    final List<_CommentModel> parentComments = [];
    final Map<String, _CommentModel> allComments = {};

    for (final json in c) {
      final comment = _CommentModel.fromJson(json);
      allComments[comment.id] = comment;
    }

    // Organize into parent/child structure
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

    if (_replyTarget != null) {}

    // Optimistic insert
    final tempComment = _CommentModel(
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
        // Add as reply
        final parentIdx = _comments.indexWhere((c) => c.id == _replyTarget!.id);
        if (parentIdx != -1) {
          _comments[parentIdx].replies.add(tempComment);
        }
      } else {
        // Add as top-level comment
        _comments.add(tempComment);
      }
    });

    _ctrl.clear();
    _replyTarget = null;

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    final newComment = await widget.api.postComment(widget.postId, text);

    if (mounted) {
      if (newComment != null) {
        final serverComment = _CommentModel.fromJson(newComment);
        setState(() {
          // Replace temp with real comment
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

  void _setReplyTarget(_CommentModel comment) {
    setState(() {
      _replyTarget = comment;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyTarget = null;
    });
  }

  void _editComment(_CommentModel comment, int parentIndex, {int? replyIndex}) {
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
            onPressed: () {
              Navigator.pop(ctx);
              _updateCommentText(
                comment,
                controller.text.trim(),
                parentIndex,
                replyIndex: replyIndex,
              );
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

  Future<void> _updateCommentText(
    _CommentModel comment,
    String newText,
    int parentIndex, {
    int? replyIndex,
  }) async {
    if (newText.isEmpty) return;

    // Optimistic update
    setState(() {
      if (replyIndex != null) {
        _comments[parentIndex].replies[replyIndex] = comment.copyWith(
          text: newText,
        );
      } else {
        _comments[parentIndex] = comment.copyWith(text: newText);
      }
    });

    // Call API to edit comment
    final success = await widget.api.editComment(comment.id, newText);

    if (success) {
    } else {
      // Revert on failure
      if (mounted) {
        setState(() {
          if (replyIndex != null) {
            _comments[parentIndex].replies[replyIndex] = comment;
          } else {
            _comments[parentIndex] = comment;
          }
        });
        NeonToast.error(context, 'Failed to edit comment');
      }
    }
  }

  Future<void> _deleteComment(
    _CommentModel comment,
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

    // Optimistic removal
    setState(() {
      if (replyIndex != null) {
        _comments[parentIndex].replies.removeAt(replyIndex);
      } else {
        _comments.removeAt(parentIndex);
      }
    });

    // Call API to delete
    final success = await widget.api.deleteComment(comment.id);

    if (success) {
    } else if (mounted) {
      // Show error - comment was already removed optimistically
      NeonToast.error(context, 'Failed to delete comment');
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _isOwnComment(_CommentModel comment) {
    return _currentUserId != null && comment.userId == _currentUserId;
  }

  void _openAuthorProfile(String? authorId) {
    final userId = (authorId ?? '').trim();
    if (userId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (p10_0) => ProfileScreen(userId: userId)),
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
          color: _kDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: _kCyan.withValues(alpha: 0.5), width: 1.5),
          ),
        ),
        child: Column(
          children: [
            // Handle
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

            // Comments List
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
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount:
                              _comments.length + (_replyTarget != null ? 1 : 0),
                          itemBuilder: (_, idx) {
                            // Reply indicator
                            if (idx == _comments.length &&
                                _replyTarget != null) {
                              return _buildReplyIndicator();
                            }

                            final comment = _comments[idx];
                            return _buildCommentItem(comment, idx);
                          },
                        ),
            ),

            // Input row
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                        ),
                        onSubmitted: (p11_0) => _submit(),
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

  Widget _buildReplyIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: const Icon(Icons.close, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(
    _CommentModel comment,
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
        boxShadow: [
          BoxShadow(color: neonColor.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Avatar, Name, Time, Menu
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      comment.username,
                                      style: TextStyle(
                                        color: neonColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (comment.gifterLevel > 0) ...[
                                      const SizedBox(width: 5),
                                      GifterBadge(level: comment.gifterLevel),
                                    ],
                                  ],
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
                // Reply button
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
                // More menu
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
                    ] else ...[
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
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Comment text
            Text(
              comment.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),

            // Replies
            if (comment.replies.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...comment.replies.asMap().entries.map((entry) {
                final replyIdx = entry.key;
                final reply = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: _buildReplyItem(reply, parentIndex, replyIdx),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReplyItem(_CommentModel reply, int parentIndex, int replyIndex) {
    final isOwn = _isOwnComment(reply);
    final neonColor = isOwn ? _kPink : _kPurple;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: neonColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: neonColor.withValues(alpha: 0.2), width: 1),
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
                      backgroundColor: neonColor.withValues(alpha: 0.2),
                      child: reply.avatar.isEmpty
                          ? Icon(Icons.person, color: neonColor, size: 12)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                reply.username,
                                style: TextStyle(
                                  color: neonColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(reply.createdAt),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
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
          // Mini menu for reply
          if (isOwn)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_horiz,
                color: Colors.white.withValues(alpha: 0.4),
                size: 16,
              ),
              color: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _kCyan.withValues(alpha: 0.3)),
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _editComment(reply, parentIndex, replyIndex: replyIndex);
                } else if (value == 'delete') {
                  _deleteComment(reply, parentIndex, replyIndex: replyIndex);
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
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Delete',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Text post background renderer ────────────────────────────────────────────
// Shares the same preset list as the publish screen so styled posts look
// identical in both the editor preview and the home feed.
class _TextPostBackground extends StatelessWidget {
  final String bgStyle;
  final String caption;

  const _TextPostBackground({required this.bgStyle, required this.caption});

  static const List<List<Color>> _presets = [
    [Color(0xFF0D0D1A), Color(0xFF1A1A2E)], // 0 Midnight
    [Color(0xFF1A0010), Color(0xFF3D0028)], // 1 Rose Noir
    [Color(0xFF001233), Color(0xFF003366)], // 2 Ocean Deep
    [Color(0xFF001A0A), Color(0xFF003316)], // 3 Forest
    [Color(0xFF7B1A1A), Color(0xFF3D1A0A)], // 4 Sunset
    [Color(0xFFFF007F), Color(0xFFBF00FF)], // 5 Neon Pink
    [Color(0xFF00C6FF), Color(0xFF0078FF)], // 6 Electric
    [Color(0xFF7B6000), Color(0xFFB38900)], // 7 Gold
    [Color(0xFF1A2E1A), Color(0xFF2E4A2E)], // 8 Sage
    [Color(0xFF0A0A0A), Color(0xFF1C1C1E)], // 9 Mono Dark
    [Color(0xFFFF69B4), Color(0xFFFF1493)], // 10 Candy
    [Color(0xFF003B2E), Color(0xFF7B00D4)], // 11 Aurora
  ];

  @override
  Widget build(BuildContext context) {
    final idx = int.tryParse(bgStyle) ?? 0;
    final colors = (idx >= 0 && idx < _presets.length)
        ? _presets[idx]
        : _presets[0];

    // Pick text color: light presets (5-Neon Pink, 6-Electric, 10-Candy) use white
    // with a dark shadow; darker presets use the neon cyan glow.
    final bool lightBg = idx == 6 || idx == 7 || idx == 10;
    final textColor = lightBg ? Colors.white : const Color(0xFF00E5FF);
    final shadowColor = lightBg
        ? Colors.black.withValues(alpha: 0.6)
        : const Color(0xFF00E5FF);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.4,
              shadows: [Shadow(color: shadowColor, blurRadius: 14)],
            ),
          ),
        ),
      ),
    );
  }
}
