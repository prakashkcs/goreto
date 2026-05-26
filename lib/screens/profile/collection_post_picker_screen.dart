import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/models/collection.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Multi-select grid of the current user's photos & reels.
/// Returns true if at least one post was successfully added.
class CollectionPostPickerScreen extends StatefulWidget {
  final Collection collection;

  const CollectionPostPickerScreen({super.key, required this.collection});

  @override
  State<CollectionPostPickerScreen> createState() =>
      _CollectionPostPickerScreenState();
}

class _CollectionPostPickerScreenState
    extends State<CollectionPostPickerScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _posts = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? '';
    if (uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final posts = await ProfileService.instance.getUserPosts(
      userId: uid,
      viewerId: uid,
    );
    if (!mounted) return;
    setState(() {
      _posts = posts
          .where((p) {
            final type = (p['type'] ?? '').toString().toLowerCase();
            return type == 'image' || type == 'photo' || type == 'reel' || type == 'video';
          })
          .toList();
      _loading = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _adding = true);

    int added = 0;
    for (final postId in _selected) {
      final ok = await _api.addPostToCollection(
        collectionId: widget.collection.id,
        postId: postId,
      );
      if (ok) added++;
    }

    if (!mounted) return;
    setState(() => _adding = false);

    if (added > 0) {
      NeonToast.success(context, '$added post${added > 1 ? 's' : ''} added!');
      Navigator.pop(context, true);
    } else {
      NeonToast.error(context, 'Failed to add posts');
    }
  }

  String _thumb(Map<String, dynamic> p) {
    return (p['thumbnail_url'] ?? p['image_url'] ?? p['file_url'] ?? p['media_url'] ?? '')
        .toString()
        .trim();
  }

  String _postId(Map<String, dynamic> p) {
    return (p['id'] ?? p['post_id'] ?? '').toString();
  }

  bool _isVideo(Map<String, dynamic> p) {
    final t = (p['type'] ?? '').toString().toLowerCase();
    return t == 'reel' || t == 'video';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0B14),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Column(
          children: [
            const Text(
              'Add to Collection',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.collection.title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _adding ? null : _addSelected,
              child: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF007F),
                      ),
                    )
                  : Text(
                      'Add (${_selected.length})',
                      style: const TextStyle(
                        color: Color(0xFFFF007F),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF007F)),
            )
          : _posts.isEmpty
              ? _buildEmpty()
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: _posts.length,
                  itemBuilder: (_, i) => _buildItem(_posts[i]),
                ),
      bottomNavigationBar: _selected.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      onPressed: _adding ? null : _addSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _adding
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Add ${_selected.length} Post${_selected.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildItem(Map<String, dynamic> post) {
    final id = _postId(post);
    final thumb = _thumb(post);
    final selected = _selected.contains(id);
    final isVideo = _isVideo(post);

    return GestureDetector(
      onTap: () => _toggle(id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          thumb.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _placeholder(isVideo),
                )
              : _placeholder(isVideo),

          // Dim overlay when selected
          if (selected)
            Container(color: const Color(0xFFFF007F).withValues(alpha: 0.35)),

          // Video indicator
          if (isVideo && !selected)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.play_circle_filled, color: Colors.white70, size: 18),
            ),

          // Check mark
          if (selected)
            const Center(
              child: Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 32),
            ),

          // Selection ring border
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFF007F),
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(bool isVideo) {
    return Container(
      color: const Color(0xFF1A1525),
      child: Icon(
        isVideo ? Icons.videocam : Icons.image,
        color: Colors.white24,
        size: 28,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined,
              color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          Text(
            'No photos or reels yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
