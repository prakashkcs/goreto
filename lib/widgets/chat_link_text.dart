import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/media_url_builder.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlRe = RegExp(r'(https?://[^\s]+)', caseSensitive: false);
final _postUrlRe = RegExp(
  r'https?://(?:www\.)?goreto\.org/(?:[A-Za-z0-9_.\-]+/(\d+)|(?:ekloadmin/)?(?:api/v1/)?view_post\.php\?id=(\d+))/?$',
  caseSensitive: false,
);

/// Chat text that turns a shared Goreto post link into a preview card and
/// makes any other link tappable (a bare URL used to be inert text).
class ChatLinkText extends StatelessWidget {
  const ChatLinkText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    final post = _postUrlRe.firstMatch(trimmed);
    if (post != null) {
      return _PostLinkCard(postId: post.group(1) ?? post.group(2)!, url: trimmed);
    }
    if (!_urlRe.hasMatch(text)) return Text(text, style: style);

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(
          color: Color(0xFF7DD3FC),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF7DD3FC),
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _PostLinkCard extends StatefulWidget {
  const _PostLinkCard({required this.postId, required this.url});
  final String postId;
  final String url;

  @override
  State<_PostLinkCard> createState() => _PostLinkCardState();
}

class _PostLinkCardState extends State<_PostLinkCard> {
  // Chats re-render often; keep one fetch per post for the app session.
  static final Map<String, Future<Map<String, dynamic>?>> _cache = {};

  late final Future<Map<String, dynamic>?> _post =
      _cache.putIfAbsent(widget.postId, () => ApiService().getPostById(widget.postId));

  String _thumb(Map<String, dynamic> p) {
    final type = (p['type'] ?? '').toString().toLowerCase();
    final isVideo = type == 'video' || type == 'reel';
    final raw = isVideo
        ? (p['thumbnail_url'] ?? '')
        : (p['thumbnail_url'] ?? '').toString().isNotEmpty
            ? p['thumbnail_url']
            : (p['image_url'] ?? p['file_url'] ?? '');
    return normalizeMediaUrl(raw, baseUrl: AppEnv.baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: widget.postId)),
      ),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF007F).withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _post,
          builder: (context, snap) {
            final p = snap.data;
            final thumb = p == null ? '' : _thumb(p);
            final type = (p?['type'] ?? '').toString().toLowerCase();
            final isVideo = type == 'video' || type == 'reel';
            final author = (p?['author_name'] ?? p?['author_username'] ?? '').toString();
            final caption = (p?['caption'] ?? '').toString().trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF1A1A2E)),
                      if (thumb.startsWith('http'))
                        CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          memCacheWidth: 500,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        )
                      else if (snap.connectionState != ConnectionState.done)
                        const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF007F)),
                          ),
                        )
                      else if (caption.isNotEmpty && !isVideo)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Center(
                            child: Text(caption,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 44),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.isNotEmpty ? author : (p == null && snap.connectionState == ConnectionState.done ? 'Post unavailable' : 'Goreto post'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      if (caption.isNotEmpty && (thumb.startsWith('http') || isVideo))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
