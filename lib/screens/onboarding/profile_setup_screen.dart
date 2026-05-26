// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/onboarding/privacy_setup_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  const ProfileSetupScreen({super.key, this.onComplete});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  File? _avatarFile;
  File? _coverFile;
  String _gender = 'male';
  bool _showOnMatch = true;
  bool _fetchingLocation = false;
  bool _saving = false;

  final _picker = ImagePicker();
  final _api = ApiService();

  // Enter animation
  late final AnimationController _enterCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _pink = Color(0xFFD946EF);
  static const _purple = Color(0xFF9B5DE5);
  static const _cyan = Color(0xFF06B6D4);
  static const _bg = Color(0xFF07050F);
  static const _card = Color(0xFF13101A);

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _ageCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  // ── Photo permission ──────────────────────────────────────────────────────

  Future<bool> _requestPhotoPermission() async {
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied && mounted) {
      NeonToast.error(context,
          'Photo access denied. Enable it in Settings → App Permissions.');
      await openAppSettings();
    }
    return false;
  }

  Future<void> _pickAvatar() async {
    if (!await _requestPhotoPermission()) return;
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (xf != null && mounted) setState(() => _avatarFile = File(xf.path));
  }

  Future<void> _pickCover() async {
    if (!await _requestPhotoPermission()) return;
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (xf != null && mounted) setState(() => _coverFile = File(xf.path));
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) NeonToast.error(context, 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty && mounted) {
        final p = marks.first;
        final parts = [p.locality, p.administrativeArea, p.country]
            .where((s) => s != null && s.isNotEmpty)
            .toList();
        _locationCtrl.text = parts.join(', ');
      }
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Could not get location');
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      String? avatarUrl;
      if (_avatarFile != null) {
        try { avatarUrl = await ProfileService.instance.uploadAvatar(_avatarFile!); } catch (_) {}
      }
      String? coverUrl;
      if (_coverFile != null) {
        try { coverUrl = await ProfileService.instance.uploadCover(_coverFile!); } catch (_) {}
      }
      final fields = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'gender': _gender,
        'location': _locationCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()) ?? 0,
        'is_match_visible': _showOnMatch ? 1 : 0,
      };
      if (avatarUrl != null) fields['profile_pic'] = avatarUrl;
      if (coverUrl != null) fields['cover_photo'] = coverUrl;
      await _api.updateProfileFields(fields);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PrivacySetupScreen(onComplete: widget.onComplete),
      ));
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Could not save profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    final hPad = isTablet ? size.width * 0.1 : 20.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cover photo (INSIDE scroll so taps work) ──────────
                  _buildCoverArea(),

                  // ── Avatar + step indicator ───────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildAvatarPicker(),
                        const Spacer(),
                        _buildStepIndicator(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Title ─────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set up your profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You can always change this later in settings.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Name & Username ───────────────────────────────────
                  _buildCard(hPad: hPad, children: [
                    _setupField(
                      controller: _nameCtrl,
                      label: 'Full Name',
                      hint: 'Your display name',
                      icon: Icons.person_outline_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _setupField(
                      controller: _usernameCtrl,
                      label: 'Username',
                      hint: 'e.g. john_doe',
                      icon: Icons.alternate_email_rounded,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(v.trim())) {
                          return '3–20 chars, letters/numbers/_';
                        }
                        return null;
                      },
                    ),
                  ]),

                  const SizedBox(height: 12),

                  // ── Gender ────────────────────────────────────────────
                  _buildCard(hPad: hPad, children: [
                    _sectionLabel('Gender'),
                    const SizedBox(height: 10),
                    Row(children: [
                      _genderChip('male', '♂ Male'),
                      const SizedBox(width: 10),
                      _genderChip('female', '♀ Female'),
                      const SizedBox(width: 10),
                      _genderChip('other', '⚧ Other'),
                    ]),
                  ]),

                  const SizedBox(height: 12),

                  // ── Age & Location ────────────────────────────────────
                  _buildCard(hPad: hPad, children: [
                    _setupField(
                      controller: _ageCtrl,
                      label: 'Age',
                      hint: 'Your age',
                      icon: Icons.cake_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 13 || n > 100) return 'Enter a valid age (13–100)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildLocationTile(),
                  ]),

                  const SizedBox(height: 12),

                  // ── Show in Match toggle ──────────────────────────────
                  _buildCard(hPad: hPad, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: _pink.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_outline,
                            color: _pink, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Show profile in Match',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            Text('Let others discover you in the Match tab',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      _neonSwitch(_showOnMatch, (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _showOnMatch = v);
                      }),
                    ]),
                  ]),

                  const SizedBox(height: 32),

                  // ── Continue button ───────────────────────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: _ContinueButton(
                      isLoading: _saving,
                      onTap: _continue,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Skip ──────────────────────────────────────────────
                  Center(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => PrivacySetupScreen(
                                      onComplete: widget.onComplete),
                                ),
                              ),
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Cover photo — INSIDE scroll content so GestureDetector works ──────────

  Widget _buildCoverArea() {
    return GestureDetector(
      onTap: _pickCover,
      child: Stack(
        children: [
          // Cover image or gradient placeholder
          SizedBox(
            height: 220,
            width: double.infinity,
            child: _coverFile != null
                ? Image.file(_coverFile!, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1A0A2E),
                          Color(0xFF16063A),
                          Color(0xFF0D1B3E),
                        ],
                      ),
                    ),
                    child: CustomPaint(painter: _CoverPatternPainter()),
                  ),
          ),
          // Bottom fade
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: 90,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, _bg],
                ),
              ),
            ),
          ),
          // Safe area top padding
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top,
              color: Colors.transparent,
            ),
          ),
          // Cover badge
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _coverFile != null
                        ? Icons.edit_outlined
                        : Icons.add_photo_alternate_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _coverFile != null ? 'Change cover' : 'Add cover photo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar picker (overlaps bottom of cover) ──────────────────────────────

  Widget _buildAvatarPicker() {
    return Transform.translate(
      offset: const Offset(0, -28),
      child: GestureDetector(
        onTap: _pickAvatar,
        child: Stack(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _bg, width: 4),
                color: const Color(0xFF1E1830),
              ),
              child: ClipOval(
                child: _avatarFile != null
                    ? Image.file(_avatarFile!, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFF1E1830),
                        child: Icon(Icons.person_rounded,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 48),
                      ),
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_pink, _purple]),
                  shape: BoxShape.circle,
                  border: Border.all(color: _bg, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step indicator ────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('Step 1 of 2',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          const SizedBox(width: 10),
          _stepDot(active: true),
          const SizedBox(width: 5),
          _stepDot(active: false),
        ],
      ),
    );
  }

  // ── Location tile ─────────────────────────────────────────────────────────

  Widget _buildLocationTile() {
    final has = _locationCtrl.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Location'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _fetchingLocation ? null : _fetchLocation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: has
                    ? _cyan.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.1),
                width: has ? 1.5 : 1.0,
              ),
              boxShadow: has
                  ? [BoxShadow(
                      color: _cyan.withValues(alpha: 0.12),
                      blurRadius: 12)]
                  : [],
            ),
            child: Row(children: [
              Icon(Icons.location_on_outlined,
                  color: has ? _cyan : _pink.withValues(alpha: 0.7), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  has ? _locationCtrl.text : 'Tap to detect your location',
                  style: TextStyle(
                    color: has
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                    fontSize: 15,
                  ),
                ),
              ),
              if (_fetchingLocation)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
                )
              else
                Icon(has ? Icons.refresh_rounded : Icons.my_location_rounded,
                    color: _cyan, size: 20),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────

  Widget _buildCard({required double hPad, required List<Widget> children}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: hPad),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // ── Text field ────────────────────────────────────────────────────────────

  Widget _setupField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          // ── Explicit white text + cursor (fixes "black text" on dark bg) ──
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
          cursorColor: _pink,
          cursorWidth: 1.8,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.28), fontSize: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(icon,
                  color: _pink.withValues(alpha: 0.85), size: 20),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _pink, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
            ),
            errorStyle:
                const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 15),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );

  Widget _genderChip(String value, String label) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _gender = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [_pink.withValues(alpha: 0.25),
                             _purple.withValues(alpha: 0.15)])
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _pink : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _pink : Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepDot({required bool active}) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 22 : 7,
        height: 7,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(colors: [_pink, _purple])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _neonSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: value
              ? const LinearGradient(colors: [_pink, _purple])
              : null,
          color: value ? null : const Color(0xFF2A2A3A),
          border: Border.all(
            color: value ? _pink : Colors.white.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: value
              ? [BoxShadow(color: _pink.withValues(alpha: 0.45), blurRadius: 10)]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22, height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: value
                  ? [BoxShadow(color: _pink.withValues(alpha: 0.4), blurRadius: 4)]
                  : [],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Continue button ────────────────────────────────────────────────────────────

class _ContinueButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _ContinueButton({required this.isLoading, required this.onTap});

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); if (!widget.isLoading) widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD946EF), Color(0xFF9B5DE5)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text(
                    'Continue →',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Decorative pattern painter for empty cover ────────────────────────────────

class _CoverPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Subtle diagonal grid lines
    for (double i = -size.height; i < size.width + size.height; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }

    // Glowing orb hint
    final orbPaint = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFD946EF).withValues(alpha: 0.15),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.3, size.height * 0.4),
          radius: size.width * 0.4));
    canvas.drawCircle(
        Offset(size.width * 0.3, size.height * 0.4), size.width * 0.4, orbPaint);

    final orb2Paint = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF9B5DE5).withValues(alpha: 0.12),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.75, size.height * 0.6),
          radius: size.width * 0.35));
    canvas.drawCircle(
        Offset(size.width * 0.75, size.height * 0.6), size.width * 0.35, orb2Paint);
  }

  @override
  bool shouldRepaint(_CoverPatternPainter _) => false;
}
