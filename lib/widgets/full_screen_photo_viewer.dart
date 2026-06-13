import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Full-screen, pinch-to-zoom photo viewer with a small app-logo watermark and
/// a download button. The downloaded image is composited at full resolution
/// with the watermark baked in.
class FullScreenPhotoViewer extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;
  const FullScreenPhotoViewer({super.key, required this.imageUrl, this.heroTag});

  static Future<void> open(BuildContext context, String imageUrl,
      {String? heroTag}) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FullScreenPhotoViewer(imageUrl: imageUrl, heroTag: heroTag),
    ));
  }

  @override
  State<FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<FullScreenPhotoViewer> {
  static const String _logoAsset = 'assets/images/goreto.png';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final img = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.contain,
      placeholder: (_, __) =>
          const Center(child: CircularProgressIndicator(color: Colors.white54)),
      errorWidget: (_, __, ___) =>
          const Icon(Icons.broken_image, color: Colors.white24, size: 64),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Zoomable photo
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: widget.heroTag != null
                    ? Hero(tag: widget.heroTag!, child: img)
                    : img,
              ),
            ),
          ),

          // On-screen watermark (bottom-right)
          Positioned(
            right: 16,
            bottom: 24,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: Image.asset(_logoAsset, width: 44,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          ),

          // Top bar: close + download
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    _saving
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white)),
                          )
                        : IconButton(
                            tooltip: 'Download',
                            icon: const Icon(Icons.download_rounded,
                                color: Colors.white),
                            onPressed: _download,
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _composeWatermarked(widget.imageUrl);
      if (bytes == null) throw Exception('decode failed');
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, album: 'Goreto');
      if (mounted) NeonToast.success(context, 'Saved to gallery');
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Could not save photo');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fetch the original image and bake the app logo watermark into the
  /// bottom-right corner at full resolution.
  Future<Uint8List?> _composeWatermarked(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return null;
    final ui.Image src =
        (await (await ui.instantiateImageCodec(resp.bodyBytes)).getNextFrame())
            .image;

    ui.Image? logo;
    try {
      final logoData = await rootBundle.load(_logoAsset);
      logo = (await (await ui.instantiateImageCodec(
                  logoData.buffer.asUint8List()))
              .getNextFrame())
          .image;
    } catch (_) {}

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());

    if (logo != null) {
      final double wmW = src.width * 0.12;
      final double wmH = wmW * (logo.height / logo.width);
      final double pad = src.width * 0.03;
      final dst = Rect.fromLTWH(
          src.width - wmW - pad, src.height - wmH - pad, wmW, wmH);
      final srcRect = Rect.fromLTWH(
          0, 0, logo.width.toDouble(), logo.height.toDouble());
      canvas.drawImageRect(
          logo, srcRect, dst, Paint()..color = Colors.white.withValues(alpha: 0.8));
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }
}
