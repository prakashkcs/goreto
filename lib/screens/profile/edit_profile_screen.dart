import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/config/app_env.dart';

/// Full screen profile editor
class EditProfileScreen extends StatefulWidget {
  final UserProfile currentProfile;
  final Function(UserProfile) onSave;

  const EditProfileScreen({
    super.key,
    required this.currentProfile,
    required this.onSave,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _locationCtrl;

  // Socials
  late TextEditingController _fbCtrl;
  late TextEditingController _igCtrl;
  late TextEditingController _ytCtrl;
  late TextEditingController _xCtrl;

  // Match Profile Extensions
  late TextEditingController _ageCtrl;
  late TextEditingController _incomeCtrl;
  String _gender = 'male';
  bool _isMatchVisible = true;
  bool _fetchingLocation = false;

  final Set<String> _selectedLookingFor = {};
  final Set<String> _selectedInterests = {};
  final Set<String> _selectedQualities = {};
  final List<File?> _bankStatements = [null, null, null];
  String _incomeStatus = 'none';

  static const _kDefaultInterests = [
    'Music 🎵',
    'Travel âœˆï¸',
    'Art 🎨',
    'Gaming 🎮',
    'Fitness 💪',
    'Movies 🎬',
    'Cooking 🍳',
    'Photography 📸',
    'Books 📚',
    'Dance 💃',
    'Nature 🌿',
    'Tech 💻',
    'Fashion 👗',
    'Sports ⚽',
    'Yoga 🧘',
  ];
  static const _kDefaultQualities = [
    'Caring 💝',
    'Funny 😄',
    'Ambitious 🚀',
    'Creative 🎨',
    'Honest 🤝',
    'Adventurous 🏔️',
    'Intellectual 🧠',
    'Kind 😇',
    'Loyal 🛡️',
    'Optimistic ☀️',
    'Confident 💎',
    'Humble 🙏',
    'Passionate 🔥',
    'Romantic 🌹',
    'Spontaneous ⚡',
  ];
  static const _kLookingForOptions = [
    'Serious Relationship 💍',
    'Casual Dating 🌙',
    'Friendship 🤝',
    'Travel Partner ✈️',
    'Study Buddy 📚',
    'Gym Partner 💪',
    'Adventure Buddy 🏔️',
    'Creative Collab 🎨',
    'Gaming Partner 🎮',
    'Coffee Dates â˜•',
    'Movie Nights 🎬',
    'Deep Talks 🧠',
  ];

  File? _newProfilePic;
  File? _coverFile;
  String _coverUrl = '';
  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentProfile.name);
    _usernameCtrl = TextEditingController(text: widget.currentProfile.username);
    _bioCtrl = TextEditingController(text: widget.currentProfile.bio);
    _locationCtrl = TextEditingController(text: widget.currentProfile.location);

    final links = widget.currentProfile.socialLinks;
    _fbCtrl = TextEditingController(text: links['facebook']);
    _igCtrl = TextEditingController(text: links['instagram']);
    _ytCtrl = TextEditingController(text: links['youtube']);
    _xCtrl = TextEditingController(text: links['x']);

    _coverUrl = widget.currentProfile.cover.isNotEmpty
        ? widget.currentProfile.cover
        : widget.currentProfile.coverPicUrl;

    // Normalize cover URL if it's a relative path
    if (_coverUrl.isNotEmpty && !_coverUrl.startsWith('http')) {
      AppEnv.getBaseUrlAsync().then((baseUrl) {
        if (mounted) {
          final root = baseUrl.replaceAll('/api/v1', '');
          setState(() {
            _coverUrl = _coverUrl.startsWith('/')
                ? '$root$_coverUrl'
                : '$root/$_coverUrl';
          });
        }
      });
    }

    _ageCtrl = TextEditingController();
    _incomeCtrl = TextEditingController();

    _loadMatchProfileStatus();
  }

