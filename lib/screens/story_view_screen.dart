import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════════════════════
//  StoryViewScreen  –  Multi-story viewer with neon cyberpunk UI
// ═══════════════════════════════════════════════════════════════════════════════

class StoryViewScreen extends StatefulWidget {
  /// All stories for the tapped user, played in sequence.
  final List<dynamic> stories;
  final String username;

  const StoryViewScreen({
    super.key,
    required this.stories,
    required this.username,
  });

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  AnimationController? _progressController;

  /// Actively animating flying emojis
  final List<_FlyingEmojiEntry> _flyingEmojis = [];

  // Music
  AudioPlayer? _musicPlayer;
  String _currentMusicTitle = '';
  int _musicGen = 0; // incremented each time music changes to cancel stale fetches

  static const Duration _defaultStoryDuration = Duration(seconds: 6);

  // ── URL helpers ─────────────────────────────────────────────────────────────

  /// Cleans a URL that may be stored as a JSON array string, e.g. '["url"]'.
  String _getCleanUrl(dynamic story) {
    final raw =
        (story['media_url'] ?? story['file_url'] ?? story['image'] ?? story['image_url'] ?? '')
            .toString();
    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) return decoded[0].toString();
      } catch (_) {}
    }
    return raw;
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }

  // ── Convenience getters ─────────────────────────────────────────────────────

  dynamic get _currentStory => widget.stories[_currentIndex];
  String get _currentUrl => _getCleanUrl(_currentStory);
  bool get _isCurrentVideo =>
      (_currentStory['type']?.toString() == 'video') || _isVideoUrl(_currentUrl);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _progressController =
        AnimationController(vsync: this, duration: _defaultStoryDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _nextStory();
          });
    _loadCurrentStory();
  }

  void _loadCurrentStory() {
    _progressController?.reset();
    _videoController?.dispose();
    _videoController = null;

    if (_isCurrentVideo) {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(_currentUrl))
            ..initialize().then((_) {
              if (!mounted) return;
              final dur = _videoController!.value.duration;
              _progressController?.duration = dur.inSeconds > 0
                  ? dur
                  : _defaultStoryDuration;
              _videoController!.setLooping(false);
              _videoController!.play();
              _progressController?.forward();
              setState(() {});
            });
    } else {
      _progressController?.duration = _defaultStoryDuration;
      _progressController?.forward();
    }

    // Play music if this story has a music tag
    final music = (_currentStory['music'] ??
            _currentStory['music_title'] ??
            '')
        .toString()
        .trim();
    if (music.isNotEmpty) {
      _fetchAndPlayMusic(music);
    } else {
      _musicGen++;
      final old = _musicPlayer;
      _musicPlayer = null;
      old?.stop();
      old?.dispose();
      if (mounted) setState(() => _currentMusicTitle = '');
    }

    setState(() {});
  }

  Future<void> _fetchAndPlayMusic(String songTitle) async {
    final gen = ++_musicGen;

    // Tear down any previously running player before the async gap
    final old = _musicPlayer;
    _musicPlayer = null;
    old?.stop();
    old?.dispose();

    if (mounted) setState(() => _currentMusicTitle = songTitle);

    try {
      final q = Uri.encodeComponent(songTitle);
      final resp = await http
          .get(Uri.parse(
              'https://itunes.apple.com/search?term=$q&media=music&limit=1&entity=song'))
          .timeout(const Duration(seconds: 8));

      // Bail if this fetch was superseded by a story change or widget disposed
      if (gen != _musicGen || !mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final previewUrl = results[0]['previewUrl'] as String?;
          if (previewUrl != null && previewUrl.isNotEmpty) {
            final player = AudioPlayer();
            _musicPlayer = player;
            await player.play(UrlSource(previewUrl));
          }
        }
      }
    } catch (_) {
      if (gen == _musicGen && mounted) setState(() => _currentMusicTitle = '');
    }
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex++);
      _loadCurrentStory();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadCurrentStory();
    } else {
      // Restart current story
      _progressController?.reset();
      _progressController?.forward();
    }
  }

  void _onEmojiTap(String emoji) {
    SoundService().playReact();
    final key = UniqueKey();
    setState(() {
      _flyingEmojis.add(
        _FlyingEmojiEntry(
          key: key,
          emoji: emoji,
          offset: Random().nextDouble() * 80 - 40, // ±40 px horizontal jitter
          onDone: (k) {
            if (mounted) {
              setState(() => _flyingEmojis.removeWhere((e) => e.key == k));
            }
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _musicGen++; // cancel any in-flight iTunes fetch
    _progressController?.dispose();
    _videoController?.dispose();
    _musicPlayer?.stop();
    _musicPlayer?.dispose();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Media content
          GestureDetector(
            onTapDown: (d) {
              if (d.localPosition.dx < size.width / 2) {
                _prevStory();
              } else {
                _nextStory();
              }
            },
            child: _buildMedia(),
          ),

          // 2. Gradient overlays (top + bottom vignette)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.2, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Progress bars
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            right: 12,
            child: Row(
              children: List.generate(widget.stories.length, (i) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _StoryProgressBar(
                      controller: i == _currentIndex
                          ? _progressController
                          : null,
                      isCompleted: i < _currentIndex,
                    ),
                  ),
                );
              }),
            ),
          ),

          // 4. Header (avatar + username + close)
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 12,
            right: 12,
            child: _buildHeader(),
          ),

          // 5. Flying emoji animations
          ..._flyingEmojis.map((e) => e.buildWidget(size)),

          // 5b. Music badge
          if (_currentMusicTitle.isNotEmpty)
            Positioned(
              bottom: 110,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note_rounded,
                          color: Color(0xFFFF007F), size: 14),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: size.width * 0.55),
                        child: Text(
                          _currentMusicTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6. Bottom bar (emoji reacts + reply) — float above keyboard
          Positioned(
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                10,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────────

  Widget _buildMedia() {
    if (_isCurrentVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      }
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFFF007F)),
          ),
        ),
      );
    }

    // Photo story
    if (_currentUrl.isEmpty) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black12,
          child: Center(
            child: Icon(
              Icons.image_not_supported,
              color: Colors.white38,
              size: 64,
            ),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: CachedNetworkImage(
        imageUrl: _currentUrl,
        fit: BoxFit.cover,
        memCacheWidth: 800, // Task 5: Global memory strategy
        placeholder: (p1_0, p1_1) => const ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFFF007F)),
          ),
        ),
        errorWidget: (p2_0, p2_1, p2_2) => const ColoredBox(
          color: Colors.black12,
          child: Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 52),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final story = _currentStory;
    final avatarUrl =
        (story['author_avatar'] ??
                story['user_avatar'] ??
                story['avatar_url'] ??
                story['user_image'] ??
                '')
            .toString();

    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Avatar with neon ring
        if (avatarUrl.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
              ),
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                errorWidget: (p3_0, p3_1, p3_2) => Container(
                  width: 34,
                  height: 34,
                  color: Colors.grey.shade800,
                  child: const Icon(
                    Icons.person,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(width: 8),

        // Username + story count
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.username,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.stories.length > 1)
                Text(
                  '${_currentIndex + 1} of ${widget.stories.length}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    const emojis = ['❤️', '🔥', '😂', '😮', '👏'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Quick Emoji Reacts ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: emojis.map((emoji) {
              return GestureDetector(
                onTap: () => _onEmojiTap(emoji),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.65),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF007F).withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Neon Reply TextField ────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 20),
                const Expanded(
                  child: TextField(
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Send a reply...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {}, // TODO: wire up send
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF007F,
                            ).withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _StoryProgressBar  –  animated gradient progress indicator per story segment
// ═══════════════════════════════════════════════════════════════════════════════

class _StoryProgressBar extends StatelessWidget {
  final AnimationController? controller;
  final bool isCompleted;

  const _StoryProgressBar({this.controller, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            // Background track
            Container(color: Colors.white24),
            // Filled portion
            if (isCompleted)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                  ),
                ),
              )
            else if (controller != null)
              AnimatedBuilder(
                animation: controller!,
                builder: (p4_0, p4_1) => FractionallySizedBox(
                  widthFactor: controller!.value,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _FlyingEmojiEntry  –  data holder for a single flying emoji instance
// ═══════════════════════════════════════════════════════════════════════════════

class _FlyingEmojiEntry {
  final Key key;
  final String emoji;
  final double offset; // horizontal jitter
  final void Function(Key) onDone;

  const _FlyingEmojiEntry({
    required this.key,
    required this.emoji,
    required this.offset,
    required this.onDone,
  });

  Widget buildWidget(Size screenSize) {
    return _FlyingEmojiWidget(
      key: key,
      emoji: emoji,
      startX: screenSize.width / 2 + offset,
      onDone: onDone,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _FlyingEmojiWidget  –  animated emoji that flies upward and fades out
// ═══════════════════════════════════════════════════════════════════════════════

class _FlyingEmojiWidget extends StatefulWidget {
  final String emoji;
  final double startX;
  final void Function(Key) onDone;

  const _FlyingEmojiWidget({
    super.key,
    required this.emoji,
    required this.startX,
    required this.onDone,
  });

  @override
  State<_FlyingEmojiWidget> createState() => _FlyingEmojiWidgetState();
}

class _FlyingEmojiWidgetState extends State<_FlyingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _translateY;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _translateY = Tween(
      begin: 0.0,
      end: -200.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );
    _scale = Tween(begin: 0.4, end: 1.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
      ),
    );

    _ctrl.forward().then((_) {
      if (widget.key != null) widget.onDone(widget.key!);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: widget.startX - 20,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _translateY.value),
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        ),
        child: Text(
          widget.emoji,
          style: const TextStyle(
            fontSize: 38,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}
