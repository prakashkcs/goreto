import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gradient_borders/gradient_borders.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  SettingsStore? _settingsStore;
  String _kycStatus = 'not_submitted';
  bool _isLoading = true;

  File? _idFrontImage;
  File? _idBackImage;
  File? _selfieImage;
  File? _livenessVideo;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _settingsStore = await SettingsStore.getInstance();
    
    // Always fetch fresh status from server first
    try {
      final remoteKyc = await ApiService().getKycStatusRemote();
      final freshStatus = remoteKyc.basicStatus;
      
      // Accept any status from server including 'none' (no submission yet)
      final resolvedStatus = (freshStatus == 'none' || freshStatus.isEmpty)
          ? 'not_submitted'
          : (freshStatus == 'approved' ? 'verified' : freshStatus);

      await _settingsStore!.setKycStatus(resolvedStatus);
      if (mounted) {
        setState(() {
          _kycStatus = resolvedStatus;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Fallback to local cache if network fails
      final cachedStatus = await _settingsStore!.getKycStatus();
      if (mounted) {
        setState(() {
          _kycStatus = cachedStatus;
          _isLoading = false;
        });
      }
    }
  }

  // Removed random action generator

  Future<void> _pickIdFront() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image != null) {
      HapticFeedback.mediumImpact();
      setState(() => _idFrontImage = File(image.path));
    }
  }

  Future<void> _pickIdBack() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image != null) {
      HapticFeedback.mediumImpact();
      setState(() => _idBackImage = File(image.path));
    }
  }

  Future<void> _pickSelfie() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1080,
      maxHeight: 1080,
      preferredCameraDevice: CameraDevice.front,
    );
    if (image != null) {
      HapticFeedback.mediumImpact();
      setState(() => _selfieImage = File(image.path));
    }
  }

  Future<void> _captureLivenessVideo() async {
    final bool? shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF22C55E), width: 2),
        ),
        title: const Text(
          'Liveness Instructions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Please shake your head 2 times and blink your eyes while recording.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Record Video',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 8),
      preferredCameraDevice: CameraDevice.front,
    );

    if (video != null) {
      HapticFeedback.mediumImpact();
      setState(() => _livenessVideo = File(video.path));
    }
  }

  Future<void> _submitKyc() async {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty) {
      _showError('Please enter your full name');
      return;
    }
    if (_idFrontImage == null || _idBackImage == null || _selfieImage == null) {
      _showError('Please upload both sides of your ID and a Selfie');
      return;
    }
    if (_livenessVideo == null) {
      _showError('Please record a liveness video');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await ApiService().submitKyc(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        idFront: _idFrontImage!,
        idBack: _idBackImage!,
        selfie: _selfieImage!,
        livenessVideo: _livenessVideo!,
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (success) {
        // Save KYC status as pending locally
        await _settingsStore?.setKycStatus('pending');

        if (mounted) {
          setState(() => _kycStatus = 'pending');
          _showSuccessDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showError(String message) {
    NeonToast.error(context, message);
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF22C55E), width: 2),
        ),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 64),
            SizedBox(height: 16),
            Text(
              'KYC Submitted!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'Your verification documents have been submitted successfully. '
          'We will review your submission and notify you once verified. '
          'This usually takes 1-3 business days.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Got it!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((_) {
      Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: GalacticTheme.laserPink),
            )
          : SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Header
                  SliverToBoxAdapter(child: _buildHeader()),

                  // KYC Status Card
                  SliverToBoxAdapter(child: _buildStatusCard()),

                  // Instructions
                  SliverToBoxAdapter(child: _buildInstructions()),

                  if (_kycStatus != 'verified' && _kycStatus != 'pending') ...[
                    // Personal Info
                    SliverToBoxAdapter(child: _buildPersonalInfoSection()),

                    // ID Upload Section
                    SliverToBoxAdapter(child: _buildIdUploadSection()),

                    // Selfie Section
                    SliverToBoxAdapter(child: _buildSelfieSection()),

                    // Liveness Section
                    SliverToBoxAdapter(child: _buildLivenessSection()),

                    // Submit Button
                    SliverToBoxAdapter(child: _buildSubmitButton()),
                  ],

                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: GalacticTheme.laserPink.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: GalacticTheme.laserPink.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'KYC Verification',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    String statusText;
    Color statusColor;
    IconData statusIcon;
    String statusDesc;

    switch (_kycStatus) {
      case 'verified':
      case 'approved': // Handle both strings since backend might return 'approved'
        statusText = 'Verified';
        statusColor = const Color(0xFF22C55E);
        statusIcon = Icons.verified;
        statusDesc = 'Your identity has been verified successfully.';
        break;
      case 'pending':
        statusText = 'Pending Review';
        statusColor = const Color(0xFFF97316);
        statusIcon = Icons.hourglass_top;
        statusDesc =
            'Your documents are being reviewed. This usually takes 1-3 business days.';
        break;
      case 'rejected':
        statusText = 'Rejected';
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel;
        statusDesc = 'Your verification was rejected. Please submit valid documents and try again.';
        break;
      default:
        statusText = 'Not Submitted';
        statusColor = const Color(0xFFFF007F);
        statusIcon = Icons.error_outline;
        statusDesc = 'Complete the verification below to enable subscriptions.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.2),
            statusColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: statusColor.withValues(alpha: 0.15), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusDesc,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_kycStatus == 'pending') ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showCancelDialog(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF333333)),
                ),
              ),
              child: const Text(
                'Cancel Request',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showCancelDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel Verification?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to cancel your ongoing KYC verification? You will need to submit all documents again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Keep it',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Cancel Request',
              style: TextStyle(color: Color(0xFFFF007F)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _cancelKycRequest();
    }
  }

  Future<void> _cancelKycRequest() async {
    setState(() => _isLoading = true);
    final success = await ApiService().cancelKyc();
    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (success) {
      await _settingsStore?.setKycStatus('unverified');
      if (mounted) {
        setState(() => _kycStatus = 'unverified');
        NeonToast.success(context, 'KYC request cancelled successfully');
      }
    } else {
      if (mounted) {
        NeonToast.error(context, 'Failed to cancel KYC request');
      }
    }
  }

  Widget _buildInstructions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD946EF).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GalacticTheme.laserPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFFD946EF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Instructions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInstructionItem(
            '1. Upload clear photos of your ID card (front and back)',
          ),
          _buildInstructionItem(
            '2. Record a short video following the on-screen action',
          ),
          _buildInstructionItem(
            '3. Submit for review - verification takes 1-3 days',
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdUploadSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: const GradientBoxBorder(
          gradient: LinearGradient(
            colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
          ),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Color(0xFFD946EF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'ID Document',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFFD946EF),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildIdUploadCard(
                        'Front',
                        _idFrontImage,
                        _pickIdFront,
                        const Color(0xFFD946EF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildIdUploadCard(
                        'Back',
                        _idBackImage,
                        _pickIdBack,
                        const Color(0xFF06B6D4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: const GradientBoxBorder(
          gradient: LinearGradient(
            colors: [Color(0xFF22C55E), Color(0xFFD946EF)],
          ),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.face,
                    color: Color(0xFF22C55E),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Your Selfie Pic',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFF22C55E),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildIdUploadCard(
              'Selfie',
              _selfieImage,
              _pickSelfie,
              const Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdUploadCard(
    String label,
    File? image,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: _kycStatus == 'pending' || _kycStatus == 'verified' ? null : onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: image != null ? color : color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: image != null
              ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  image,
                  width: 80,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              Icon(Icons.check_circle, color: color, size: 20),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.add_a_photo, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label == 'Selfie' ? 'Take Selfie' : 'ID $label',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLivenessSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: const GradientBoxBorder(
          gradient: LinearGradient(
            colors: [Color(0xFF22C55E), Color(0xFF06B6D4)],
          ),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.videocam,
                    color: Color(0xFF22C55E),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Liveness Check',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFF22C55E),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Action text removed as requested, replaced with static instruction
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: const Text(
                    'Upload your selfie video for liveness check',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                // Video preview or capture button
                GestureDetector(
                  onTap: _kycStatus == 'pending' || _kycStatus == 'verified'
                      ? null
                      : _captureLivenessVideo,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _livenessVideo != null
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF22C55E).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: _livenessVideo != null
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF22C55E,
                                ).withValues(alpha: 0.2),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: _livenessVideo != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF22C55E),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.videocam,
                                    color: Color(0xFF22C55E),
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF22C55E),
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Video captured',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(
                                        0xFF22C55E,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.videocam,
                                    color: Color(0xFF22C55E),
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Record Video',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to record a 3-5 second video',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit =
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _idFrontImage != null &&
        _idBackImage != null &&
        _selfieImage != null &&
        _livenessVideo != null &&
        (_kycStatus != 'pending' && _kycStatus != 'verified');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ElevatedButton(
        onPressed: canSubmit ? _submitKyc : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22C55E),
          disabledBackgroundColor: const Color(0xFF2A2A2A),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _kycStatus == 'verified' || _kycStatus == 'approved'
              ? 'Already Verified'
              : _kycStatus == 'pending'
              ? 'Under Review'
              : 'Submit for Verification',
          style: TextStyle(
            color:
                canSubmit ||
                    (_kycStatus == 'verified' || _kycStatus == 'pending')
                ? Colors.white
                : Colors.white38,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal Information',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField('First Name', _firstNameController),
          const SizedBox(height: 12),
          _buildTextField('Last Name', _lastNameController),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    bool isReadOnly = _kycStatus == 'pending' || _kycStatus == 'verified';
    return TextField(
      controller: controller,
      readOnly: isReadOnly,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD946EF)),
        ),
      ),
    );
  }
}
