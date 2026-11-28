import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/match_user.dart';
import 'package:love_vibe_pro/services/profile_service.dart';

/// Full-screen, swipeable photos of a Matches card: profile photo and cover
/// first (shown instantly), then the person's photo posts as they load.
class MatchPhotoGallery extends StatefulWidget {
  final MatchUser user;
  const MatchPhotoGallery({super.key, required this.user});

  static Future<void> open(BuildContext context, MatchUser user) {
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => MatchPhotoGallery(user: user),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  State<MatchPhotoGallery> createState() => _MatchPhotoGalleryState();
}

class _MatchPhotoGalleryState extends State<MatchPhotoGallery> {
  final _page = PageController();
  late List<String> _photos;
  int _index = 0;
  bool _loadingMore = true;

  @override
  void initState() {
    super.initState();
    _photos = _unique([
      widget.user.photoUrl,
      widget.user.coverPicUrl ?? '',
    ]);
    _loadPosts();
  }

  List<String> _unique(Iterable<String> urls) {
    final seen = <String>{};
    return [
      for (final u in urls)
        if (u.startsWith('http') && seen.add(u)) u
    ];
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await ProfileService.instance
          .getUserPosts(userId: widget.user.id, limit: 30);
      final more = <String>[];
      for (final p in posts) {
        final type = (p['type'] ?? '').toString().toLowerCase();
        if (type == 'video' || type == 'reel') continue;
        if (p['is_locked'] == 1 || p['is_locked'] == true) continue;
        final url = (p['file_url'] ?? p['image_url'] ?? p['media_url'] ?? '')
            .toString()
            .trim();
        if (url.isNotEmpty) more.add(url);
      }
      if (!mounted) return;
      setState(() => _photos = _unique([..._photos, ...more]));
    } catch (_) {
      // Keep the photos we already have.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (count == 0)
            Center(
              child: _loadingMore
                  ? const CircularProgressIndicator(color: Color(0xFFFF007F))
                  : const Text('No photos yet',
                      style: TextStyle(color: Colors.white54)),
            )
          else
            PageView.builder(
              controller: _page,
              itemCount: count,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: _photos[i],
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFFF007F), strokeWidth: 2),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white24,
                        size: 64),
                  ),
                ),
              ),
            ),

          // Top: progress segments, name, close.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                children: [
                  if (count > 1)
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: i == _index
                                    ? const LinearGradient(colors: [
                                        Color(0xFFFF007F),
                                        Color(0xFF06B6D4)
                                      ])
                                    : null,
                                color: i == _index
                                    ? null
                                    : Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.user.name}${widget.user.age > 0 ? ', ${widget.user.age}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 8)
                            ],
                          ),
                        ),
                      ),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            '${_index + 1} / $count${_loadingMore ? '…' : ''}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF151515)
                                .withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFFFF007F)
                                    .withValues(alpha: 0.8),
                                width: 1.4),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
