import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Audio that starts playing without the iOS lag.
///
/// On iOS, audioplayers streams a [UrlSource] through AVPlayer, which buffers
/// for several seconds before it starts ("minimise stalling"), so sounds,
/// voice notes and music previews felt laggy. Clips here are small (sounds are
/// AAC capped at 60 s), so download once into the disk cache and play the
/// local file — instant from the second play on, and still streaming-fast the
/// first time. Falls back to the URL if the download fails.
class FastAudio {
  static final CacheManager _cache = CacheManager(Config(
    'goreto_audio',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 300,
  ));

  static Future<Source> source(String url,
      {Duration timeout = const Duration(seconds: 12)}) async {
    if (!url.startsWith('http')) return DeviceFileSource(url);
    try {
      final cached = await _cache.getFileFromCache(url);
      if (cached != null && await cached.file.exists()) {
        return DeviceFileSource(cached.file.path);
      }
      final file = await _cache.getSingleFile(url).timeout(timeout);
      return DeviceFileSource(file.path);
    } catch (_) {
      return UrlSource(url);
    }
  }

  /// Warm the cache ahead of time (e.g. for the next post), fire-and-forget.
  static void prefetch(String url) {
    if (!url.startsWith('http')) return;
    unawaited(_cache.getSingleFile(url).then((_) {}, onError: (_) {}));
  }

  /// One audio session for the whole app on iOS: playback that mixes with the
  /// video player instead of both fighting over AVAudioSession (which caused
  /// stutters when a post sound and a video overlapped). Call once at start.
  static Future<void> configureSession() async {
    if (!Platform.isIOS) return;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ));
    } catch (_) {}
  }
}
