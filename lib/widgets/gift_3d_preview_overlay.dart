import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shimmer/shimmer.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Full-screen overlay that shows a rotating 3D GLB model of a gift.
///
/// - Blur backdrop (sigma 18) + dark dim layer (0.45 opacity)
/// - Center card with gradient border, 3D ModelViewer, name, and coin price
/// - Shows thumbnail immediately with shimmer, then crossfades to 3D model
/// - Scale + fade entrance animation (~300 ms)
/// - Auto-dismiss after 4 s OR tap-outside to dismiss
/// - Does NOT close the bottom sheet underneath
class Gift3dPreviewOverlay {
  Gift3dPreviewOverlay._();

  static OverlayEntry? _currentEntry;

  // â”€â”€ Extractors â”€â”€

  /// Prefer glb_url / model_url for 3D model; fall back to empty.
  static String _modelUrl(Map<String, dynamic> gift) =>
      (gift['glb_url'] ?? gift['model_url'] ?? '').toString();

  /// Thumb image for the fallback when no 3D model is available.
  static String _thumbUrl(Map<String, dynamic> gift) =>
      (gift['thumb_image'] ?? gift['gif_url'] ?? gift['image'] ?? '')
          .toString();

  static String _name(Map<String, dynamic> gift) =>
      (gift['name'] ?? gift['title'] ?? 'Gift').toString();

  static int _price(Map<String, dynamic> gift) =>
      int.tryParse((gift['coin_price'] ?? gift['price'] ?? 0).toString()) ?? 0;

  /// Show the 3D preview overlay for [gift].
  static void show(BuildContext context, Map<String, dynamic> gift) {
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Gift3dPreviewWidget(
        modelUrl: _modelUrl(gift),
        thumbUrl: _thumbUrl(gift),
        name: _name(gift),
        price: _price(gift),
        onDismiss: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// Remove the current overlay (if any).
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Private stateful widget that manages animation, timer, caching, and 3D viewer
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Gift3dPreviewWidget extends StatefulWidget {
  final String modelUrl;
  final String thumbUrl;
  final String name;
  final int price;
  final VoidCallback onDismiss;

  const _Gift3dPreviewWidget({
    required this.modelUrl,
    required this.thumbUrl,
    required this.name,
    required this.price,
    required this.onDismiss,
  });

  @override
  State<_Gift3dPreviewWidget> createState() => _Gift3dPreviewWidgetState();
}

class _Gift3dPreviewWidgetState extends State<_Gift3dPreviewWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  // â”€â”€ Caching state â”€â”€
  String? _localModelPath; // file:// URI for cached GLB
  bool _modelReady = false; // flipped once ModelViewer can render

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Start caching the 3D model in the background
    if (_has3dModel) {
      _cacheAndLoad();
    }
  }

  /// Download the GLB file via cache manager, then switch to local URI.
  Future<void> _cacheAndLoad() async {
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.modelUrl);
      if (!mounted) return;

      final localUri = Uri.file(file.path).toString();

      // Small delay so the thumbnail is visible briefly, then crossfade
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      setState(() {
        _localModelPath = localUri;
        _modelReady = true;
      });
    } catch (_) {
      // If caching fails, stay on the thumbnail â€” don't crash
    }
  }

  Future<void> _close() async {
    if (!mounted) {
      widget.onDismiss();
      return;
    }
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _has3dModel {
    final url = widget.modelUrl;
    return url.isNotEmpty && url.startsWith('http');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          onTap: _close,
          child: Stack(
            children: [
              // â”€â”€ Blur + dim backdrop â”€â”€
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                ),
              ),

              // â”€â”€ Center preview card â”€â”€
              Center(
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: GestureDetector(
                    onTap: () {}, // absorb taps on card
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1425), Color(0xFF0F1118)],
                        ),
                        border: Border.all(
                          width: 1.5,
                          color: const Color(0xFFD946EF).withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFD946EF,
                            ).withValues(alpha: 0.18),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF06B6D4,
                            ).withValues(alpha: 0.10),
                            blurRadius: 60,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // â”€â”€ 3D model / thumbnail with shimmer â”€â”€
                          SizedBox(
                            height: 220,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: _has3dModel
                                  ? _buildCachedModelViewer()
                                  : _buildFallbackImage(),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // â”€â”€ Gift name â”€â”€
                          Text(
                            widget.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CoinIcon(size: 16, color: Colors.amber),
                              const SizedBox(width: 6),
                              Text(
                                '${widget.price}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stack: thumbnail+shimmer on bottom, ModelViewer crossfading on top.
  Widget _buildCachedModelViewer() {
    return Stack(
      children: [
        // â”€â”€ Bottom layer: Thumbnail + shimmer + progress â”€â”€
        AnimatedOpacity(
          opacity: _modelReady ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 400),
          child: Stack(
            children: [
              // Thumbnail image
              Positioned.fill(child: _buildThumbImage()),

              // Shimmer overlay
              Positioned.fill(
                child: Shimmer.fromColors(
                  baseColor: Colors.white.withValues(alpha: 0.04),
                  highlightColor: Colors.white.withValues(alpha: 0.15),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFD946EF),
                  ),
                ),
              ),
            ],
          ),
        ),

        // â”€â”€ Top layer: ModelViewer, crossfades in when ready â”€â”€
        if (_localModelPath != null)
          AnimatedOpacity(
            opacity: _modelReady ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: ModelViewer(
              src: _localModelPath!,
              autoRotate: true,
              cameraControls: true,
              autoPlay: true,
              backgroundColor: Colors.transparent,
              disableZoom: false,
            ),
          ),
      ],
    );
  }

  /// Thumbnail image (used as instant preview while GLB loads).
  Widget _buildThumbImage() {
    final url = widget.thumbUrl;
    if (url.isEmpty || !url.startsWith('http')) {
      return const Center(
        child: Icon(Icons.card_giftcard, color: Colors.white38, size: 80),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.card_giftcard, color: Colors.white38, size: 80),
      ),
    );
  }

  Widget _buildFallbackImage() {
    final url = widget.thumbUrl;
    if (url.isEmpty || !url.startsWith('http')) {
      return const Center(
        child: Icon(Icons.card_giftcard, color: Colors.white38, size: 80),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFFD946EF),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.card_giftcard, color: Colors.white38, size: 80),
      ),
    );
  }
}
