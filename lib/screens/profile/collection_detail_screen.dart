import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/collection.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/profile/collection_post_picker_screen.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';

/// Full-screen view of all posts inside a single collection.
/// Automatically records a view when opened.
class CollectionDetailScreen extends StatefulWidget {
  final Collection collection;
  final bool canAddPosts;

  const CollectionDetailScreen({
    super.key,
    required this.collection,
    this.canAddPosts = false,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _posts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAndTrack();
  }

  Future<void> _loadAndTrack() async {
    // Record a view (fire-and-forget)
    _api.recordCollectionView(widget.collection.id);

    try {
      final posts = await _api.getCollectionPosts(widget.collection.id);
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openPicker() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CollectionPostPickerScreen(collection: widget.collection),
      ),
    );
    if (added == true) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      _loadAndTrack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: widget.canAddPosts
          ? FloatingActionButton(
              onPressed: _openPicker,
              backgroundColor: const Color(0xFFFF007F),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.collection.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${widget.collection.itemCount} items',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD946EF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFD946EF).withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.collections_bookmark,
                  color: Color(0xFFD946EF),
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  'Collection',
                  style: TextStyle(
                    color: Color(0xFFD946EF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFD946EF)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadAndTrack();
              },
              child: const Text(
                'Retry',
                style: TextStyle(color: Color(0xFFD946EF)),
              ),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'This collection is empty',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            if (widget.canAddPosts) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _openPicker,
                child: const Text(
                  'Tap + to add photos & reels',
                  style: TextStyle(color: Color(0xFFFF007F), fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) => _buildPostTile(_posts[index]),
    );
  }

  Widget _buildPostTile(Map<String, dynamic> post) {
    final String type = (post['type'] ?? 'photo').toString();
    final bool isVideo = type == 'reel' || type == 'video';
    // Always use thumbnail for grid display; fall back to file_url for photos
    final String thumbUrl = (post['thumbnail_url'] ?? '').toString().trim();
    final String fileUrl = (post['media_url'] ?? post['file_url'] ?? '').toString().trim();
    final String displayUrl = thumbUrl.isNotEmpty ? thumbUrl : (isVideo ? '' : fileUrl);
    final int views = int.tryParse(
          (post['views_total'] ?? post['view_count'] ?? post['views'] ?? 0)
              .toString(),
        ) ??
        0;
    final String postId = (post['id'] ?? '').toString();

    return GestureDetector(
      onTap: () {
        if (postId.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              postId: postId,
              initialPost: post,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFD946EF).withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              displayUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: displayUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallback(isVideo),
                    )
                  : _fallback(isVideo),
              // Video indicator
              if (isVideo)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    Icons.play_circle_filled,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              // Views
              Positioned(
                bottom: 3,
                left: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_fmt(views)} Views',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 8,
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

  Widget _fallback(bool isVideo) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Icon(
        isVideo ? Icons.videocam : Icons.image,
        color: Colors.white24,
        size: 24,
      ),
    );
  }

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }
}
