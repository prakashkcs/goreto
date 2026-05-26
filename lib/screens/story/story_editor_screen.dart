import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────
enum _Tool { none, text, draw, sticker, music, filter }

enum TextDisplayStyle { plain, shadow, neon, box, outline }

enum StoryFilterType { none, vivid, warm, cool, grayscale, fade }

enum _OverlayKind { text, tag, sticker }

// ── Models ─────────────────────────────────────────────────────────────────────
class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke({required this.points, required this.color, required this.width});
}

class _Overlay {
  final String id;
  final _OverlayKind kind;
  String text;
  Color color;
  TextDisplayStyle style;
  Offset position;
  double scale;
  double rotation;

  _Overlay({
    required this.id,
    required this.kind,
    required this.text,
    this.color = Colors.white,
    this.style = TextDisplayStyle.shadow,
    Offset? position,
    this.scale = 1.0,
    double rotation = 0.0,
  })  : rotation = rotation,
        position = position ?? const Offset(80, 200);
}

// ── Screen ─────────────────────────────────────────────────────────────────────
class StoryEditorScreen extends StatefulWidget {
  final File mediaFile;
  final String type; // 'image' or 'video'

  const StoryEditorScreen({
    super.key,
    required this.mediaFile,
    required this.type,
  });

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  static const _pink   = Color(0xFFFF007F);
  static const _cyan   = Color(0xFF00E5FF);
  static const _purple = Color(0xFFD946EF);

  final GlobalKey _repaintKey = GlobalKey();
  final ApiService _api = ApiService();

  _Tool _activeTool = _Tool.none;

  // Overlays
  final List<_Overlay> _overlays = [];

  // Drawing
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  Color _drawColor = Colors.white;
  double _brushSize = 6.0;

  // Text compose
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _musicCtrl = TextEditingController();
  Color _textColor = Colors.white;
  TextDisplayStyle _textStyle = TextDisplayStyle.shadow;
  bool _composingText = false;
  _Overlay? _editingOverlay;

  // Filter
  StoryFilterType _filter = StoryFilterType.none;

  // Music
  String _musicTitle = '';
  List<Map<String, String>> _songs = _kFallbackSongs;
  bool _songsLoading = false;
  AudioPlayer? _musicPreviewPlayer;
  bool _musicPlaying = false;

  static const List<Map<String, String>> _kFallbackSongs = [
    {'title': 'Nasayo',            'artist': 'Albatross'},
    {'title': 'Rara',              'artist': 'Swoopna Suman'},
    {'title': 'Swasni',            'artist': 'Prabesh Kumar Shrestha'},
    {'title': 'Bhool',             'artist': 'Sajjan Raj Vaidya'},
    {'title': 'Rokna Sakdina',     'artist': 'Sugam Pokhrel'},
    {'title': 'Sambodhan',         'artist': 'Sugam Pokhrel'},
    {'title': 'Timilai Dekhna',    'artist': 'Sabin Rai'},
    {'title': 'Sindoor',           'artist': 'Albatross'},
    {'title': 'Chhodi Ja',         'artist': 'Albatross'},
    {'title': 'Maya',              'artist': 'Bartika Eam Rai'},
    {'title': 'Parelima',          'artist': 'Santosh Lama'},
    {'title': 'Resham Firiri',     'artist': 'Traditional'},
    {'title': 'Kasto Manchhe',     'artist': '1974 AD'},
    {'title': 'Yesto Maya',        'artist': 'Sushant KC'},
    {'title': 'Aafai Hunthe',      'artist': 'Nabin K. Bhattarai'},
    {'title': 'Mann Nai Timilai',  'artist': 'Nabin K. Bhattarai'},
    {'title': 'Phool Ko Aakha Ma', 'artist': 'NB Das'},
    {'title': 'Taal',              'artist': 'Neetesh Jung Kunwar'},
    {'title': 'Nai Nai',           'artist': 'Samir Shrestha'},
    {'title': 'Eklai Basa',        'artist': 'Samir Shrestha'},
  ];