  Future<void> _loadMatchProfileStatus() async {
    try {
      final data = await ApiService().getMyMatchProfile();
      if (mounted) {
        if (data['profile'] != null) {
          final p = data['profile'];
          _ageCtrl.text = (p['age'] ?? '').toString();
          _incomeCtrl.text = (p['income'] ?? '').toString();
          _gender = p['gender'] ?? 'male';
          _incomeStatus = p['income_status'] ?? 'none';
          _isMatchVisible = (p['is_visible']?.toString() ?? '1') != '0';

          if (p['looking_for'] != null) {
            final val = p['looking_for'];
            if (val is List) {
              _selectedLookingFor.addAll(
                val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
              );
            } else if (val is String && val.isNotEmpty) {
              _selectedLookingFor.addAll(
                val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
              );
            }
          }
          if (p['interests'] != null) {
            final val = p['interests'];
            if (val is List) {
              _selectedInterests.addAll(
                val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
              );
            } else if (val is String && val.isNotEmpty) {
              _selectedInterests.addAll(
                val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
              );
            }
          }
          if (p['qualities'] != null) {
            final val = p['qualities'];
            if (val is List) {
              _selectedQualities.addAll(
                val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
              );
            } else if (val is String && val.isNotEmpty) {
              _selectedQualities.addAll(
                val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
              );
            }
          }
        }
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _fbCtrl.dispose();
    _igCtrl.dispose();
    _ytCtrl.dispose();
    _xCtrl.dispose();
    _ageCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoFetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _fetchingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final city = p.locality ?? p.subAdministrativeArea ?? '';
        final country = p.country ?? '';
        final loc = [city, country].where((s) => s.isNotEmpty).join(', ');
        setState(() {
          _locationCtrl.text = loc;
        });
        NeonToast.success(context, 'Location detected: $loc');
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Location detection failed: $e');
    }
    if (mounted) setState(() => _fetchingLocation = false);
  }

  Future<void> _pickBankStatement(int index) async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (f != null && mounted) {
      setState(() => _bankStatements[index] = File(f.path));
    }
  }

  Future<void> _cancelIncomeReview() async {
    final userId = await ApiService().getCurrentUserId();
    if (userId.isEmpty) return;

    NeonToast.show(context, 'Cancelling review...', type: NeonToastType.info);

    await ApiService().cancelIncomeReview(userId: userId);

    if (mounted) {
      setState(() {
        _incomeStatus = 'none';
        _bankStatements.fillRange(0, 3, null);
      });
      NeonToast.success(
        context,
        'Income review cancelled. You can now edit and resubmit.',
      );
    }
  }

  Future<void> _pickImage(bool isCover, ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 90);
    if (pickedFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: isCover
          ? const CropAspectRatio(ratioX: 16, ratioY: 9)
          : const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: isCover ? 'Crop Cover Photo' : 'Crop Profile Photo',
          toolbarColor: const Color(0xFF0D0B14),
          toolbarWidgetColor: Colors.white,
          backgroundColor: const Color(0xFF0D0B14),
          activeControlsWidgetColor: const Color(0xFFFF007F),
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: isCover ? 'Crop Cover Photo' : 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    if (croppedFile == null) return;

    setState(() {
      if (isCover) {
        _coverFile = File(croppedFile.path);
      } else {
        _newProfilePic = File(croppedFile.path);
      }
    });
  }

