import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/photo_feed_item.dart';
import 'package:love_vibe_pro/widgets/video_feed_item.dart';

/// Shows a single post in full feed style (PhotoFeedItem / VideoFeedItem)
/// with all the same like, comment, share options as the home feed.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPost;

  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null && widget.initialPost!.isNotEmpty) {
      _post = Map<String, dynamic>.from(widget.initialPost!);
      _loading = false;
    }
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && _post != null) return;
    if (mounted) setState(() => _loading = true);

    try {
      // Try the dedicated single-post endpoint first
      final fetched = await _api.getPostById(widget.postId);
      if (fetched != null) {
        if (mounted) setState(() { _post = fetched; _loading = false; });
        return;
      }

      // Fall back: search the feed
      final feed = await _api.getFeed();
      final found = feed.cast<dynamic>().firstWhere(
        (item) => ((item is Map ? (item['id'] ?? item['post_id']) : null))
            ?.toString() == widget.postId,
        orElse: () => null,
      );
      if (mounted) {
        setState(() {
          _post = found is Map ? Map<String, dynamic>.from(found) : null;
          _loading = false;
          if (_post == null) _error = 'Post not found';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load'; });
    }
  }

  bool _isVideo(Map<String, dynamic> post) {
    final type = (post['type'] ?? post['post_type'] ?? '').toString().toLowerCase();
    final url = (post['file_url'] ?? post['media_url'] ?? post['video_url'] ?? '').toString().toLowerCase();
    return type == 'video' || type == 'reel' ||
        url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _post == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF007F))),
      );
    }

    if (_post == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Post unavailable',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _load(force: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final post = _post!;
    final isVideo = _isVideo(post);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          (post['author_name'] ?? post['author_username'] ?? '').toString().isNotEmpty
              ? (post['author_name'] ?? '').toString()
              : 'Post',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        child: isVideo
            ? VideoFeedItem(
                post: post,
              )
            : PhotoFeedItem(
                post: post,
              ),
      ),
    );
  }
}
