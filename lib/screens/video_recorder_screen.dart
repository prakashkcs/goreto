import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/screens/publish_post_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// TikTok-style camera recorder with filters and sound selection.
class VideoRecorderScreen extends StatefulWidget {
  /// Sound name pre-selected (e.g. from "Use This Sound" flow).
  final String? initialSoundName;

  const VideoRecorderScreen({super.key, this.initialSoundName});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _cameraReady = false;
  bool _isRecording = false;
  bool _frontCamera = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _selectedSoundName;
  int _selectedFilterIndex = 0;
  int _filterCategory = 0;

  // ── Filter category groups ─────────────────────────────────────────────────
  static const List<List<int>> _filterGroups = [
    [0, 8, 12, 17, 18, 24, 27],     // Beauty
    [1, 2, 3, 20, 26, 16, 10],      // Color
    [7, 4, 5, 13, 21, 19, 22, 23],  // Cinematic
    [6, 14, 15, 9, 11, 28, 25],     // FX
  ];
  static const List<String> _filterCategoryLabels = ['Beauty', 'Color', 'Cinematic', 'FX'];
  static const List<String> _filterCategoryEmoji = ['✨', '🎨', '🎬', '⚡'];
  static const List<List<Color>> _filterCategoryColors = [
    [Color(0xFFFF007F), Color(0xFFFF69B4)],
    [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
    [Color(0xFF1C1C1E), Color(0xFF6B7280)],
    [Color(0xFF00C6FF), Color(0xFF00FF88)],
  ];

  // ── Filters (TikTok-style advanced) ───────────────────────────────────────
  static const List<_FilterDef> _filters = [
    _FilterDef('None', null),
    // Vivid – boosted saturation
    _FilterDef(
        'Vivid',
        ColorFilter.matrix([
          1.4,
          0,
          0,
          0,
          -20,
          0,
          1.4,
          0,
          0,
          -20,
          0,
          0,
          1.4,
          0,
          -20,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Warm – golden hour
    _FilterDef(
        'Warm',
        ColorFilter.matrix([
          1.2,
          0.1,
          0,
          0,
          10,
          0,
          1.0,
          0,
          0,
          5,
          0,
          0,
          0.8,
          0,
          -5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Cool – blue tint
    _FilterDef(
        'Cool',
        ColorFilter.matrix([
          0.8,
          0,
          0.1,
          0,
          -5,
          0,
          0.9,
          0.1,
          0,
          0,
          0.1,
          0,
          1.2,
          0,
          10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // B&W – classic monochrome
    _FilterDef(
        'B&W',
        ColorFilter.matrix([
          0.33,
          0.59,
          0.11,
          0,
          0,
          0.33,
          0.59,
          0.11,
          0,
          0,
          0.33,
          0.59,
          0.11,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Vintage – faded film look
    _FilterDef(
        'Vintage',
        ColorFilter.matrix([
          0.9,
          0.1,
          0.1,
          0,
          15,
          0.1,
          0.8,
          0.1,
          0,
          10,
          0.1,
          0.1,
          0.7,
          0,
          5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Neon – cyberpunk glow
    _FilterDef(
        'Neon',
        ColorFilter.matrix([
          1.0,
          0,
          0.3,
          0,
          20,
          0,
          0.8,
          0.3,
          0,
          -10,
          0.3,
          0,
          1.3,
          0,
          10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Drama – high contrast dark
    _FilterDef(
        'Drama',
        ColorFilter.matrix([
          1.1,
          0,
          0,
          0,
          -15,
          0,
          0.9,
          0,
          0,
          -10,
          0,
          0,
          0.8,
          0,
          -20,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Rosy – pink beauty filter (TikTok "Beauty")
    _FilterDef(
        'Rosy',
        ColorFilter.matrix([
          1.1,
          0.05,
          0.05,
          0,
          10,
          0,
          0.95,
          0.05,
          0,
          5,
          0,
          0,
          0.9,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Fade – matte/faded look (TikTok "Fade")
    _FilterDef(
        'Fade',
        ColorFilter.matrix([
          0.85,
          0,
          0,
          0,
          30,
          0,
          0.85,
          0,
          0,
          30,
          0,
          0,
          0.85,
          0,
          30,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Sunset – orange-red tones
    _FilterDef(
        'Sunset',
        ColorFilter.matrix([
          1.3,
          0.1,
          0,
          0,
          20,
          0,
          0.9,
          0,
          0,
          -5,
          0,
          0,
          0.7,
          0,
          -10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Forest – green nature tones
    _FilterDef(
        'Forest',
        ColorFilter.matrix([
          0.8,
          0,
          0,
          0,
          -5,
          0.1,
          1.1,
          0.1,
          0,
          10,
          0,
          0,
          0.8,
          0,
          -5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Glam – bright high-key (TikTok "Glam")
    _FilterDef(
        'Glam',
        ColorFilter.matrix([
          1.15,
          0,
          0,
          0,
          15,
          0,
          1.15,
          0,
          0,
          15,
          0,
          0,
          1.15,
          0,
          15,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Moody – desaturated dark (TikTok "Moody")
    _FilterDef(
        'Moody',
        ColorFilter.matrix([
          0.7,
          0.1,
          0.1,
          0,
          -10,
          0.1,
          0.7,
          0.1,
          0,
          -10,
          0.1,
          0.1,
          0.7,
          0,
          -10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Sepia – warm brown tones
    _FilterDef(
        'Sepia',
        ColorFilter.matrix([
          0.393,
          0.769,
          0.189,
          0,
          0,
          0.349,
          0.686,
          0.168,
          0,
          0,
          0.272,
          0.534,
          0.131,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Invert – negative (TikTok "Invert")
    _FilterDef(
        'Invert',
        ColorFilter.matrix([
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Pop – punchy vibrant (TikTok "Pop")
    _FilterDef(
        'Pop',
        ColorFilter.matrix([
          1.5,
          0,
          0,
          0,
          -30,
          0,
          1.4,
          0,
          0,
          -20,
          0,
          0,
          1.3,
          0,
          -10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Soft – gentle beauty glow (TikTok "Soft")
    _FilterDef(
        'Soft',
        ColorFilter.matrix([
          1.05,
          0.02,
          0.02,
          0,
          8,
          0.02,
          1.05,
          0.02,
          0,
          8,
          0.02,
          0.02,
          1.05,
          0,
          8,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Cream – warm creamy skin tone (TikTok "Cream")
    _FilterDef(
        'Cream',
        ColorFilter.matrix([
          1.1,
          0.05,
          0,
          0,
          12,
          0.05,
          1.05,
          0,
          0,
          8,
          0,
          0,
          0.95,
          0,
          5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Lomo – dark vignette feel (TikTok "Lomo")
    _FilterDef(
        'Lomo',
        ColorFilter.matrix([
          1.2,
          0,
          0,
          0,
          -25,
          0,
          1.0,
          0,
          0,
          -15,
          0,
          0,
          0.9,
          0,
          -10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Aqua – blue-green ocean (TikTok "Aqua")
    _FilterDef(
        'Aqua',
        ColorFilter.matrix([
          0.85,
          0,
          0.15,
          0,
          5,
          0.1,
          1.0,
          0.1,
          0,
          10,
          0.15,
          0,
          1.1,
          0,
          15,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Retro – 90s film look (TikTok "Retro")
    _FilterDef(
        'Retro',
        ColorFilter.matrix([
          1.0,
          0.1,
          0,
          0,
          5,
          0,
          0.9,
          0.1,
          0,
          0,
          0,
          0.1,
          0.8,
          0,
          -5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // VHS – analog glitch feel (TikTok "VHS")
    _FilterDef(
        'VHS',
        ColorFilter.matrix([
          1.1,
          0.05,
          -0.05,
          0,
          0,
          -0.05,
          1.0,
          0.05,
          0,
          5,
          0.05,
          -0.05,
          1.1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Noir – high contrast B&W (TikTok "Noir")
    _FilterDef(
        'Noir',
        ColorFilter.matrix([
          0.5,
          0.5,
          0.5,
          0,
          -30,
          0.5,
          0.5,
          0.5,
          0,
          -30,
          0.5,
          0.5,
          0.5,
          0,
          -30,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Peach – warm peachy glow (TikTok "Peach")
    _FilterDef(
        'Peach',
        ColorFilter.matrix([
          1.2,
          0.1,
          0,
          0,
          15,
          0,
          1.0,
          0,
          0,
          5,
          0,
          0,
          0.85,
          0,
          -5,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Cyber – neon green/pink (TikTok "Cyber")
    _FilterDef(
        'Cyber',
        ColorFilter.matrix([
          1.2,
          0,
          0.2,
          0,
          10,
          0,
          1.0,
          0.2,
          0,
          0,
          0.2,
          0,
          1.2,
          0,
          10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Golden – rich golden hour (TikTok "Golden")
    _FilterDef(
        'Golden',
        ColorFilter.matrix([
          1.3,
          0.15,
          0,
          0,
          20,
          0,
          1.1,
          0,
          0,
          10,
          0,
          0,
          0.7,
          0,
          -10,
          0,
          0,
          0,
          1,
          0,
        ])),
    // Pastel – soft pastel tones (TikTok "Pastel")
    _FilterDef(
        'Pastel',
        ColorFilter.matrix([
          1.0,
          0.1,
          0.1,
          0,
          15,
          0.1,
          1.0,
          0.1,
          0,
          15,
          0.1,
          0.1,
          1.0,
          0,
          15,
          0,
          0,
          0,
          1,
          0,
        ])),
    // HDR – high dynamic range punch (TikTok "HDR")
    _FilterDef(
        'HDR',
        ColorFilter.matrix([
          1.3,
          0,
          0,
          0,
          -20,
          0,
          1.2,
          0,
          0,
          -10,
          0,
          0,
          1.1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ])),
  ];

  // ── Trending sounds (loaded from reels) ───────────────────────────────────
  List<String> _sounds = [];
  bool _loadingSounds = false;
  bool _showSoundPicker = false;

  // ── Countdown timer ───────────────────────────────────────────────────────
  int _timerSeconds = 0; // 0 = off, 3 = 3s, 10 = 10s
  bool _isCountingDown = false;
  int _countdownRemaining = 0;
  Timer? _countdownTimer;

  // ── Max recording duration ────────────────────────────────────────────────
  static const int _maxSeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedSoundName = widget.initialSoundName;
    // Start with front (selfie) camera for reels creation
    _initCamera(cameraIndex: 1);
    _loadTrendingSounds();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Null out _controller BEFORE disposing so _initCamera won't try to
      // dispose it a second time on resume.
      final ctrl = _controller;
      if (ctrl != null) {
        setState(() {
          _controller = null;
          _cameraReady = false;
        });
        ctrl.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(cameraIndex: _frontCamera ? 1 : 0);
    }
  }

  Future<void> _initCamera({int cameraIndex = 0}) async {
    setState(() => _cameraReady = false);
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // For selfie (front) camera, find the actual front-facing camera
      // instead of blindly using index 1 (which may not exist or may be wrong)
      int idx;
      if (cameraIndex == 1) {
        // Find front camera by lens direction
        final frontIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        idx = frontIdx >= 0 ? frontIdx : 0;
      } else {
        // Find back camera by lens direction
        final backIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        idx = backIdx >= 0 ? backIdx : 0;
      }

      // Dispose old controller BEFORE creating new one to avoid resource conflicts
      final old = _controller;
      _controller = null;
      await old?.dispose();

      final ctrl = CameraController(
        _cameras[idx],
        ResolutionPreset.high,
        enableAudio: true,
        // Use nv21 for better compatibility with front-facing cameras on Android
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _cameraReady = true;
        _frontCamera = _cameras[idx].lensDirection == CameraLensDirection.front;
      });
    } catch (e) {
      // If front camera fails, try back camera as fallback
      if (cameraIndex == 1 && _cameras.isNotEmpty) {
        final backIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (backIdx >= 0) {
          try {
            final ctrl = CameraController(
              _cameras[backIdx],
              ResolutionPreset.high,
              enableAudio: true,
              imageFormatGroup: Platform.isAndroid
                  ? ImageFormatGroup.nv21
                  : ImageFormatGroup.bgra8888,
            );
            await ctrl.initialize();
            if (mounted) {
              setState(() {
                _controller = ctrl;
                _cameraReady = true;
                _frontCamera = false;
              });
              return;
            }
            await ctrl.dispose();
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  Future<void> _flipCamera() async {
    HapticFeedback.lightImpact();
    final nextIndex = _frontCamera ? 0 : 1;
    await _initCamera(cameraIndex: nextIndex);
  }

  Future<void> _toggleRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !_cameraReady) return;

    if (_isCountingDown) {
      _cancelCountdown();
      return;
    }
    if (_isRecording) {
      await _stopRecording();
    } else if (_timerSeconds > 0) {
      _startCountdown();
    } else {
      await _startRecording();
    }
  }

  void _startCountdown() {
    HapticFeedback.lightImpact();
    setState(() {
      _isCountingDown = true;
      _countdownRemaining = _timerSeconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdownRemaining <= 1) {
        t.cancel();
        setState(() {
          _isCountingDown = false;
          _countdownRemaining = 0;
        });
        _startRecording();
      } else {
        HapticFeedback.selectionClick();
        setState(() => _countdownRemaining--);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownRemaining = 0;
    });
  }

  Future<void> _startRecording() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    HapticFeedback.mediumImpact();
    try {
      await ctrl.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= _maxSeconds) _stopRecording();
      });
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    final ctrl = _controller;
    if (ctrl == null || !_isRecording) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRecording = false);
    try {
      final file = await ctrl.stopVideoRecording();
      if (!mounted) return;

      // Extract thumbnail (first frame) using video_thumbnail
      String? thumbnailPath;
      try {
        final tmpDir = await getTemporaryDirectory();
        thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: file.path,
          thumbnailPath: tmpDir.path,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 720,
          quality: 85,
          timeMs: 0, // first frame
        );
      } catch (_) {}

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PublishPostScreen(
            mediaType: 'reel',
            mediaPath: file.path,
            soundName: _selectedSoundName,
            thumbnailPath: thumbnailPath,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Extract audio from a video file and return the .m4a path.
  /// Called from the publish screen via a static helper.
  /// NOTE: Audio extraction is now handled server-side for reliability.
  /// This stub returns null so the upload proceeds with video only;
  /// the backend can extract audio if needed.
  static Future<String?> extractAudioFromVideo(String videoPath) async {
    // Server-side audio extraction is preferred.
    // Returning null lets the upload flow continue with the video file only.
    return null;
  }

  Future<void> _loadTrendingSounds() async {
    setState(() => _loadingSounds = true);
    try {
      final reels = await ApiService().getReels(type: 'trending');
      final Set<String> names = {};
      for (final r in reels) {
        final name =
            (r['sound_name'] ?? r['audio_name'] ?? r['music_name'] ?? '')
                .toString();
        if (name.isNotEmpty && name != 'Original Audio') names.add(name);
      }
      if (mounted) {
        setState(() {
          _sounds = names.take(30).toList();
          _loadingSounds = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSounds = false);
    }
  }

  String get _recordingProgress {
    final pct = (_recordingSeconds / _maxSeconds * 100).round();
    return '${_recordingSeconds}s  $pct%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview with selected filter
          if (_cameraReady && _controller != null)
            _selectedFilterIndex == 0
                ? CameraPreview(_controller!)
                : ColorFiltered(
                    colorFilter: _filters[_selectedFilterIndex].filter!,
                    child: CameraPreview(_controller!),
                  )
          else
            const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF007F))),

          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // Recording progress bar
          if (_isRecording)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _recordingSeconds / _maxSeconds,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFF007F)),
                minHeight: 4,
              ),
            ),

          // Sound picker overlay
          if (_showSoundPicker) Positioned.fill(child: _buildSoundPicker()),

          // Countdown overlay
          if (_isCountingDown) _buildCountdownOverlay(),

          // Filter strip + record button at bottom
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterStrip(),
                const SizedBox(height: 24),
                _buildRecordRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _iconBtn(Icons.close, onTap: () => Navigator.pop(context)),
          const Spacer(),

          // Sound selector
          GestureDetector(
            onTap: () => setState(() => _showSoundPicker = !_showSoundPicker),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedSoundName != null
                      ? const Color(0xFFFF007F)
                      : Colors.white30,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.music_note,
                    color: _selectedSoundName != null
                        ? const Color(0xFFFF007F)
                        : Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      _selectedSoundName ?? 'Add Sound',
                      style: TextStyle(
                        color: _selectedSoundName != null
                            ? const Color(0xFFFF007F)
                            : Colors.white70,
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

          const SizedBox(width: 12),
          _timerBtn(),
          const SizedBox(width: 12),
          _iconBtn(Icons.flip_camera_ios, onTap: _flipCamera),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _timerBtn() {
    final active = _timerSeconds > 0;
    final label = _timerSeconds == 0 ? 'Off' : '${_timerSeconds}s';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (_timerSeconds == 0) {
            _timerSeconds = 3;
          } else if (_timerSeconds == 3) {
            _timerSeconds = 10;
          } else {
            _timerSeconds = 0;
          }
        });
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF007F).withValues(alpha: 0.25) : Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? const Color(0xFFFF007F) : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer, color: active ? const Color(0xFFFF007F) : Colors.white, size: 16),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFFF007F) : Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cancelCountdown,
        child: Container(
          color: Colors.black38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: Tween<double>(begin: 1.4, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  ),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(
                  '$_countdownRemaining',
                  key: ValueKey(_countdownRemaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Color(0xFFFF007F), blurRadius: 40),
                      Shadow(color: Color(0xFFFF007F), blurRadius: 80),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tap anywhere to cancel',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter strip ───────────────────────────────────────────────────────────

  Widget _buildFilterStrip() {
    final catColors = _filterCategoryColors[_filterCategory];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Category tabs ──
        SizedBox(
          height: 32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filterCategoryLabels.length,
            itemBuilder: (context, catIdx) {
              final sel = catIdx == _filterCategory;
              final cc = _filterCategoryColors[catIdx];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _filterCategory = catIdx);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: sel
                        ? LinearGradient(
                            colors: [cc[0], cc[1]],
                          )
                        : null,
                    color: sel ? null : Colors.white12,
                    border: Border.all(
                      color: sel ? Colors.transparent : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${_filterCategoryEmoji[catIdx]} ${_filterCategoryLabels[catIdx]}',
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // ── Filter portrait cards ──
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filterGroups[_filterCategory].length,
            itemBuilder: (context, idx) {
              final filterIdx = _filterGroups[_filterCategory][idx];
              final f = _filters[filterIdx];
              final selected = filterIdx == _selectedFilterIndex;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedFilterIndex = filterIdx);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  width: 52,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 52,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? catColors[0] : Colors.white24,
                                width: selected ? 2.5 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: catColors[0].withValues(alpha: 0.5),
                                        blurRadius: 14,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: f.filter != null
                                  ? ColorFiltered(
                                      colorFilter: f.filter!,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFFFF6B9D),
                                              Color(0xFF7C3AED),
                                              Color(0xFF1E3A8A),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xFF2D2D2D),
                                            Color(0xFF111111),
                                          ],
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.wb_sunny_outlined,
                                            color: Colors.white60, size: 22),
                                      ),
                                    ),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: catColors[0],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check,
                                    color: Colors.white, size: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.name,
                        style: TextStyle(
                          color: selected ? catColors[0] : Colors.white70,
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Record row ─────────────────────────────────────────────────────────────

  Widget _buildRecordRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Timer label
        SizedBox(
          width: 70,
          child: _isRecording
              ? Text(
                  _recordingProgress,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // Record button
        GestureDetector(
          onTap: _toggleRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isRecording ? 64 : 76,
            height: _isRecording ? 64 : 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 26 : 58,
                height: _isRecording ? 26 : 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF007F),
                  borderRadius: BorderRadius.circular(_isRecording ? 6 : 50),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 70),
      ],
    );
  }

  // ── Sound picker ───────────────────────────────────────────────────────────

  Widget _buildSoundPicker() {
    return GestureDetector(
      onTap: () => setState(() => _showSoundPicker = false),
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {}, // absorb taps inside sheet
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.55,
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note,
                            color: Color(0xFFFF007F), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Trending Sounds',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        // Clear selection
                        if (_selectedSoundName != null)
                          GestureDetector(
                            onTap: () => setState(() {
                              _selectedSoundName = null;
                              _showSoundPicker = false;
                            }),
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Original audio option
                  _buildSoundItem('Original Audio', isOriginal: true),

                  const Divider(color: Colors.white10, height: 1),

                  // Trending list
                  Expanded(
                    child: _loadingSounds
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF007F)))
                        : _sounds.isEmpty
                            ? Center(
                                child: Text(
                                  'No sounds found',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.35)),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: _sounds.length,
                                itemBuilder: (context, index) =>
                                    _buildSoundItem(_sounds[index]),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundItem(String name, {bool isOriginal = false}) {
    final selected = _selectedSoundName == name ||
        (isOriginal && _selectedSoundName == null);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedSoundName = isOriginal ? null : name;
          _showSoundPicker = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF007F).withValues(alpha: 0.1)
              : Colors.transparent,
          border: selected
              ? const Border(
                  left: BorderSide(color: Color(0xFFFF007F), width: 3),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOriginal
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFFFF007F).withValues(alpha: 0.15),
                border: Border.all(
                  color: selected ? const Color(0xFFFF007F) : Colors.white12,
                ),
              ),
              child: Icon(
                isOriginal ? Icons.person : Icons.music_note,
                color: selected ? const Color(0xFFFF007F) : Colors.white54,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: selected ? const Color(0xFFFF007F) : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isOriginal ? 'No background sound' : 'Trending',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: Color(0xFFFF007F), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _FilterDef {
  final String name;
  final ColorFilter? filter;
  const _FilterDef(this.name, this.filter);
}
