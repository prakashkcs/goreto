import 'package:flutter/material.dart';

/// Compact "1.2K" style count.
String formatFeedCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.0', '')}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.0', '')}K';
  }
  return '$n';
}

/// Reads the view count from whichever key the API used.
int feedViewCount(Map post) {
  final raw = post['views_unique'] ??
      post['views_total'] ??
      post['view_count'] ??
      post['views_count'] ??
      post['views'] ??
      0;
  return int.tryParse('$raw') ?? 0;
}

/// Small glass pill: eye icon + "1.2K views".
class FeedViewsPill extends StatelessWidget {
  final int views;
  const FeedViewsPill({super.key, required this.views});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_rounded,
              color: Color(0xFF06B6D4), size: 13),
          const SizedBox(width: 5),
          Text(
            formatFeedCount(views),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 3),
          Text(views == 1 ? 'view' : 'views',
              style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// Caption (up to 2 lines) with the views pill directly under it, both on
/// the same left edge. Used at the bottom-left of feed photo/video cards so
/// the two never drift apart or overlap.
class FeedCaptionViews extends StatelessWidget {
  final String caption;
  final int views;
  const FeedCaptionViews(
      {super.key, required this.caption, required this.views});

  @override
  Widget build(BuildContext context) {
    final text = caption.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty) ...[
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(height: 7),
        ],
        FeedViewsPill(views: views),
      ],
    );
  }
}
