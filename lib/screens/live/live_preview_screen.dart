import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:love_vibe_pro/screens/live/live_room_screen.dart';

class LivePreviewScreen extends StatefulWidget {
  final String userId;
  final String? userName;
  final String? userAvatar;

  const LivePreviewScreen({
    super.key,
    required this.userId,
    this.userName,
    this.userAvatar,
  });

  @override
  State<LivePreviewScreen> createState() => _LivePreviewScreenState();
}

class _LivePreviewScreenState extends State<LivePreviewScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isGoingLive = false;
  bool _isFrontCamera = true;
  bool _showEffects = true;

  // Beauty sliders
  double _brightness = 0.5;
  double _warmth = 0.0;

  // Filter preset
  String _selectedFilter = 'normal';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Filter definitions ──────────────────────────────────────────────────
  static const _filters = [
    {'id': 'normal',  'name': 'Normal',  'color': Color(0xFFFFFFFF)},
    {'id': 'bright',  'name': 'Bright',  'color': Color(0xFFFFD700)},
    {'id': 'beauty',  'name': 'Beauty',  'color': Color(0xFFFF69B4)},
    {'id': 'warm',    'name': 'Warm',    'color': Color(0xFFFF6B35)},
    {'id': 'rose',    'name': 'Rose',    'color': Color(0xFFFF4081)},
    {'id': 'cool',    'name': 'Cool',    'color': Color(0xFF00BFFF)},
    {'id': 'vintage', 'name': 'Vintage', 'color': Color(0xFFDEB887)},
    {'id': 'moody',   'name': 'Moody',   'color': Color(0xFF8B008B)},
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _flipCamera() async {
    HapticFeedback.lightImpact();
    try {
      final cameras = await availableCameras();
      if (cameras.length < 2) return;
      final target = _isFrontCamera
          ? cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first)
          : cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.first);
      await _cameraController?.dispose();
      _cameraController = CameraController(target, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
    } catch (e) {
      debugPrint('Flip camera error: $e');
    }
  }

  Future<void> _goLive() async {
    if (_isGoingLive) return;
    setState(() => _isGoingLive = true);
    HapticFeedback.heavyImpact();
    _cameraController?.dispose();
    _cameraController = null;
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRoomScreen(
          userId: widget.userId,
          userName: widget.userName,
          userAvatar: widget.userAvatar,
          viewerCount: 0,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Builds color matrix from filter preset + brightness/warmth sliders
  List<double> _buildColorMatrix() {
    final bright = (_brightness - 0.5) * 60.0;
    final warm   = _warmth * 20.0;

    switch (_selectedFilter) {
      case 'bright':
        return [1.1, 0,   0,   0, bright + 20 + warm,
                0,   1.1, 0,   0, bright + 20,
                0,   0,   1.1, 0, bright + 20 - warm * 0.5,
                0,   0,   0,   1, 0];
      case 'beauty':
        return [1.05, 0,    0,    0, bright + 15 + warm,
                0,    1.05, 0,    0, bright + 15,
                0,    0,    1.0,  0, bright + 5 - warm,
                0,    0,    0,    1, 0];
      case 'warm':
        return [1.2,  0,    0,    0, bright + 15 + warm,
                0,    1.0,  0,    0, bright,
                0,    0,    0.85, 0, bright - 20 - warm,
                0,    0,    0,    1, 0];
      case 'rose':
        return [1.25, 0,    0,    0, bright + 10 + warm,
                0,    0.95, 0,    0, bright - 5,
                0,    0,    0.9,  0, bright - 10,
                0,    0,    0,    1, 0];
      case 'cool':
        return [0.9,  0,    0,    0, bright - 5,
                0,    1.0,  0,    0, bright,
                0,    0,    1.25, 0, bright + 20,
                0,    0,    0,    1, 0];
      case 'vintage':
        // Slightly desaturated + warm tones
        return [0.9,  0.1,  0,    0, bright + 10 + warm,
                0.05, 0.85, 0.1,  0, bright + 5,
                0,    0.05, 0.8,  0, bright - 10,
                0,    0,    0,    1, 0];
      case 'moody':
        // Darken + high contrast
        return [1.1,  0,    0,    0, bright - 15,
                0,    0.95, 0,    0, bright - 20,
                0,    0,    1.1,  0, bright - 5,
                0,    0,    0,    1, 0];
      default: // normal
        return [1, 0, 0, 0, bright + warm,
                0, 1, 0, 0, bright,
                0, 0, 1, 0, bright - warm * 0.5,
                0, 0, 0, 1, 0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera preview (fill screen, maintain aspect ratio) ──
          if (_isCameraReady && _cameraController != null)
            Positioned.fill(
              child: ClipRect(
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_buildColorMatrix()),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      // Swap previewSize dimensions: sensor reports landscape,
                      // we want portrait fill
                      width:  _cameraController!.value.previewSize?.height ?? 1920,
                      height: _cameraController!.value.previewSize?.width  ?? 1080,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0D0D0D),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFF007F)),
                      SizedBox(height: 16),
                      Text('Opening camera…', style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Top / bottom gradient overlay ──
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.50),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.18, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar ──
          Positioned(
            top: topPad + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
                const Spacer(),
                const Text(
                  'Go Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                _iconBtn(Icons.flip_camera_android, _flipCamera),
              ],
            ),
          ),

          // ── Filter presets row ──
          Positioned(
            bottom: _showEffects ? 310 : 200,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _filters.length,
                itemBuilder: (_, i) {
                  final f = _filters[i];
                  final id = f['id'] as String;
                  final selected = _selectedFilter == id;
                  final color = f['color'] as Color;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedFilter = id);
                    },
                    child: Container(
                      width: 58,
                      margin: const EdgeInsets.only(right: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? Colors.white : color.withValues(alpha: 0.5),
                                width: selected ? 3 : 1.5,
                              ),
                              gradient: LinearGradient(
                                colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: selected
                                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            f['name'] as String,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 10,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Beauty sliders panel ──
          if (_showEffects)
            Positioned(
              bottom: 155,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF007F).withValues(alpha: 0.25)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Color(0xFFFF007F), size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Beauty',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _showEffects = false),
                          child: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildSlider(
                      icon: Icons.wb_sunny,
                      label: 'Brightness',
                      value: _brightness,
                      onChanged: (v) => setState(() => _brightness = v),
                      color: const Color(0xFFFFD700),
                    ),
                    const SizedBox(height: 8),
                    _buildSlider(
                      icon: Icons.thermostat,
                      label: 'Warmth',
                      value: _warmth,
                      onChanged: (v) => setState(() => _warmth = v),
                      color: const Color(0xFFFF6B35),
                    ),
                  ],
                ),
              ),
            ),

          // ── Show effects toggle (when hidden) ──
          if (!_showEffects)
            Positioned(
              bottom: 165,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _showEffects = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFFFF007F), size: 15),
                        SizedBox(width: 5),
                        Text('Beauty', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── GO LIVE button ──
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Transform.scale(
                  scale: _isGoingLive ? 0.9 : _pulseAnim.value,
                  child: child,
                ),
                child: GestureDetector(
                  onTap: _isCameraReady ? _goLive : null,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isCameraReady
                          ? const LinearGradient(
                              colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: _isCameraReady ? null : Colors.grey,
                      boxShadow: _isCameraReady
                          ? [
                              BoxShadow(color: const Color(0xFFFF007F).withValues(alpha: 0.5), blurRadius: 25, spreadRadius: 5),
                              BoxShadow(color: const Color(0xFFD946EF).withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 8),
                            ]
                          : null,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(
                      child: _isGoingLive
                          ? const SizedBox(
                              width: 30, height: 30,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_tethering, color: Colors.white, size: 28),
                                SizedBox(height: 2),
                                Text('LIVE',
                                  style: TextStyle(
                                    color: Colors.white, fontSize: 12,
                                    fontWeight: FontWeight.w900, letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );

  Widget _buildSlider({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        SizedBox(
          width: 68,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}
