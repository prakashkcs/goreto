import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';
import 'package:love_vibe_pro/services/sound_service.dart';

bool _isImageUrl(String url) {
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif');
}

class ReelsVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool isActive;
  /// When true and isActive is false: initialize the controller in the background
  /// so swipe-to-next feels instant. Does not play.
  final bool preload;
  final VoidCallback? onDoubleTapLike;
  final ValueChanged<VideoPlayerController>? onControllerReady;
  final ValueChanged<VideoPlayerController>? onControllerDisposed;

  const ReelsVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.isActive = true,
    this.preload = false,
    this.onDoubleTapLike,
    this.onControllerReady,
    this.onControllerDisposed,
  });

  @override
  State<ReelsVideoPlayer> createState() => _ReelsVideoPlayerState();
}

class _ReelsVideoPlayerState extends State<ReelsVideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoPlayerController;
  bool _isInitializing = false;
  bool _isPausedByUser = false;
  bool _isVideoPlaying = false;
  bool _showPauseOverlay = false;
  bool _showHeartOverlay = false;

  Uint8List? _cachedThumb;
  bool _thumbRequested = false;

  late final AnimationController _heartController;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _heartScale = CurvedAnimation(
      parent: _heartController,
      curve: Curves.elasticOut,
    );

    if (widget.isActive) {
      _initializePlayer();
    } else if (widget.preload) {
      _initializePreload();
    }

    if (!_hasNetworkThumb) {
      _cachedThumb = ThumbnailCache.instance.get(widget.videoUrl);
      if (_cachedThumb == null) _fetchThumb();
    }
  }

  bool get _hasNetworkThumb {
    final t = widget.thumbnailUrl?.trim() ?? '';
    return t.isNotEmpty && t.startsWith('http') && _isImageUrl(t);
  }

  Future<void> _fetchThumb() async {
    if (_thumbRequested || widget.videoUrl.isEmpty) return;
    _thumbRequested = true;
    final bytes = await ThumbnailCache.instance.fetch(widget.videoUrl);
    if (mounted && bytes != null) setState(() => _cachedThumb = bytes);
  }

  @override
  void didUpdateWidget(covariant ReelsVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoUrl != widget.videoUrl) {
      _cachedThumb = null;
      _thumbRequested = false;
      _disposeControllers();
      _isPausedByUser = false;
      _isVideoPlaying = false;
      _showPauseOverlay = false;
      if (widget.isActive) {
        _initializePlayer();
      } else if (widget.preload) {
        _initializePreload();
      }
      if (!_hasNetworkThumb) {
        _cachedThumb = ThumbnailCache.instance.get(widget.videoUrl);
        if (_cachedThumb == null) _fetchThumb();
      }
      return;
    }

    if (widget.isActive) {
      if (_videoPlayerController == null ||
          !_videoPlayerController!.value.isInitialized) {
        _initializePlayer();
      } else {
        // Controller was preloaded — show thumbnail for 400ms, then play.
        if (!_isPausedByUser) {
          final c = _videoPlayerController!;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && widget.isActive && _videoPlayerController == c) {
              c.play();
              setState(() => _isVideoPlaying = true);
            }
          });
        }
      }
    } else if (widget.preload) {
      if (_videoPlayerController == null) {
        _initializePreload();
      }
    } else {
      _disposeControllers();
      _isPausedByUser = false;
      _isVideoPlaying = false;
      _showPauseOverlay = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _initializePlayer() async {
    if (_isInitializing || widget.videoUrl.isEmpty || !widget.isActive) return;
    _isInitializing = true;
    _disposeControllers();
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _videoPlayerController = controller;

      final thumbUrl = widget.thumbnailUrl?.trim() ?? '';

      // Load video and thumbnail in parallel.
      // - If server provides a real image URL, precache it into Flutter's ImageCache.
      // - Otherwise extract a frame from the video via ThumbnailCache (fast-start MP4s
      //   only need the MOOV header to produce a frame, so this is quick on mobile).
      final futures = <Future>[controller.initialize()];
      if (_isImageUrl(thumbUrl) && mounted) {
        futures.add(
            precacheImage(NetworkImage(thumbUrl), context).catchError((_) {}));
      } else if (widget.videoUrl.isNotEmpty) {
        futures.add(
          ThumbnailCache.instance.fetch(widget.videoUrl).then((bytes) {
            if (mounted && bytes != null) setState(() => _cachedThumb = bytes);
          }).catchError((_) {}),
        );
      }
      await Future.wait(futures);

      await Future.wait([controller.setLooping(true), controller.setVolume(1)]);
      if (!widget.isActive || _videoPlayerController != controller || !mounted) return;

      // Thumbnail is in cache — show it instantly.
      setState(() => _isInitializing = false);

      // Hold thumbnail visible for 400ms so the user actually sees it.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!widget.isActive || _videoPlayerController != controller || !mounted) return;

      if (!_isPausedByUser) {
        await controller.play();
        _isVideoPlaying = true;
      }
      widget.onControllerReady?.call(controller);
      if (mounted) setState(() {});
    } catch (_) {
      _disposeControllers();
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize controller in the background without playing — for the next reel.
  Future<void> _initializePreload() async {
    if (_isInitializing || widget.videoUrl.isEmpty) return;
    _isInitializing = true;
    _disposeControllers();
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _videoPlayerController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1);
      await controller.pause();

      // Also extract thumbnail while preloading so it's ready when this reel activates.
      final thumbUrl = widget.thumbnailUrl?.trim() ?? '';
      if (_isImageUrl(thumbUrl) && mounted) {
        precacheImage(NetworkImage(thumbUrl), context).catchError((_) {});
      } else if (widget.videoUrl.isNotEmpty) {
        ThumbnailCache.instance.fetch(widget.videoUrl).then((bytes) {
          if (mounted && bytes != null) setState(() => _cachedThumb = bytes);
        }).catchError((_) {});
      }

      if (mounted) setState(() {});
    } catch (_) {
      _disposeControllers();
    } finally {
      _isInitializing = false;
    }
  }

  void _disposeControllers() {
    final c = _videoPlayerController;
    if (c != null) {
      try { c.pause(); } catch (_) {}
      widget.onControllerDisposed?.call(c);
      try { c.dispose(); } catch (_) {}
    }
    _videoPlayerController = null;
    _isVideoPlaying = false;
  }

  Future<void> _togglePlayback() async {
    final c = _videoPlayerController;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      _isPausedByUser = true;
      if (mounted) setState(() { _showPauseOverlay = true; _isVideoPlaying = false; });
    } else {
      await c.play();
      _isPausedByUser = false;
      if (mounted) setState(() { _showPauseOverlay = false; _isVideoPlaying = true; });
    }
  }

  Future<void> _handleDoubleTap() async {
    widget.onDoubleTapLike?.call();
    await SoundService().playReact();
    if (!mounted) return;
    setState(() => _showHeartOverlay = true);
    _heartController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showHeartOverlay = false);
    });
  }

  @override
  void dispose() {
    _disposeControllers();
    _heartController.dispose();
    super.dispose();
  }

  bool get _canRenderVideo {
    try {
      return _videoPlayerController != null &&
          _videoPlayerController!.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  static const _kGradientDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0D0D1A), Color(0xFF110820), Color(0xFF000000)],
    ),
  );

  Widget _buildThumbnailLayer() {
    final thumbUrl = widget.thumbnailUrl?.trim() ?? '';
    if (thumbUrl.startsWith('http')) {
      return Image.network(
        thumbUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          // Thumbnail still downloading — show gradient placeholder.
          return Container(
            decoration: _kGradientDecoration,
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD946EF),
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          decoration: _kGradientDecoration,
          child: const Center(
            child: Icon(Icons.play_circle_outline_rounded,
                color: Colors.white24, size: 56),
          ),
        ),
      );
    }
    if (_cachedThumb != null) {
      return Image.memory(_cachedThumb!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Container(
      decoration: _kGradientDecoration,
      child: Center(
        child: _isInitializing
            ? const CircularProgressIndicator(
                color: Color(0xFFD946EF), strokeWidth: 2)
            : const Icon(Icons.play_circle_outline_rounded,
                color: Colors.white24, size: 56),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1 — black background
          Container(color: Colors.black),

          // Layer 2 — video (behind thumbnail)
          if (_canRenderVideo)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoPlayerController!.value.size.width,
                  height: _videoPlayerController!.value.size.height,
                  child: VideoPlayer(_videoPlayerController!),
                ),
              ),
            ),

          // Layer 3 — thumbnail on TOP of video, hidden only after video plays
          if (!_isVideoPlaying)
            SizedBox.expand(child: _buildThumbnailLayer()),

          // Pause overlay
          if (_showPauseOverlay)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pause_rounded,
                      color: Colors.white, size: 46),
                ),
              ),
            ),

          // Heart overlay
          if (_showHeartOverlay)
            IgnorePointer(
              child: Center(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.25, end: 1.3)
                      .animate(_heartScale),
                  child: const Icon(Icons.favorite,
                      color: Color(0xFFFF295C), size: 120),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