  // Video
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  // Upload
  bool _isUploading = false;

  // ── Filter matrices ────────────────────────────────────────────────────────
  static const Map<StoryFilterType, List<double>> _filterMatrix = {
    StoryFilterType.none: [
      1, 0, 0, 0, 0,  0, 1, 0, 0, 0,  0, 0, 1, 0, 0,  0, 0, 0, 1, 0,
    ],
    StoryFilterType.vivid: [
      1.3, 0,   0,   0, -15,  0,   1.3, 0,   0, -15,  0,   0,   1.3, 0, -15,  0, 0, 0, 1, 0,
    ],
    StoryFilterType.warm: [
      1.2, 0,   0,   0, 10,  0, 1.0, 0,   0, 0,  0,   0,   0.8, 0, -10,  0, 0, 0, 1, 0,
    ],
    StoryFilterType.cool: [
      0.8, 0,   0,   0, -5,  0, 1.0, 0,   0, 0,  0,   0,   1.3, 0, 10,   0, 0, 0, 1, 0,
    ],
    StoryFilterType.grayscale: [
      0.33, 0.59, 0.11, 0, 0,  0.33, 0.59, 0.11, 0, 0,  0.33, 0.59, 0.11, 0, 0,  0, 0, 0, 1, 0,
    ],
    StoryFilterType.fade: [
      0.8, 0.1, 0.1, 0, 25,  0.1, 0.8, 0.1, 0, 25,  0.1, 0.1, 0.8, 0, 25,  0, 0, 0, 1, 0,
    ],
  };

