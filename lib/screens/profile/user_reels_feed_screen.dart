import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/reels_video_player.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:share_plus/share_plus.dart';

class UserReelsFeedScreen extends StatefulWidget {
  final List<dynamic> posts;
  final int initialIndex;
  final String userName;

  const UserReelsFeedScreen({
    super.key,
    required this.posts,
    this.initialIndex = 0,
    this.userName = 'User',
  });

  @override
  State<UserReelsFeedScreen> createState() => _UserReelsFeedScreenState();
}

class _UserReelsFeedScreenState extends State<UserReelsFeedScreen> {
  late PageController _pageController;
  final ApiService _apiService = ApiService();
  int _currentIndex = 0;
  final Set<String> _likedReelIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideoPost(Map<String, dynamic> post) {
    final type = (post['type'] ?? '').toString().toLowerCase();
    final media =
        (post['video_url'] ?? post['file_url'] ?? post['media_url'] ?? '')
            .toString()
            .toLowerCase();
    return type == 'video' ||
        type == 'reel' ||
        media.endsWith('.mp4') ||
        media.endsWith('.mov') ||
        media.endsWith('.m4v') ||
        media.endsWith('.webm');
  }

  String _pickMediaUrl(Map<String, dynamic> post, bool isVideo) {
    if (isVideo) {
      return (post['video_url'] ?? post['file_url'] ?? post['media_url'] ?? '')
          .toString();
    }
    return (post['image_url'] ??
            post['file_url'] ??
            post['media_url'] ??
            post['thumbnail_url'] ??
            '')
        .toString();
  }

  bool _isReelLiked(dynamic reel) {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (_likedReelIds.contains(postId)) return true;
    return reel['is_liked'] == true || reel['is_liked'] == 1;
  }

  Future<void> _handleLike(dynamic reel, {bool fromDoubleTap = false}) async {
    final postId = (reel['id'] ?? reel['post_id'] ?? '').toString();
    if (postId.isEmpty) return;

    final alreadyLiked = _isReelLiked(reel);
    if (fromDoubleTap && alreadyLiked) return;

    await SoundService().playReact();

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

    final result = await _apiService.likePostToggle(postId);
    if (mounted) {
      setState(() {
        final rawLiked = result['liked'];
        final serverLiked =
            rawLiked == true || rawLiked == 1 || rawLiked == '1';
        if (serverLiked) {
          _likedReelIds.add(postId);
        } else {
          _likedReelIds.remove(postId);
        }
        reel['is_liked'] = serverLiked;
      });
    }
  }

  String _formatCount(dynamic value) {
    final intValue = int.tryParse(value.toString()) ?? 0;
    if (intValue >= 1000000) {
      return '${(intValue / 1000000).toStringAsFixed(1)}M';
    }
    if (intValue >= 1000) return '${(intValue / 1000).toStringAsFixed(1)}K';
    return intValue.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const SafeArea(
          child: Center(
            child: Text(
              "No posts found",
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "${widget.userName}'s Posts",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        onPageChanged: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
        itemBuilder: (context, index) {
          final post = widget.posts[index];
          final isVideo = _isVideoPost(post);
          final mediaUrl = _pickMediaUrl(post, isVideo);
          final caption = (post['caption'] ?? '').toString();
          final isLiked = _isReelLiked(post);
          final likesCount = _formatCount(post['likes_count'] ?? post['likes']);
          final commentsCount = _formatCount(
            post['comments_count'] ?? post['comments'],
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // Media Layer
              if (isVideo)
                ReelsVideoPlayer(
                  videoUrl: mediaUrl,
                  thumbnailUrl:
                      (post['thumbnail_url'] ?? post['image_url'] ?? '')
                          .toString(),
                  isActive: _currentIndex == index,
                  onDoubleTapLike: () => _handleLike(post, fromDoubleTap: true),
                )
              else
                GestureDetector(
                  onDoubleTap: () => _handleLike(post, fromDoubleTap: true),
                  child: mediaUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: mediaUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white24,
                              size: 64,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.white24,
                            size: 64,
                          ),
                        ),
                ),

              // Bottom Overlay Graident
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 300,
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Text & Caption
              Positioned(
                bottom: 40,
                left: 16,
                right: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "@${widget.userName}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Right Action Buttons
              Positioned(
                bottom: 40,
                right: 12,
                child: Column(
                  children: [
                    _buildActionButton(
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? const Color(0xFFFF007F) : Colors.white,
                      label: likesCount,
                      onTap: () => _handleLike(post),
                    ),
                    const SizedBox(height: 20),
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      color: Colors.white,
                      label: commentsCount,
                      onTap: () {
                        // Routing to PostDetailScreen for comments
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PostDetailScreen(
                              postId:
                                  (post['id'] ?? post['post_id']).toString(),
                              initialPost: post,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildActionButton(
                      icon: Icons.share_rounded,
                      color: const Color(0xFF00E5FF),
                      label: 'Share',
                      onTap: () => _showShareSheet(post),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showShareSheet(dynamic post) async {
    final postId = (post['id'] ?? post['post_id'] ?? '').toString();
    final caption = (post['caption'] ?? '').toString();
    final mediaUrl = _pickMediaUrl(post, _isVideoPost(post));
    final baseUrl = await AppEnv.getBaseUrlAsync();
    final postUrl = '$baseUrl/view_post.php?id=$postId';

    final shareText = caption.isNotEmpty
        ? '$caption\n\n$postUrl'
        : 'Check out this post!\n\n$postUrl';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Share Post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF00E5FF)),
              title: const Text(
                'Send to Chat',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Send post link to a contact',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _shareToChat(postUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group, color: Color(0xFFD946EF)),
              title: const Text(
                'Share to Group',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Post link in a group chat',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _shareToGroup(postUrl);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.share_rounded,
                color: Color(0xFF22C55E),
              ),
              title: const Text(
                'Share to External Apps',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Share via other apps',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(shareText);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToChat(String postUrl) async {
    if (!mounted) return;
    // Navigate to chat list - user can then paste link manually
    // For now, just copy to clipboard and show toast
    await Clipboard.setData(ClipboardData(text: postUrl));
    if (mounted) {
      NeonToast.success(context, 'Link copied! Paste it in chat');
    }
  }

  Future<void> _shareToGroup(String postUrl) async {
    if (!mounted) return;
    // Copy to clipboard for now
    await Clipboard.setData(ClipboardData(text: postUrl));
    if (mounted) {
      NeonToast.success(context, 'Link copied! Paste it in group chat');
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
