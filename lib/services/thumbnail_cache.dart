import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Singleton thumbnail cache.
/// Preload a batch of video URLs and all widgets will get instant
/// thumbnails from memory instead of waiting for on-demand extraction.
class ThumbnailCache {
  ThumbnailCache._();
  static final ThumbnailCache instance = ThumbnailCache._();

  // url → bytes (null entry means tried and failed)
  final Map<String, Uint8List?> _mem = {};
  // Prevent duplicate concurrent requests for the same URL
  final Map<String, Future<Uint8List?>> _inflight = {};

  /// Synchronous cache check. Returns null if not yet generated.
  Uint8List? get(String url) => _mem.containsKey(url) ? _mem[url] : null;

  bool isCached(String url) => _mem.containsKey(url);

  /// Fetch thumbnail — returns instantly if cached, otherwise extracts.
  Future<Uint8List?> fetch(String url) async {
    if (url.isEmpty) return null;
    if (_mem.containsKey(url)) return _mem[url];
    if (_inflight.containsKey(url)) return _inflight[url];

    final future = _generate(url);
    _inflight[url] = future;
    final result = await future;
    _inflight.remove(url);
    _mem[url] = result;
    return result;
  }

  /// Fire-and-forget preloading for a list of video URLs.
  /// Call this as soon as you have a list (e.g. after fetching the reel/feed list).
  void preload(List<String> urls) {
    for (final url in urls) {
      if (url.isNotEmpty && !_mem.containsKey(url) && !_inflight.containsKey(url)) {
        fetch(url);
      }
    }
  }

  Future<Uint8List?> _generate(String url) async {
    // Fast-start MP4s (MOOV atom at front) allow video_thumbnail to extract
    // the first frame by downloading only the header — fast even for network URLs.
    try {
      return await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360,
        quality: 55,
        timeMs: 0,
      );
    } catch (_) {
      return null;
    }
  }
}
