import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

/// Shows a blurred overlay preview of a gift in the center of the screen.
///
/// - Blur backdrop (sigma 18) + dark dim layer (0.45 opacity)
/// - Center card with gradient border, animated GIF, name, and coin price
/// - Scale + fade entrance animation (~300 ms)
/// - Auto-dismiss after 2.5 s OR tap-outside to dismiss
/// - Does NOT close the bottom sheet underneath
class GiftPreviewOverlay {
  GiftPreviewOverlay._();

  static OverlayEntry? _currentEntry;

  /// Convenience extractors ─ mirrors the helpers in GiftsSheet
  static String _imageUrl(Map<String, dynamic> gift) =>
      (gift['gif_url'] ?? gift['thumb_image'] ?? gift['image'] ?? '')
          .toString();

  static String _emoji(Map<String, dynamic> gift) =>
      (gift['emoji'] ?? '🎁').toString().trim();

  static String _name(Map<String, dynamic> gift) =>
      (gift['name'] ?? gift['title'] ?? 'Gift').toString();

  static String _sender(Map<String, dynamic> gift) =>
      (gift['sender_name'] ?? gift['sender'] ?? gift['sent_by'] ?? '')
          .toString();

  static String _senderId(Map<String, dynamic> gift) =>
      (gift['sender_id'] ?? '').toString();

  static String _senderPic(Map<String, dynamic> gift) =>
      (gift['sender_avatar'] ?? gift['sender_pic'] ?? gift['sender_profile_pic'] ?? '').toString();

  static String _message(Map<String, dynamic> gift) =>
      (gift['message'] ?? '').toString();

  static int _qty(Map<String, dynamic> gift) =>
      int.tryParse((gift['qty'] ?? 1).toString()) ?? 1;

  static int _price(Map<String, dynamic> gift) =>
      int.tryParse((gift['coin_price'] ?? gift['price'] ?? 0).toString()) ?? 0;

  /// Show the preview overlay for [gift].
  static void show(BuildContext context, Map<String, dynamic> gift) {
    // Remove any existing overlay first
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GiftPreviewOverlayWidget(
        imageUrl: _imageUrl(gift),
        emoji: _emoji(gift),
        name: _name(gift),
        senderId: _senderId(gift),
        senderName: _sender(gift),
        senderPic: _senderPic(gift),
        message: _message(gift),
        qty: _qty(gift),
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

  /// Programmatically dismiss the current overlay (if any).
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Private widget that manages animation + auto-dismiss timer
// ──────────────────────────────────────────────────────────────────────────────

class _GiftPreviewOverlayWidget extends StatefulWidget {
  final String imageUrl;
  final String emoji;
  final String name;
  final String senderId;
  final String senderName;
  final String senderPic;
  final String message;
  final int qty;
  final int price;
  final VoidCallback onDismiss;

  const _GiftPreviewOverlayWidget({
    required this.imageUrl,
    this.emoji = '🎁',
    required this.name,
    required this.senderId,
    required this.senderName,
    required this.senderPic,
    required this.message,
    required this.qty,
    required this.price,
    required this.onDismiss,
  });

  @override
  State<_GiftPreviewOverlayWidget> createState() =>
      _GiftPreviewOverlayWidgetState();
}

class _GiftPreviewOverlayWidgetState extends State<_GiftPreviewOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnim = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          // Tap outside the card → dismiss
          onTap: _close,
          child: Stack(
            children: [
              // ── Heavy Blur + dim backdrop ──
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
                  child: Container(color: Colors.black.withValues(alpha: 0.65)),
                ),
              ),

              // ── Center presentation ──
              Center(
                child: SlideTransition(
                  position: _slideAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: GestureDetector(
                      // Absorb taps on the card
                      onTap: () {},
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.85,
                        constraints: const BoxConstraints(maxWidth: 400),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 36,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141418).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            width: 2,
                            color: const Color(
                              0xFFD946EF,
                            ).withValues(alpha: 0.5),
                          ),
                          gradient: const RadialGradient(
                            center: Alignment.topLeft,
                            radius: 1.5,
                            colors: [Color(0xFF2B0F4C), Color(0xFF0F1118)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.4),
                              blurRadius: 100,
                              spreadRadius: -10,
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFF06B6D4,
                              ).withValues(alpha: 0.2),
                              blurRadius: 120,
                              spreadRadius: -10,
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ── App Branding ──
                                const Text(
                                  'GORETO',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // ── Header ──
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          Color(0xFF00E5FF),
                                          Color(0xFFFF007F),
                                        ],
                                      ).createShader(bounds),
                                  child: const Text(
                                    'GIFT RECEIVED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 30),

                                // ── Gift image (Massive & Interactive) ──
                                SizedBox(
                                  height: 220,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    clipBehavior: Clip.none,
                                    children: [
                                      InteractiveViewer(
                                        panEnabled: true,
                                        scaleEnabled: true,
                                        maxScale: 4.0,
                                        child: _buildGiftImage(),
                                      ),
                                      if (widget.qty > 1)
                                        Positioned(
                                          top: 10,
                                          right: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFF007F),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFF007F,
                                                  ).withValues(alpha: 0.6),
                                                  blurRadius: 15,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              'x${widget.qty}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // ── Gift name ──
                                Text(
                                  widget.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 16),

                                // ── Custom Message ──
                                if (widget.message.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFD946EF,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFD946EF,
                                        ).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      '"${widget.message}"',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),

                                // ── Spacing ──
                                const SizedBox(height: 8),

                                // ── Sender Info Row ──
                                if (widget.senderName.isNotEmpty)
                                  GestureDetector(
                                    onTap: widget.senderId.isNotEmpty
                                        ? () {
                                            _close();
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ProfileScreen(
                                                    userId: widget.senderId),
                                              ),
                                            );
                                          }
                                        : null,
                                    child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.senderPic.isNotEmpty) ...[
                                          Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0xFF00E5FF),
                                                width: 2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF00E5FF,
                                                  ).withValues(alpha: 0.4),
                                                  blurRadius: 10,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: CircleAvatar(
                                              radius: 20,
                                              backgroundImage:
                                                  CachedNetworkImageProvider(
                                                    widget.senderPic,
                                                  ),
                                              backgroundColor: Colors.grey[800],
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                        ],
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'SENT BY',
                                                style: TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                              Text(
                                                widget.senderName,
                                                style: const TextStyle(
                                                  color: Color(0xFF06B6D4),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ),

                                const SizedBox(height: 24),

                                // ── Coin price ──
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.amber.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CoinIcon(size: 20, color: Colors.amber),
                                      const SizedBox(width: 8),
                                      Text(
                                        '+ ${widget.price}',
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // ── Close Button ──
                            Positioned(
                              top: -16,
                              right: -16,
                              child: GestureDetector(
                                onTap: _close,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildGiftImage() {
    final url = widget.imageUrl;
    if (url.isEmpty || !url.startsWith('http')) {
      return Center(
        child: Text(
          widget.emoji.isNotEmpty ? widget.emoji : '🎁',
          style: const TextStyle(fontSize: 100),
          textAlign: TextAlign.center,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Color(0xFFD946EF),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Center(
        child: Text(
          widget.emoji.isNotEmpty ? widget.emoji : '🎁',
          style: const TextStyle(fontSize: 100),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
