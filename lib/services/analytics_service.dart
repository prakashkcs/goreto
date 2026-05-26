import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Batched analytics service — queues events locally and flushes them to
/// `analytics.php?action=batch` every 30 seconds, when 20 events accumulate,
/// or when the app goes to background.
class AnalyticsService with WidgetsBindingObserver {
  // Singleton
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  // Queue of events to send
  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    flush(); // flush remaining
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      flush();
    }
  }

  /// Track when a post appears in the feed.
  void trackImpression({
    required String postId,
    required String source, // 'feed', 'explore', 'following', 'reels'
    int watchPct = 0,
    int timeSpentMs = 0,
    bool rewatched = false,
  }) {
    _enqueue({
      'type': 'impression',
      'post_id': postId,
      'source': source,
      'watch_pct': watchPct,
      'time_spent_ms': timeSpentMs,
      'rewatched': rewatched ? 1 : 0,
    });
  }

  void trackWatchComplete({
    required String postId,
    required int watchPct,
    int durationSec = 0,
  }) {
    _enqueue({
      'type': 'watch_complete',
      'post_id': postId,
      'watch_pct': watchPct,
      'duration_sec': durationSec,
    });
  }

  void trackSave({required String postId}) {
    _enqueue({'type': 'save', 'post_id': postId});
  }

  void trackProfileVisit({
    required String postId,
    required String creatorId,
  }) {
    _enqueue({
      'type': 'profile_visit',
      'post_id': postId,
      'creator_id': creatorId,
    });
  }

  void trackShare({required String postId}) {
    _enqueue({'type': 'share', 'post_id': postId});
  }

  void _enqueue(Map<String, dynamic> event) {
    _queue.add({...event, 'ts': DateTime.now().millisecondsSinceEpoch});
    if (_queue.length >= 20) flush();
  }

  Future<void> flush() async {
    if (_queue.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      final dio = await ApiService().getDioClient();
      await dio.post(
        'analytics.php',
        data: {'action': 'batch', 'events': batch},
      );
    } catch (_) {
      // Re-queue on failure (max 100 total to prevent memory leak)
      if (_queue.length < 100) _queue.insertAll(0, batch);
    }
  }
}
