import 'package:flutter/material.dart';
import 'dart:io';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class PublishPostScreen extends StatefulWidget {
  final String mediaType;
  final String? mediaPath;
  final String? initialCaption;
  final String? soundName;

  /// Pre-extracted thumbnail path (first frame via FFmpeg/video_thumbnail).
  /// When provided, this image is uploaded as the reel cover instead of
  /// letting the server pick a random frame.
  final String? thumbnailPath;

  const PublishPostScreen({
    super.key,
    required this.mediaType,
    this.mediaPath,
    this.initialCaption,
    this.soundName,
    this.thumbnailPath,
  });

  @override
  State<PublishPostScreen> createState() => _PublishPostScreenState();
}

class _PublishPostScreenState extends State<PublishPostScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  bool _isPublishing = false;
  VideoPlayerController? _videoController;
  bool _hasPlans = false;
  bool _subscriberOnly = false;
  bool _showEmojiPicker = false;
  late AnimationController _publishAnimCtrl;
  late Animation<double> _publishScale;

  // Thumbnail selection
  String? _thumbnailPath;
  List<String> _frameOptions = [];
  bool _isExtractingFrames = false;
  double _scrubValue = 0.0;
  bool _isScrubbing = false;

  // Text post decoration
  int _bgStyleIndex = 0;
  TextAlign _textAlign = TextAlign.center;
  double _fontSize = 20.0;

  static const List<_BgPreset> _bgPresets = [
    _BgPreset('Midnight',   [Color(0xFF0D0D1A), Color(0xFF1A1A2E)]),
    _BgPreset('Rose Noir',  [Color(0xFF1A0010), Color(0xFF3D0028)]),
    _BgPreset('Ocean Deep', [Color(0xFF001233), Color(0xFF003366)]),
    _BgPreset('Forest',     [Color(0xFF001A0A), Color(0xFF003316)]),
    _BgPreset('Sunset',     [Color(0xFF7B1A1A), Color(0xFF3D1A0A)]),
    _BgPreset('Neon Pink',  [Color(0xFFFF007F), Color(0xFFBF00FF)]),
    _BgPreset('Electric',   [Color(0xFF00C6FF), Color(0xFF0078FF)]),
    _BgPreset('Gold',       [Color(0xFF7B6000), Color(0xFFB38900)]),
    _BgPreset('Sage',       [Color(0xFF1A2E1A), Color(0xFF2E4A2E)]),
    _BgPreset('Mono Dark',  [Color(0xFF0A0A0A), Color(0xFF1C1C1E)]),
    _BgPreset('Candy',      [Color(0xFFFF69B4), Color(0xFFFF1493)]),
    _BgPreset('Aurora',     [Color(0xFF003B2E), Color(0xFF7B00D4)]),
  ];

  // Common emojis for quick access
  static const List<String> _quickEmojis = [
    '😍',
    '🥰',
    '😘',
    '❤️',
    '🔥',
    '💯',
    '✨',
    '🎉',
    '💕',
    '😎',
    '🤩',
    '💪',
    '🙌',
    '😂',
    '🥺',
    '💖',
    '🌟',
    '👏',
    '💐',
    '🎶',
    '🤗',
    '😊',
    '💋',
    '🦋',
    '🌈',
    '🍀',
    '💎',
    '👑',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '😇',
    '🥳',
    '🤞',
    '🙏',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCaption != null && widget.initialCaption!.isNotEmpty) {
      _captionController.text = widget.initialCaption!;
    }
    _captionController.addListener(() {
      if (widget.mediaType == 'text' && mounted) setState(() {});
    });
    // Seed the selected thumbnail with the first frame passed from the recorder
    if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      _thumbnailPath = widget.thumbnailPath;
      _frameOptions = [widget.thumbnailPath!];
    }
    if ((widget.mediaType == 'video' || widget.mediaType == 'reel') &&
        widget.mediaPath != null) {
      _initializeVideo();
    }
    _checkPlans();

    _publishAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _publishScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _publishAnimCtrl, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkPlans() async {
    final plans = await SubscriptionPlanService().getMyPlans();
    if (mounted) setState(() => _hasPlans = plans.isNotEmpty);
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.file(File(widget.mediaPath!));
    try {
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.setVolume(0.0);
      await _videoController!.play();
      if (mounted) setState(() {});
      // Extract additional frames for the cover picker after init
      _extractFrameOptions();
    } catch (_) {}
  }

  Future<void> _extractFrameOptions() async {
    if (widget.mediaPath == null || _isExtractingFrames) return;
    if (mounted) setState(() => _isExtractingFrames = true);
    try {
      final durationMs =
          _videoController?.value.duration.inMilliseconds ?? 0;
      final tmpDir = await getTemporaryDirectory();

      // 10 evenly-spaced positions: 0%–90%
      final fractions = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
      final positions = durationMs > 0
          ? fractions.map((f) => (durationMs * f).round()).toList()
          : [0];

      final paths = <String>[];
      for (int i = 0; i < positions.length; i++) {
        try {
          // Use thumbnailData to get bytes, then write to a uniquely named file
          // so repeated calls for the same video don't overwrite each other.
          final bytes = await VideoThumbnail.thumbnailData(
            video: widget.mediaPath!,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 720,
            quality: 80,
            timeMs: positions[i],
          );
          if (bytes != null && bytes.isNotEmpty) {
            final file = File('${tmpDir.path}/cover_frame_$i.jpg');
            await file.writeAsBytes(bytes, flush: true);
            paths.add(file.path);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isExtractingFrames = false;
        if (paths.isNotEmpty) {
          _frameOptions = paths;
          _thumbnailPath ??= paths.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isExtractingFrames = false);
    }
  }

  // Extract one frame at the scrubber position and set it as the cover.
  Future<void> _extractFrameAt(double fraction) async {
    if (widget.mediaPath == null) return;
    final durationMs =
        _videoController?.value.duration.inMilliseconds ?? 0;
    if (durationMs == 0) return;
    setState(() => _isScrubbing = true);
    try {
      final ms = (durationMs * fraction).round();
      final tmpDir = await getTemporaryDirectory();
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.mediaPath!,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 720,
        quality: 85,
        timeMs: ms,
      );
      if (bytes != null && bytes.isNotEmpty && mounted) {
        final file = File('${tmpDir.path}/cover_custom.jpg');
        await file.writeAsBytes(bytes, flush: true);
        setState(() {
          // Replace or add the custom frame at the end of the list
          _frameOptions = [
            ..._frameOptions.where((p) => p != file.path),
            file.path,
          ];
          _thumbnailPath = file.path;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isScrubbing = false);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    _captionFocus.dispose();
    _publishAnimCtrl.dispose();
    super.dispose();
  }

  /// Extract hashtags from caption text (words starting with #)
  String _extractHashtags() {
    final regex = RegExp(r'#(\w+)');
    final matches = regex.allMatches(_captionController.text);
    return matches.map((m) => '#${m.group(1)}').join(' ');
  }

  void _insertEmoji(String emoji) {
    final text = _captionController.text;
    final selection = _captionController.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _captionController.text = newText;
    _captionController.selection = TextSelection.collapsed(
      offset: selection.start + emoji.length,
    );
  }

  Future<void> _publishPost() async {
    _publishAnimCtrl.forward().then((_) => _publishAnimCtrl.reverse());
    setState(() => _isPublishing = true);

    try {
      final hashtags = _extractHashtags();
      Map<String, dynamic>? uploadResult;

      // Normalize type to what the backend accepts:
      // photo, video, text, audio  (reel → video, image → photo)
      String _normalizeType(String t) {
        switch (t.toLowerCase()) {
          case 'reel':
            return 'video';
          case 'image':
            return 'photo';
          default:
            return t.toLowerCase();
        }
      }

      final backendType = _normalizeType(widget.mediaType);

      if (widget.mediaType == 'text' ||
          widget.mediaPath == null ||
          widget.mediaPath!.isEmpty) {
        uploadResult = await ApiService().uploadTextPost(
          _captionController.text,
          backendType,
          hashtags: hashtags,
          subscriberOnly: _subscriberOnly,
          bgStyle: _bgStyleIndex.toString(),
        );
      } else {
        // Ensure thumbnail is always uploaded for videos.
        // If extraction hasn't finished yet (user tapped Publish early),
        // generate one now from the local file — fast because it's on disk.
        String? thumbPath = _thumbnailPath;
        if (thumbPath == null &&
            widget.mediaPath != null &&
            (backendType == 'video' || backendType == 'reel')) {
          try {
            final bytes = await VideoThumbnail.thumbnailData(
              video: widget.mediaPath!,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 720,
              quality: 75,
              timeMs: 0,
            );
            if (bytes != null && bytes.isNotEmpty) {
              final tmpDir = await getTemporaryDirectory();
              final f = File('${tmpDir.path}/cover_publish.jpg');
              await f.writeAsBytes(bytes, flush: true);
              thumbPath = f.path;
            }
          } catch (_) {}
        }

        uploadResult = await ApiService().uploadPost(
          File(widget.mediaPath!),
          _captionController.text,
          backendType,
          hashtags: hashtags,
          soundName: widget.soundName,
          muteAudio: widget.soundName != null && widget.soundName!.isNotEmpty,
          subscriberOnly: _subscriberOnly,
          thumbnailPath: thumbPath,
        );
      }

      if (!mounted) return;
      NeonToast.success(context, 'Post Published Successfully! 🎉');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      debugPrint('[PUBLISH_POST] Upload error: $e');
      NeonToast.error(context, 'Upload Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom App Bar ──
            _buildAppBar(),
            // ── Content ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildMediaPreview(),
                      if (widget.mediaType == 'video' ||
                          widget.mediaType == 'reel') ...[
                        const SizedBox(height: 16),
                        _buildThumbnailPicker(),
                      ],
                      const SizedBox(height: 20),
                      _buildCaptionInput(),
                      const SizedBox(height: 16),
                      if (_hasPlans) _buildSubscriberToggle(),
                      const SizedBox(height: 24),
                      _buildPublishButton(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            // ── Emoji Picker ──
            if (_showEmojiPicker) _buildEmojiPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
            ).createShader(bounds),
            child: const Text(
              'Create Post',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Spacer(),
          // Post type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF007F).withValues(alpha: 0.2),
                  const Color(0xFF9C27B0).withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF007F).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              widget.mediaType.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFFF007F),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.mediaType != 'text' && widget.mediaPath != null) {
      return Container(
        height: 320,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF007F).withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media content
              (widget.mediaType == 'video' || widget.mediaType == 'reel')
                  ? _videoController != null &&
                          _videoController!.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF007F),
                              strokeWidth: 2,
                            ),
                          ),
                        )
                  : Image.file(File(widget.mediaPath!), fit: BoxFit.cover),
              // Gradient overlay at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                ),
              ),
              // Play icon for video
              if (widget.mediaType == 'video' || widget.mediaType == 'reel')
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Text post: live preview + decoration controls
    final preset = _bgPresets[_bgStyleIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview card
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: 220,
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: preset.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: preset.colors.last.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: preset.colors.first.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _captionController.text.isEmpty
                  ? '✨ Your text will appear here...'
                  : _captionController.text,
              textAlign: _textAlign,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _captionController.text.isEmpty
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white,
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                height: 1.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── Background presets ──────────────────────────────────────────
        Row(
          children: [
            const Icon(Icons.palette_outlined, color: Colors.white54, size: 15),
            const SizedBox(width: 6),
            const Text('Background',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _bgPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final p = _bgPresets[i];
              final selected = i == _bgStyleIndex;
              return GestureDetector(
                onTap: () => setState(() => _bgStyleIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: selected ? 64 : 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: p.colors),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Center(
                          child: Icon(Icons.check, color: Colors.white, size: 16))
                      : null,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // ── Font size + alignment ────────────────────────────────────────
        Row(
          children: [
            // Font size slider
            const Icon(Icons.format_size, color: Colors.white54, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: const Color(0xFFFF007F),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: _fontSize,
                  min: 14,
                  max: 36,
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Alignment toggles
            _alignBtn(Icons.format_align_left,   TextAlign.left),
            _alignBtn(Icons.format_align_center, TextAlign.center),
            _alignBtn(Icons.format_align_right,  TextAlign.right),
          ],
        ),
      ],
    );
  }

  Widget _alignBtn(IconData icon, TextAlign align) {
    final active = _textAlign == align;
    return GestureDetector(
      onTap: () => setState(() => _textAlign = align),
      child: Container(
        width: 32, height: 32,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF007F).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFFFF007F) : Colors.white24,
          ),
        ),
        child: Icon(icon,
            color: active ? const Color(0xFFFF007F) : Colors.white38,
            size: 16),
      ),
    );
  }

  Widget _buildCaptionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFFFF007F)],
              ).createShader(bounds),
              child: const Icon(Icons.edit_note, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 8),
            const Text(
              'Caption',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Builder(builder: (context) {
              final isReel = widget.mediaType == 'reel';
              final limit = isReel ? 150 : 2200;
              final len = _captionController.text.length;
              final nearLimit = isReel && len > 120;
              return Text(
                '$len/$limit',
                style: TextStyle(
                  color: nearLimit
                      ? const Color(0xFFFF007F)
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                  fontWeight: nearLimit ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 10),

        // Text field with emoji button
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _captionFocus.hasFocus
                  ? const Color(0xFFFF007F).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _captionController,
                focusNode: _captionFocus,
                autofocus: widget.mediaType == 'text',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
                maxLines: widget.mediaType == 'reel' ? 3 : 5,
                maxLength: widget.mediaType == 'reel' ? 150 : 2200,
                decoration: InputDecoration(
                  hintText: widget.mediaType == 'reel'
                      ? 'Short caption... #hashtags auto-categorize (hidden in feed)'
                      : 'Write a caption... use #hashtags to categorize 🏷️',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 14,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              // Bottom action bar
              Container(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    // Emoji toggle button
                    _actionChip(
                      icon: _showEmojiPicker
                          ? Icons.keyboard
                          : Icons.emoji_emotions_outlined,
                      label: _showEmojiPicker ? 'Keyboard' : 'Emoji',
                      onTap: () {
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                          if (_showEmojiPicker) {
                            _captionFocus.unfocus();
                          } else {
                            _captionFocus.requestFocus();
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    // Hashtag hint
                    _actionChip(
                      icon: Icons.tag,
                      label: 'Hashtag',
                      onTap: () {
                        _insertEmoji('#');
                        _captionFocus.requestFocus();
                      },
                    ),
                    const Spacer(),
                    // Hashtag count
                    if (_extractHashtags().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFF00E5FF,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '${RegExp(r'#(\w+)').allMatches(_captionController.text).length} tags',
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailPicker() {
    final durationMs =
        _videoController?.value.duration.inMilliseconds ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              const Icon(Icons.photo_camera_back_rounded,
                  color: Color(0xFFFF007F), size: 16),
              const SizedBox(width: 6),
              const Text(
                'Cover Photo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_isExtractingFrames || _isScrubbing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Color(0xFFFF007F), strokeWidth: 1.5),
                )
              else
                Text(
                  'Tap a frame or drag slider',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Frame strip ──
          if (_isExtractingFrames && _frameOptions.isEmpty)
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 10,
                itemBuilder: (_, __) => Container(
                  width: 60,
                  height: 90,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else if (_frameOptions.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _frameOptions.length,
                itemBuilder: (context, i) {
                  final path = _frameOptions[i];
                  final isSelected = path == _thumbnailPath;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _thumbnailPath = path;
                      // Sync slider to this frame's approximate position
                      if (i < 10) {
                        _scrubValue = i / 10.0;
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 60,
                      height: 90,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF007F)
                              : Colors.white.withValues(alpha: 0.12),
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFF007F)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 14,
                                )
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              // Force re-read from disk (not cached stale data)
                              cacheWidth: 180,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF1A1A2E),
                                child: const Icon(Icons.broken_image_outlined,
                                    color: Colors.white30, size: 18),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: 3, right: 3,
                                child: Container(
                                  width: 18, height: 18,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF007F),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                            // Frame position label
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.45),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  i < 10
                                      ? '${(i * 10)}%'
                                      : 'Custom',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // ── Scrubber slider ──
          if (durationMs > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    color: Colors.white38, size: 13),
                const SizedBox(width: 6),
                Text(
                  _fmtMs((_scrubValue * durationMs).round()),
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: const Color(0xFFFF007F),
                      inactiveTrackColor:
                          Colors.white.withValues(alpha: 0.15),
                      thumbColor: const Color(0xFFFF007F),
                      overlayColor:
                          const Color(0xFFFF007F).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _scrubValue,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) => setState(() => _scrubValue = v),
                      onChangeEnd: _extractFrameAt,
                    ),
                  ),
                ),
                Text(
                  _fmtMs(durationMs),
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmtMs(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _quickEmojis.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _insertEmoji(_quickEmojis[index]),
            child: Center(
              child: Text(
                _quickEmojis[index],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubscriberToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: _subscriberOnly
            ? LinearGradient(
                colors: [
                  const Color(0xFFFF007F).withValues(alpha: 0.1),
                  const Color(0xFF9C27B0).withValues(alpha: 0.05),
                ],
              )
            : null,
        color: _subscriberOnly ? null : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _subscriberOnly
              ? const Color(0xFFFF007F).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _subscriberOnly
                  ? const Color(0xFFFF007F).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _subscriberOnly ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: _subscriberOnly ? const Color(0xFFFF007F) : Colors.white54,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscriber Only',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Only subscribers can see this post',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _subscriberOnly,
            onChanged: (v) => setState(() => _subscriberOnly = v),
            activeThumbColor: const Color(0xFFFF007F),
            activeTrackColor: const Color(0xFFFF007F).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishButton() {
    return ScaleTransition(
      scale: _publishScale,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: _isPublishing
                ? null
                : const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                  ),
            color: _isPublishing ? Colors.grey[800] : null,
            boxShadow: _isPublishing
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: _isPublishing ? null : _publishPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: _isPublishing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rocket_launch, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'PUBLISH',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BgPreset {
  final String label;
  final List<Color> colors;
  const _BgPreset(this.label, this.colors);
}