  ColorFilter get _activeColorFilter =>
      ColorFilter.matrix(_filterMatrix[_filter]!);

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') _initVideo();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() => _songsLoading = true);
    try {
      final resp = await http
          .get(Uri.parse('https://goreto.org/ekloadmin/popular_songs.php'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['songs'] as List?)
            ?.map((e) => Map<String, String>.from(e as Map))
            .toList();
        if (list != null && list.isNotEmpty && mounted) {
          setState(() => _songs = list);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _songsLoading = false);
  }

  Future<void> _initVideo() async {
    _videoCtrl = VideoPlayerController.file(widget.mediaFile);
    try {
      await _videoCtrl!.initialize();
      await _videoCtrl!.setLooping(true);
      await _videoCtrl!.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    _textCtrl.dispose();
    _musicCtrl.dispose();
    _musicPreviewPlayer?.stop();
    _musicPreviewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _playMusicPreview(String title, String artist) async {
    await _musicPreviewPlayer?.stop();
    _musicPreviewPlayer?.dispose();
    _musicPreviewPlayer = AudioPlayer();
    if (mounted) setState(() => _musicPlaying = false);

    try {
      final q = Uri.encodeComponent('$title $artist');
      final resp = await http
          .get(Uri.parse(
              'https://itunes.apple.com/search?term=$q&media=music&limit=1&entity=song'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final previewUrl = results[0]['previewUrl'] as String?;
          if (previewUrl != null && previewUrl.isNotEmpty) {
            await _musicPreviewPlayer!.play(UrlSource(previewUrl));
            if (mounted) setState(() => _musicPlaying = true);
            _musicPreviewPlayer!.onPlayerStateChanged.listen((s) {
              if (s == PlayerState.completed && mounted) {
                setState(() => _musicPlaying = false);
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  void _stopMusicPreview() {
    _musicPreviewPlayer?.stop();
    if (mounted) setState(() => _musicPlaying = false);
  }

  // ── Text compose ───────────────────────────────────────────────────────────
  void _openTextCompose([_Overlay? editing]) {
    _editingOverlay = editing;
    _textCtrl.text = editing?.text ?? '';
    _textColor = editing?.color ?? Colors.white;
    _textStyle = editing?.style ?? TextDisplayStyle.shadow;
    setState(() {
      _composingText = true;
      _activeTool = _Tool.none;
    });
  }

  void _confirmText() {
    final t = _textCtrl.text.trim();
    if (t.isNotEmpty) {
      setState(() {
        if (_editingOverlay != null) {
          _editingOverlay!.text = t;
          _editingOverlay!.color = _textColor;
          _editingOverlay!.style = _textStyle;
        } else {
          final size = MediaQuery.of(context).size;
          _overlays.add(_Overlay(
            id: '${DateTime.now().millisecondsSinceEpoch}',
            kind: _OverlayKind.text,
            text: t,
            color: _textColor,
            style: _textStyle,
            position: Offset(size.width * 0.1, size.height * 0.35),
          ));
        }
      });
      SoundService().playTap();
    }
    _textCtrl.clear();
    _editingOverlay = null;
    setState(() => _composingText = false);
  }

  // ── Tag overlay ─────────────────────────────────────────────────────────────
  void _addTagOverlay(String username) {
    if (username.isEmpty) return;
    final size = MediaQuery.of(context).size;
    setState(() {
      _overlays.add(_Overlay(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        kind: _OverlayKind.tag,
        text: username,
        position: Offset(size.width * 0.15, size.height * 0.45),
      ));
      _activeTool = _Tool.none;
    });
    SoundService().playTap();
  }

  // ── Drawing ────────────────────────────────────────────────────────────────
  void _onDrawStart(DragStartDetails d) => setState(() {
        _currentStroke =
            _Stroke(points: [d.localPosition], color: _drawColor, width: _brushSize);
      });

  void _onDrawUpdate(DragUpdateDetails d) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke = _Stroke(
        points: [..._currentStroke!.points, d.localPosition],
        color: _currentStroke!.color,
        width: _currentStroke!.width,
      );
    });
  }

  void _onDrawEnd(DragEndDetails d) {
    if (_currentStroke != null && _currentStroke!.points.length > 1) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
      });
    }
  }

  // ── Sticker ────────────────────────────────────────────────────────────────
  void _addSticker(String emoji) {
    final size = MediaQuery.of(context).size;
    setState(() {
      _overlays.add(_Overlay(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        kind: _OverlayKind.sticker,
        text: emoji,
        position: Offset(size.width * 0.3, size.height * 0.3),
        scale: 1.8,
      ));
      _activeTool = _Tool.none;
    });
    SoundService().playTap();
  }

  // ── Render & upload ────────────────────────────────────────────────────────
  Future<void> _handleShare() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    SoundService().playTap();

    try {
      final fileToUpload =
          widget.type == 'image' ? await _renderToImage() : widget.mediaFile;

      final tags = _overlays
          .where((o) => o.kind == _OverlayKind.tag)
          .map((o) => o.text)
          .toList();

      // Encode text overlay metadata for server
      final textMeta = _overlays
          .where((o) => o.kind == _OverlayKind.text)
          .map((o) => {
                'text': o.text,
                'style': o.style.name,
                'color': o.color.toARGB32(),
              })
          .toList();

      await _api.uploadStory(
        fileToUpload,
        type: widget.type,
        music: _musicTitle.isNotEmpty ? _musicTitle : null,
        tags: tags.isNotEmpty ? tags : null,
        filterName: _filter != StoryFilterType.none ? _filter.name : null,
        textOverlays: textMeta.isNotEmpty ? jsonEncode(textMeta) : null,
      );

      if (mounted) {
        NeonToast.success(context, 'Story shared!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<File> _renderToImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 80));
      final boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return widget.mediaFile;
      final img = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return widget.mediaFile;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes.buffer.asUint8List());
      return f;
    } catch (_) {
      return widget.mediaFile;
    }
  }

  // ── Overlay widget builder ─────────────────────────────────────────────────
  Widget _buildOverlay(_Overlay ov) {
    Widget content;

    if (ov.kind == _OverlayKind.sticker) {
      content = Text(ov.text, style: const TextStyle(fontSize: 52));
    } else if (ov.kind == _OverlayKind.tag) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_cyan, _purple]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.35), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.alternate_email, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(ov.text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      );
    } else {
      content = _styledText(ov);
    }

    return _DraggableItem(
      key: ValueKey(ov.id),
      initialPosition: ov.position,
      initialScale: ov.scale,
      initialRotation: ov.rotation,
      onPositionChanged: (p) => ov.position = p,
      onScaleChanged: (s) => ov.scale = s,
      onRotationChanged: (r) => ov.rotation = r,
      onTap: ov.kind == _OverlayKind.text ? () => _openTextCompose(ov) : null,
      onLongPress: () => setState(() => _overlays.remove(ov)),
      child: content,
    );
  }

  Widget _styledText(_Overlay ov) {
    switch (ov.style) {
      case TextDisplayStyle.plain:
        return Text(ov.text,
            style: TextStyle(color: ov.color, fontSize: 26, fontWeight: FontWeight.bold));

      case TextDisplayStyle.shadow:
        return Text(ov.text,
            style: TextStyle(
              color: ov.color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 12, offset: Offset(2, 2)),
                Shadow(color: Colors.black54, blurRadius: 20),
              ],
            ));

      case TextDisplayStyle.neon:
        return Text(ov.text,
            style: TextStyle(
              color: ov.color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: ov.color, blurRadius: 8),
                Shadow(color: ov.color, blurRadius: 20),
                Shadow(color: ov.color.withValues(alpha: 0.4), blurRadius: 35),
              ],
            ));

