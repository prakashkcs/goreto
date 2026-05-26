import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';

class FeedController extends ChangeNotifier {
  FeedController._();
  static final FeedController instance = FeedController._();

  final ApiService _api = ApiService();

  List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
  bool isLoading = false;
  bool hasLoadedOnce = false;

  Future<void> loadFeed({bool force = false}) async {
    if (isLoading) return;
    // Skip only if we already loaded AND got real data.
    // If items is empty after a previous load (empty API response / network blip),
    // always retry so the user never stares at a blank feed.
    if (hasLoadedOnce && !force && items.isNotEmpty) return;

    // Load from cache instantly if memory is empty
    if (items.isEmpty) {
      await _loadFromCache();
      if (items.isNotEmpty) notifyListeners();
    }

    isLoading = items.isEmpty; // Only show spinner if cache was empty

    try {
      final fetched = await _api.getFeed(force: force);
      final newItems = fetched
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      // Only replace items if the server returned actual data.
      // An empty response (even on force-refresh) means the API failed silently
      // — never wipe visible posts with an empty list.
      if (newItems.isNotEmpty) {
        items = newItems;
        _saveToCache(items);
        // Preload thumbnails for video/reel posts that have no stored thumbnail
        final videoUrls = newItems
            .where((p) {
              final t = (p['type'] ?? '').toString().toLowerCase();
              return t == 'video' || t == 'reel';
            })
            .map((p) {
              final thumb = (p['thumbnail_url'] ?? '').toString().trim();
              if (thumb.isNotEmpty && thumb.startsWith('http')) return null;
              return (p['file_url'] ?? p['video_url'] ?? p['media_url'] ?? '')
                  .toString()
                  .trim();
            })
            .where((u) => u != null && u.isNotEmpty && u.startsWith('http'))
            .cast<String>()
            .toList();
        ThumbnailCache.instance.preload(videoUrls);
      }
      hasLoadedOnce = true;
    } catch (_) {
      // Network/parse error — keep existing items so the user sees something
    } finally {
      isLoading = false;
      notifyListeners(); // Single notify at end
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString('cached_feed_items');
      if (cachedString != null && cachedString.isNotEmpty) {
        final decoded = jsonDecode(cachedString);
        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveToCache(List<Map<String, dynamic>> newItems) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only top 20 items in cache to save disk space and speed up decoding
      final toSave = newItems.take(20).toList();
      await prefs.setString('cached_feed_items', jsonEncode(toSave));
    } catch (_) {}
  }

  void prependServerPost(Map<String, dynamic> post) {
    items.removeWhere((p) => _isMediaType(p) && _mediaUrl(p).isEmpty);

    final pid = (post['id'] ?? post['post_id']).toString();
    items.removeWhere((p) => (p['id'] ?? p['post_id']).toString() == pid);
    items.insert(0, Map<String, dynamic>.from(post));
    notifyListeners();
  }

  void removePostById(dynamic postId) {
    final pid = postId?.toString();
    if (pid == null || pid.isEmpty) return;
    items.removeWhere((p) => (p['id'] ?? p['post_id']).toString() == pid);
    notifyListeners();
  }

  String _mediaUrl(Map<String, dynamic> p) {
    return (p['file_url'] ??
            p['image_url'] ??
            p['media_url'] ??
            p['image'] ??
            p['photo'] ??
            p['raw_file_url'] ??
            '')
        .toString();
  }

  bool _isMediaType(Map<String, dynamic> p) {
    final type = (p['type'] ?? 'image').toString().toLowerCase();
    return type == 'image' || type == 'video' || type == 'reel';
  }
}
