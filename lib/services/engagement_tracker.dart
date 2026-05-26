import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/analytics_service.dart';

/// Tracks user engagement to build an interest model.
/// Signals are stored locally and attached to feed/reels requests so the
/// backend (or client-side re-ranker) can personalise content.
class EngagementTracker {
  static final EngagementTracker _instance = EngagementTracker._();
  factory EngagementTracker() => _instance;
  EngagementTracker._();

  static const String _prefKey = 'engagement_tracker_v2';

  // Category weights (higher = more interested)
  final Map<String, double> _scores = {};

  // Session watch-time per post (postId -> seconds elapsed)
  final Map<String, int> _sessionWatchSeconds = {};

  // Trending sound / hashtag frequency this session
  final Map<String, int> _trendingSignals = {};

  bool _loaded = false;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          _scores[k] = (v as num).toDouble();
        });
      } catch (_) {}
    }
    _loaded = true;
  }

  /// Call when a post/reel becomes visible in the feed.
  Future<void> recordImpression(dynamic post) async {
    await ensureLoaded();
    _bumpFromPost(post, delta: 0.05);
  }

  /// Call when the user watches a video — pass elapsed seconds.
  Future<void> recordWatchTime(dynamic post, int seconds) async {
    await ensureLoaded();
    final postId = (post['id'] ?? post['post_id'] ?? '').toString();
    if (postId.isEmpty) return;

    final existing = _sessionWatchSeconds[postId] ?? 0;
    _sessionWatchSeconds[postId] = existing + seconds;

    // Reward categories proportional to watch time (capped per post)
    final reward = (seconds / 30.0).clamp(0.0, 2.0);
    _bumpFromPost(post, delta: reward);
    await _persist();

    // Fire server engagement signal
    _sendEngagement(post, 'watch', seconds);

    // Deep analytics batch event
    final totalWatched = _sessionWatchSeconds[postId] ?? seconds;
    final duration =
        int.tryParse((post['duration'] ?? post['duration_sec'] ?? 0).toString()) ?? 0;
    final watchPct = duration > 0
        ? ((totalWatched * 100) ~/ duration).clamp(0, 100)
        : 0;
    AnalyticsService.instance.trackWatchComplete(
      postId: postId,
      watchPct: watchPct,
      durationSec: duration,
    );
  }

  /// Call on like, comment, or share.
  Future<void> recordInteraction(dynamic post, {String action = 'like'}) async {
    await ensureLoaded();
    final delta = action == 'like'
        ? 1.0
        : action == 'comment'
            ? 1.5
            : 0.5;
    _bumpFromPost(post, delta: delta);
    await _persist();
  }

  /// Call when user follows a creator — boost the creator's content categories.
  Future<void> recordFollow(dynamic post) async {
    await ensureLoaded();
    _bumpFromPost(post, delta: 2.0);
    await _persist();
  }

  /// Call when user skips a reel quickly (< 2 s viewed).
  Future<void> recordSkip(dynamic post, {int seconds = 0, String source = 'feed'}) async {
    await ensureLoaded();
    _bumpFromPost(post, delta: -0.1);
    await _persist();
    // Fire-and-forget server signal
    _sendEngagement(post, 'skip', 0);

    // Deep analytics batch event
    final postId = (post['id'] ?? post['post_id'] ?? '').toString();
    if (postId.isNotEmpty) {
      AnalyticsService.instance.trackImpression(
        postId: postId,
        source: source,
        watchPct: 0,
        timeSpentMs: seconds * 1000,
      );
    }
  }

  /// Send engagement signal to server (fire-and-forget).
  void _sendEngagement(dynamic post, String action, int watchSeconds) {
    final postId = (post['id'] ?? post['post_id'] ?? '').toString();
    if (postId.isEmpty || postId == '0') return;
    // Lazy import to avoid circular dependency — use a callback if set
    _onEngagement?.call(postId, action, watchSeconds);
  }

  /// Set by ApiService to receive engagement events without circular import.
  void Function(String postId, String action, int watchSeconds)? _onEngagement;

  void setEngagementCallback(
      void Function(String postId, String action, int watchSeconds) cb) {
    _onEngagement = cb;
  }

  /// Record trending sound/hashtag usage.
  Future<void> recordTrending(String tag) async {
    _trendingSignals[tag] = (_trendingSignals[tag] ?? 0) + 1;
  }

  /// Returns the interest vector as a URL-safe JSON string for attaching to API calls.
  Future<String> interestParam() async {
    await ensureLoaded();
    if (_scores.isEmpty) return '';
    // Top 6 categories by score
    final sorted = _scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = Map.fromEntries(sorted
        .take(6)
        .map((e) => MapEntry(e.key, double.parse(e.value.toStringAsFixed(2)))));
    return jsonEncode(top);
  }

  /// Returns the top interest categories sorted by score.
  Future<List<String>> topInterests({int limit = 5}) async {
    await ensureLoaded();
    if (_scores.isEmpty) return [];
    final sorted = _scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Re-ranks a list of feed posts by estimated relevance to the user.
  Future<List<dynamic>> rerankFeed(List<dynamic> posts) async {
    await ensureLoaded();
    if (_scores.isEmpty || posts.length <= 3) return posts;

    // Score each post
    final scored = posts.map((post) {
      double score = 0;
      final type = (post['type'] ?? '').toString().toLowerCase();
      final hashtags = (post['hashtags'] ?? '').toString().toLowerCase();
      final soundName = (post['sound_name'] ?? post['music_name'] ?? '')
          .toString()
          .toLowerCase();
      final isVideo = type == 'video' || type == 'reel';
      final isFollowing =
          post['is_following'] == true || post['is_following'] == 1;
      final likes = int.tryParse(
              (post['likes_count'] ?? post['likes'] ?? '0').toString()) ??
          0;
      final views = int.tryParse(
              (post['views_count'] ?? post['views'] ?? '0').toString()) ??
          0;

      // Virality signal (high engagement)
      if (likes > 1000) score += 0.5;
      if (likes > 10000) score += 1.0;
      if (views > 100000) score += 1.0;

      // Following boost
      if (isFollowing) score += 1.5;

      // Content type preference
      if (isVideo && (_scores['video'] ?? 0) > 0)
        score += (_scores['video'] ?? 0) * 0.5;
      if (!isVideo && (_scores['photo'] ?? 0) > 0)
        score += (_scores['photo'] ?? 0) * 0.5;

      // Category tags in hashtags
      _scores.forEach((category, weight) {
        if (hashtags.contains(category) || soundName.contains(category)) {
          score += weight * 0.3;
        }
      });

      return _ScoredPost(post: post, score: score);
    }).toList();

    // Sort by score descending, preserve followed-user posts near top
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.post).toList();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _bumpFromPost(dynamic post, {required double delta}) {
    // Content type
    final type = (post['type'] ?? '').toString().toLowerCase();
    final isVideo = type == 'video' ||
        type == 'reel' ||
        (post['file_url'] ?? post['video_url'] ?? '')
            .toString()
            .toLowerCase()
            .endsWith('.mp4');

    _bump(isVideo ? 'video' : 'photo', delta);

    // Hashtag categories
    final hashtags = (post['hashtags'] ?? '').toString().toLowerCase();
    for (final cat in _knownCategories) {
      if (hashtags.contains(cat)) _bump(cat, delta * 0.4);
    }

    // Sound / music interest
    final soundName =
        (post['sound_name'] ?? post['music_name'] ?? '').toString();
    if (soundName.isNotEmpty) _bump('music', delta * 0.3);

    // Caption keywords
    final caption = (post['caption'] ?? '').toString().toLowerCase();
    for (final cat in _knownCategories) {
      if (caption.contains(cat)) _bump(cat, delta * 0.2);
    }
  }

  void _bump(String category, double delta) {
    final current = _scores[category] ?? 0.0;
    // Decay existing score slightly to prevent stale preferences dominating
    _scores[category] = (current * 0.98 + delta).clamp(-5.0, 20.0);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_scores));
  }

  static const List<String> _knownCategories = [
    'love',
    'romance',
    'fashion',
    'beauty',
    'fitness',
    'gym',
    'food',
    'travel',
    'music',
    'dance',
    'humor',
    'comedy',
    'gaming',
    'tech',
    'motivation',
    'lifestyle',
    'art',
    'photography',
    'nature',
    'sports',
  ];
}

class _ScoredPost {
  final dynamic post;
  final double score;
  const _ScoredPost({required this.post, required this.score});
}