      case TextDisplayStyle.box:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(ov.text,
              style: TextStyle(color: ov.color, fontSize: 26, fontWeight: FontWeight.bold)),
        );

      case TextDisplayStyle.outline:
        return Stack(
          children: [
            Text(ov.text,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 4
                    ..color = Colors.black,
                )),
            Text(ov.text,
                style: TextStyle(
                    color: ov.color, fontSize: 26, fontWeight: FontWeight.bold)),
          ],
        );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1 ── Captured canvas ─────────────────────────────────────────
            RepaintBoundary(
              key: _repaintKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Media + filter
                  if (widget.type == 'image')
                    ColorFiltered(
                      colorFilter: _activeColorFilter,
                      child: Image.file(widget.mediaFile,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity),
                    )
                  else if (widget.type == 'video' && _videoReady && _videoCtrl != null)
                    ColorFiltered(
                      colorFilter: _activeColorFilter,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF1A1A1A),
                      child: const Center(child: CircularProgressIndicator(color: _cyan)),
                    ),

                  // Drawing layer
                  if (_strokes.isNotEmpty || _currentStroke != null)
                    CustomPaint(
                      painter: _DrawingPainter(strokes: _strokes, current: _currentStroke),
                      child: const SizedBox.expand(),
                    ),

                  // Overlays
                  ..._overlays.map(_buildOverlay),

                  // Music badge (baked into capture)
                  if (_musicTitle.isNotEmpty)
                    Positioned(
                      bottom: 70,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _pink.withValues(alpha: 0.45)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.music_note, color: _pink, size: 14),
                            const SizedBox(width: 6),
                            Text(_musicTitle,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2 ── Drawing gesture capture ─────────────────────────────────
            if (_activeTool == _Tool.draw)
              GestureDetector(
                onPanStart: _onDrawStart,
                onPanUpdate: _onDrawUpdate,
                onPanEnd: _onDrawEnd,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),

            // 3 ── Text compose overlay (full-screen) ─────────────────────
            if (_composingText) _buildTextComposeOverlay(),

            // 4 ── Top bar ─────────────────────────────────────────────────
            if (!_composingText)
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

            // 5 ── Tool panel ──────────────────────────────────────────────
            if (!_composingText && _activeTool != _Tool.none && _activeTool != _Tool.text)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                bottom: () {
                  final kb = MediaQuery.of(context).viewInsets.bottom;
                  return kb > 0 ? kb + 8.0 : 90.0;
                }(),
                left: 0,
                right: 0,
                child: _buildToolPanel(),
              ),

            // 6 ── Bottom toolbar ──────────────────────────────────────────
            if (!_composingText)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomToolbar()),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          _iconBtn(Icons.close_rounded, onTap: () => Navigator.pop(context)),
          const Spacer(),
          if (_activeTool == _Tool.draw && _strokes.isNotEmpty) ...[
            _iconBtn(Icons.undo_rounded,
                onTap: () => setState(() => _strokes.removeLast())),
            const SizedBox(width: 8),
          ],
          _iconBtn(Icons.download_rounded, onTap: () async {
            if (widget.type == 'image') {
              await _renderToImage();
              if (mounted) NeonToast.success(context, 'Saved to drafts!');
            }
          }),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _isUploading ? null : _handleShare,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_pink, _purple]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: _pink.withValues(alpha: 0.45), blurRadius: 12)
                ],
              ),
              child: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Share',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tool panel dispatcher ──────────────────────────────────────────────────
  Widget _buildToolPanel() {
    return switch (_activeTool) {
      _Tool.draw    => _buildDrawPanel(),
      _Tool.sticker => _buildStickerPanel(),
      _Tool.music   => _buildMusicPanel(),
      _Tool.filter  => _buildFilterPanel(),
      _             => const SizedBox.shrink(),
    };
  }

  // ── Draw panel ─────────────────────────────────────────────────────────────
  Widget _buildDrawPanel() {
    const colors = [
      Colors.white, Colors.black, _pink, _cyan, _purple,
      Colors.yellow, Colors.orange, Colors.green, Colors.red, Colors.blue,
    ];
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors
                .map((c) => GestureDetector(
                      onTap: () => setState(() => _drawColor = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _drawColor == c ? _cyan : Colors.white24,
                            width: _drawColor == c ? 3 : 1,
                          ),
                          boxShadow: _drawColor == c
                              ? [BoxShadow(color: _cyan.withValues(alpha: 0.6), blurRadius: 8)]
                              : null,
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.brush_rounded,
                  color: _drawColor, size: _brushSize.clamp(14, 24)),
              Expanded(
                child: Slider(
                  value: _brushSize,
                  min: 2,
                  max: 28,
                  activeColor: _pink,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _brushSize = v),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _strokes.clear()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Clear',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Sticker panel ──────────────────────────────────────────────────────────
  Widget _buildStickerPanel() {
    const emojis = [
      '😍','❤️','🔥','✨','💫','🎉','😂','😎',
      '🥰','💕','🌸','🦋','🌈','⭐','💯','🎶',
      '🙌','👑','🌙','🍀','💎','🚀','🌺','🎸',
      '😏','🤩','💜','🩷','🧡','💛','💚','💙',
    ];
    final tagCtrl = TextEditingController();
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag input
          Row(
            children: [
              const Icon(Icons.alternate_email, color: _cyan, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: tagCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tag someone...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onSubmitted: (v) => _addTagOverlay(v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _addTagOverlay(tagCtrl.text.trim()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_cyan, _purple]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Add', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          // Emoji grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: emojis
                .map((e) => GestureDetector(
                      onTap: () => _addSticker(e),
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── Music panel ────────────────────────────────────────────────────────────
  Widget _buildMusicPanel() {
    final query = _musicCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _songs
        : _songs.where((s) {
            return (s['title'] ?? '').toLowerCase().contains(query) ||
                (s['artist'] ?? '').toLowerCase().contains(query);
          }).toList();

    return _panel(
      borderColor: _pink.withValues(alpha: 0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.music_note_rounded, color: _pink, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Add Music',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (_musicTitle.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _musicTitle = '';
                    _musicCtrl.clear();
                  }),
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Search field
          TextField(
            controller: _musicCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search song or artist...',
              hintStyle: const TextStyle(color: Colors.white38),
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
              suffixIcon: _musicCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white38, size: 18),
                      onPressed: () => setState(() => _musicCtrl.clear()),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              final trimmed = v.trim();
              if (trimmed.isNotEmpty) {
                setState(() {
                  _musicTitle = trimmed;
                  _activeTool = _Tool.none;
                });
                FocusScope.of(context).unfocus();
              }
            },
          ),
          const SizedBox(height: 10),

          // Song list
          if (_songsLoading && _songs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: _pink, strokeWidth: 2)),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No songs found for "$query"',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => Divider(
                    color: Colors.white.withValues(alpha: 0.06),
                    height: 1),
                itemBuilder: (_, i) {
                  final song = filtered[i];
                  final title = song['title'] ?? '';
                  final artist = song['artist'] ?? '';
                  final isSelected = _musicTitle == title;
                  final isPlaying = isSelected && _musicPlaying;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() => _musicTitle = title);
                        _playMusicPreview(title, artist);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 9),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _pink.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isPlaying
                                    ? Icons.graphic_eq_rounded
                                    : isSelected
                                        ? Icons.music_note_rounded
                                        : Icons.music_note_outlined,
                                color: isSelected ? _pink : Colors.white38,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      style: TextStyle(
                                          color: isSelected
                                              ? _pink
                                              : Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      isPlaying ? 'Playing preview...' : artist,
                                      style: TextStyle(
                                          color: isPlaying
                                              ? _pink.withValues(alpha: 0.8)
                                              : Colors.white38,
                                          fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.check_circle_rounded,
                                color: _pink,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Filter panel ───────────────────────────────────────────────────────────
  Widget _buildFilterPanel() {
    final filters = [
      (StoryFilterType.none, 'Normal'),
      (StoryFilterType.vivid, 'Vivid'),
      (StoryFilterType.warm, 'Warm'),
      (StoryFilterType.cool, 'Cool'),
      (StoryFilterType.grayscale, 'B&W'),
      (StoryFilterType.fade, 'Fade'),
    ];
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final type = filters[i].$1;
          final label = filters[i].$2;
          final selected = _filter == type;
          return GestureDetector(
            onTap: () => setState(() => _filter = type),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? _cyan : Colors.white24,
                      width: selected ? 2.5 : 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: _cyan.withValues(alpha: 0.4), blurRadius: 8)]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(_filterMatrix[type]!),
                      child: widget.type == 'image'
                          ? Image.file(widget.mediaFile, fit: BoxFit.cover)
                          : Container(
                              color: Colors.grey.shade800,
                              child: const Center(
                                  child: Icon(Icons.videocam_rounded,
                                      color: Colors.white54, size: 28)),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                      color: selected ? _cyan : Colors.white60,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Text compose overlay ───────────────────────────────────────────────────
  Widget _buildTextComposeOverlay() {
    const styles = [
      (TextDisplayStyle.shadow, 'Shadow'),
      (TextDisplayStyle.plain,   'Plain'),
      (TextDisplayStyle.neon,    'Neon'),
      (TextDisplayStyle.box,     'Box'),
      (TextDisplayStyle.outline, 'Outline'),
    ];
    const colors = [
      Colors.white, Colors.black, _pink, _cyan,
      _purple, Color(0xFFFFD700), Colors.red, Colors.green,
    ];

    return GestureDetector(
      onTap: _confirmText,
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Column(
          children: [
            // Style pills
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: styles.map((s) {
                    final selected = _textStyle == s.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _textStyle = s.$1),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? _pink
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? _pink : Colors.white24),
                        ),
                        child: Text(s.$2,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const Spacer(),

            // Text field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () {},
                child: TextField(
                  controller: _textCtrl,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  maxLines: null,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: _textStyle == TextDisplayStyle.neon
                        ? [Shadow(color: _textColor, blurRadius: 14)]
                        : _textStyle == TextDisplayStyle.shadow
                            ? const [Shadow(color: Colors.black, blurRadius: 8, offset: Offset(2, 2))]
                            : null,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Type something...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 24),
                    filled: _textStyle == TextDisplayStyle.box,
                    fillColor: _textStyle == TextDisplayStyle.box ? Colors.black54 : null,
                  ),
                  onSubmitted: (_) => _confirmText(),
                ),
              ),
            ),

            const Spacer(),

            // Color row + done
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: colors.map((c) => GestureDetector(
                          onTap: () => setState(() => _textColor = c),
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _textColor == c ? _cyan : Colors.white24,
                                width: _textColor == c ? 2.5 : 1,
                              ),
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _confirmText,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: _pink, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom toolbar ─────────────────────────────────────────────────────────
  Widget _buildBottomToolbar() {
    final tools = [
      (_Tool.text,    Icons.text_fields_rounded,   'Text',    _pink),
      (_Tool.draw,    Icons.brush_rounded,          'Draw',    _cyan),
      (_Tool.sticker, Icons.emoji_emotions_rounded, 'Sticker', _purple),
      (_Tool.music,   Icons.music_note_rounded,     'Music',   const Color(0xFFFF6B35)),
      (_Tool.filter,  Icons.auto_awesome_rounded,   'Filter',  const Color(0xFF38EF7D)),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, 10, 8, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.92), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((t) {
          final tool = t.$1;
          final icon = t.$2;
          final label = t.$3;
          final color = t.$4;
          final active = _activeTool == tool;
          // Music gets dot indicator when set
          final hasBadge = tool == _Tool.music && _musicTitle.isNotEmpty;

          return GestureDetector(
            onTap: () {
              if (tool == _Tool.text) {
                _openTextCompose();
              } else {
                if (tool != _Tool.music) _stopMusicPreview();
                setState(() => _activeTool = active ? _Tool.none : tool);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: active ? color : Colors.transparent, width: 1.2),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: active ? color : Colors.white70, size: 26),
                      const SizedBox(height: 3),
                      Text(label,
                          style: TextStyle(
                            color: active ? color : Colors.white60,
                            fontSize: 10,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          )),
                    ],
                  ),
                  if (hasBadge)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: _pink, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _panel({required Widget child, Color? borderColor}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? Colors.white12),
      ),
      child: child,
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Drawing painter ────────────────────────────────────────────────────────────
class _DrawingPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;

  const _DrawingPainter({required this.strokes, this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...strokes, if (current != null) current!];
    for (final stroke in all) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length - 1; i++) {
        final mid = Offset(
          (stroke.points[i].dx + stroke.points[i + 1].dx) / 2,
          (stroke.points[i].dy + stroke.points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(
          stroke.points[i].dx, stroke.points[i].dy,
          mid.dx, mid.dy,
        );
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) =>
      old.strokes != strokes || old.current != current;
}

// ── Draggable item wrapper ─────────────────────────────────────────────────────
class _DraggableItem extends StatefulWidget {
  final Widget child;
  final Offset initialPosition;
  final double initialScale;
  final double initialRotation;
  final ValueChanged<Offset>? onPositionChanged;
  final ValueChanged<double>? onScaleChanged;
  final ValueChanged<double>? onRotationChanged;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DraggableItem({
    super.key,
    required this.child,
    required this.initialPosition,
    this.initialScale = 1.0,
    this.initialRotation = 0.0,
    this.onPositionChanged,
    this.onScaleChanged,
    this.onRotationChanged,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_DraggableItem> createState() => _DraggableItemState();
}

class _DraggableItemState extends State<_DraggableItem> {
  late Offset _pos;
  late double _scale;
  late double _rot;
  double _baseScale = 1.0;
  double _baseRot = 0.0;
  Offset? _lastFocal;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPosition;
    _scale = widget.initialScale;
    _rot = widget.initialRotation;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onScaleStart: (d) {
          _baseScale = _scale;
          _baseRot = _rot;
          _lastFocal = d.localFocalPoint;
        },
        onScaleUpdate: (d) {
          setState(() {
            if (_lastFocal != null) _pos += d.localFocalPoint - _lastFocal!;
            _lastFocal = d.localFocalPoint;
            _scale = (_baseScale * d.scale).clamp(0.3, 4.0);
            _rot = _baseRot + d.rotation;
          });
          widget.onPositionChanged?.call(_pos);
          widget.onScaleChanged?.call(_scale);
          widget.onRotationChanged?.call(_rot);
        },
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Transform.rotate(
          angle: _rot,
          child: Transform.scale(scale: _scale, child: widget.child),
        ),
      ),
    );
  }
}