  Future<void> _showImageSourcePicker(bool isCover) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(isCover, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(isCover, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;

    // Validate match profile selections only if user has started selecting items
    bool matchProfileValid = true;
    if (_selectedLookingFor.isNotEmpty &&
        (_selectedLookingFor.length < 3 || _selectedLookingFor.length > 5)) {
      NeonToast.error(context, 'Please select 3 to 5 items for "Looking For".');
      matchProfileValid = false;
    }
    if (_selectedInterests.isNotEmpty &&
        (_selectedInterests.length < 3 || _selectedInterests.length > 5)) {
      NeonToast.error(context, 'Please select 3 to 5 items for "Interests".');
      matchProfileValid = false;
    }
    if (_selectedQualities.isNotEmpty &&
        (_selectedQualities.length < 3 || _selectedQualities.length > 5)) {
      NeonToast.error(context, 'Please select 3 to 5 items for "Qualities".');
      matchProfileValid = false;
    }

    setState(() => _isSaving = true);
    try {
      final service = ProfileService.instance;
      String? pUrl;
      String? cUrl;

      if (_newProfilePic != null) {
        pUrl = await service.uploadAvatar(_newProfilePic!);
        if (pUrl != null && pUrl.isNotEmpty) {
          setState(() => _newProfilePic = null);
          final cached = await service.getCachedProfile();
          if (cached != null) {
            await service.cacheProfile(
              cached.copyWith(avatar: pUrl, profilePicUrl: pUrl),
            );
          }
        }
      }

      if (_coverFile != null) {
        cUrl = await service.uploadCover(_coverFile!);
        if (cUrl != null && cUrl.isNotEmpty) {
          setState(() {
            _coverUrl = cUrl!;
            _coverFile = null;
          });
          final cached = await service.getCachedProfile();
          if (cached != null) {
            await service.cacheProfile(
              cached.copyWith(cover: cUrl, coverPicUrl: cUrl),
            );
          }
        }
      }

      final socialLinks = {
        'facebook': _fbCtrl.text.trim(),
        'instagram': _igCtrl.text.trim(),
        'youtube': _ytCtrl.text.trim(),
        'x': _xCtrl.text.trim(),
      };
      socialLinks.removeWhere((_, v) => v.isEmpty);

      await service.updateProfile(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        avatar: pUrl,
        cover: cUrl,
        socialLinks: socialLinks,
      );

      // Refresh latest backend profile
      final updated = await service.getMyProfile(forceRefresh: true);

      // Update match profile silently (only if selections are valid)
      if (matchProfileValid) {
        try {
          await ApiService().saveMatchProfile(
            interests: _selectedInterests.toList(),
            qualities: _selectedQualities.toList(),
            lookingFor: _selectedLookingFor.toList(),
            age: _ageCtrl.text.trim(),
            location: _locationCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            gender: _gender,
            income: _incomeCtrl.text.trim(),
            isVisible: _isMatchVisible,
            incomeProofs: _bankStatements,
          );
        } catch (e) {}
      }

      if (mounted) {
        widget.onSave(updated);
        Navigator.pop(context, true);
        NeonToast.success(context, 'Profile updated successfully!');
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatarUrl = widget.currentProfile.avatar.isNotEmpty
        ? widget.currentProfile.avatar
        : widget.currentProfile.profilePicUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Edit Profile'),
        actions: [
          IconButton(
            onPressed: _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF007F),
                    ),
                  )
                : const Icon(Icons.check, color: Color(0xFFFF007F)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Images Section
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Cover — 9:16 portrait ratio
                GestureDetector(
                  onTap: () => _showImageSourcePicker(true),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox.expand(
                              child: _coverFile != null
                                  ? Image.file(_coverFile!, fit: BoxFit.cover)
                                  : _coverUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _coverUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              const SizedBox.shrink(),
                                        )
                                      : Container(
                                          color: Colors.black.withValues(alpha: 0.18),
                                          child: const Center(
                                            child: Icon(
                                              Icons.image_outlined,
                                              color: Colors.white54,
                                              size: 44,
                                            ),
                                          ),
                                        ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFFF007F).withValues(alpha: 0.7),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Avatar overlapping at center-bottom of cover
                Positioned(
                  bottom: -50,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: GestureDetector(
                        onTap: () => _showImageSourcePicker(false),
                        child: Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF121212),
                                  width: 4,
                                ),
                                color: Colors.grey[800],
                                image: _newProfilePic != null
                                    ? DecorationImage(
                                        image: FileImage(_newProfilePic!),
                                        fit: BoxFit.cover,
                                      )
                                    : (currentAvatarUrl.isNotEmpty
                                        ? DecorationImage(
                                            image: currentAvatarUrl.startsWith(
                                              'http',
                                            )
                                                ? CachedNetworkImageProvider(
                                                    currentAvatarUrl,
                                                  )
                                                : FileImage(
                                                    File(
                                                      currentAvatarUrl,
                                                    ),
                                                  ) as ImageProvider,
                                            fit: BoxFit.cover,
                                          )
                                        : null),
                              ),
                              child: currentAvatarUrl.isEmpty &&
                                      _newProfilePic == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 50,
                                      color: Colors.white54,
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF007F),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 60),

            _buildTextField('Name', _nameCtrl),
            const SizedBox(height: 16),
            _buildTextField('Username', _usernameCtrl),
            const SizedBox(height: 16),
            _buildTextField('Bio', _bioCtrl, maxLines: 3),
            const SizedBox(height: 16),
            _buildTextField(
              'Location',
              _locationCtrl,
              icon: Icons.location_on,
              readOnly: true,
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _fetchingLocation ? null : _autoFetchLocation,
                icon: _fetchingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
                label: const Text('Auto-Detect Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
            _buildMatchProfileSection(),
            const SizedBox(height: 40),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Social Links',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField('Facebook', _fbCtrl, icon: Icons.facebook),
            const SizedBox(height: 10),
            _buildTextField('Instagram', _igCtrl, icon: Icons.camera_alt),
            const SizedBox(height: 10),
            _buildTextField('YouTube', _ytCtrl, icon: Icons.play_arrow),
            const SizedBox(height: 10),
            _buildTextField('X (Twitter)', _xCtrl, icon: Icons.close),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchProfileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Match Profile',
            style: TextStyle(
              color: Color(0xFFFF007F),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isMatchVisible
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                  : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isMatchVisible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color:
                    _isMatchVisible ? const Color(0xFF00E5FF) : Colors.white30,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Profile on Match',
                      style: TextStyle(
                        color: _isMatchVisible ? Colors.white : Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isMatchVisible
                          ? 'Others can discover your profile'
                          : 'Your profile is hidden',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isMatchVisible,
                onChanged: (v) => setState(() => _isMatchVisible = v),
                activeThumbColor: const Color(0xFF00E5FF),
                activeTrackColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                inactiveThumbColor: Colors.white30,
                inactiveTrackColor: Colors.white12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField('Age', _ageCtrl, icon: Icons.cake),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = 'male'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _gender == 'male'
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.8)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '♂️ Male',
                      style: TextStyle(
                        color:
                            _gender == 'male' ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = 'female'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _gender == 'female'
                          ? const Color(0xFFFF007F).withValues(alpha: 0.8)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '♀️ Female',
                      style: TextStyle(
                        color:
                            _gender == 'female' ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Monthly Income (Optional)',
          _incomeCtrl,
          icon: Icons.account_balance_wallet,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        if (_incomeStatus == 'verified' || _incomeStatus == 'approved')
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 4),
            child: Row(
              children: [
                Icon(Icons.verified, color: Color(0xFF00E5FF), size: 14),
                SizedBox(width: 4),
                Text(
                  'Verified Income (Updating will require re-verification)',
                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                ),
              ],
            ),
          )
        else if (_incomeStatus.isNotEmpty && _incomeStatus != 'none')
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _incomeStatus == 'pending'
                      ? 'Verification pending...'
                      : 'Needs verification',
                  style: TextStyle(
                    color: _incomeStatus == 'pending'
                        ? const Color(0xFFFFD700)
                        : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                if (_incomeStatus == 'pending')
                  TextButton(
                    onPressed: _cancelIncomeReview,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Cancel & Edit',
                      style: TextStyle(color: Color(0xFFFF007F), fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Upload 3 months bank statement (Optional)',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(3, (index) {
            return Expanded(
              child: GestureDetector(
                onTap: () => _pickBankStatement(index),
                child: Container(
                  height: 80,
                  margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _bankStatements[index] != null
                          ? const Color(0xFFFF007F)
                          : Colors.white12,
                    ),
                    image: _bankStatements[index] != null
                        ? DecorationImage(
                            image: FileImage(_bankStatements[index]!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _bankStatements[index] == null
                      ? const Center(
                          child: Icon(
                            Icons.add_photo_alternate,
                            color: Colors.white30,
                          ),
                        )
                      : null,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        _buildChipSection(
          'Looking For',
          _kLookingForOptions,
          _selectedLookingFor,
          max: 3,
        ),
        _buildChipSection('Interests', _kDefaultInterests, _selectedInterests),
        _buildChipSection('Qualities', _kDefaultQualities, _selectedQualities),
      ],
    );
  }

  Widget _buildChipSection(
    String title,
    List<String> options,
    Set<String> selectedSet, {
    int max = 15,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: options.map((item) {
            final isSelected = selectedSet.contains(item);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selectedSet.remove(item);
                  } else {
                    if (selectedSet.length < 5) {
                      selectedSet.add(item);
                    } else {
                      if (mounted) {
                        NeonToast.show(
                          context,
                          'You can only select up to 5 options.',
                          type: NeonToastType.error,
                        );
                      }
                    }
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                        : Colors.white12,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    color:
                        isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    IconData? icon,
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: readOnly
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon:
            icon != null ? Icon(icon, color: Colors.white54, size: 20) : null,
      ),
    );
  }
}
