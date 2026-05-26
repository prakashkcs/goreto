import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/home_screen.dart';

/// Step 2 of first-time onboarding: privacy settings.
/// All toggles default to OFF (most private) so the user consciously opts in.
class PrivacySetupScreen extends StatefulWidget {
  /// Called after onboarding completes. When null, navigates to HomeScreen.
  final VoidCallback? onComplete;

  const PrivacySetupScreen({super.key, this.onComplete});

  @override
  State<PrivacySetupScreen> createState() => _PrivacySetupScreenState();
}

class _PrivacySetupScreenState extends State<PrivacySetupScreen> {
  // ── All OFF by default ────────────────────────────────────────────────────
  bool _allowFindById = false;
  bool _nearbyVisible = false;
  bool _shareDistance = false;
  bool _showOnline = false;
  bool _showLastSeen = false;
  bool _showProfileViews = false;
  bool _allowRandomVideoCall = false;
  bool _allowDirectCall = false;
  bool _allowUnknownInbox = false;
  bool _allowRepost = false;

  bool _saving = false;

  final _api = ApiService();

  static const _pink = Color(0xFFD946EF);
  static const _bg = Color(0xFF0A0A0A);

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    try {
      await _api.updateUserPrivacySettings({
        'privacy_allow_find_id': _allowFindById,
        'privacy_nearby_visible': _nearbyVisible,
        'privacy_share_distance': _shareDistance,
        'privacy_show_online': _showOnline,
        'privacy_show_last_seen': _showLastSeen,
        'privacy_show_profile_views': _showProfileViews,
        'privacy_allow_random_video_call': _allowRandomVideoCall,
        'privacy_allow_direct_call': _allowDirectCall,
        'privacy_allow_unknown_inbox': _allowUnknownInbox,
        'privacy_allow_repost': _allowRepost,
      });
    } catch (e) {
      // Non-fatal — user can adjust later in settings
      debugPrint('Privacy setup error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    // Mark onboarding complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  _stepDot(active: false),
                  const SizedBox(width: 6),
                  _stepDot(active: true),
                  const Spacer(),
                  Text(
                    'Step 2 of 2',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Privacy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Everything is off by default. Turn on only what you\'re comfortable sharing.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Scrollable toggles ───────────────────────────────────────────
            Expanded(
              child: Builder(
                builder: (context) {
                  final toggleItems = <Widget>[
                    _section('Discovery', Icons.search),
                    _toggle(
                      icon: Icons.fingerprint,
                      label: 'Allow find by ID',
                      subtitle: 'Others can search your profile using your ID',
                      value: _allowFindById,
                      color: const Color(0xFF06B6D4),
                      onChanged: (v) => setState(() => _allowFindById = v),
                    ),

                    _section('Location & Nearby', Icons.location_on_outlined),
                    _toggle(
                      icon: Icons.near_me,
                      label: 'Appear in Nearby',
                      subtitle: 'Show your profile to people near you',
                      value: _nearbyVisible,
                      color: const Color(0xFF22C55E),
                      onChanged: (v) => setState(() => _nearbyVisible = v),
                    ),
                    _toggle(
                      icon: Icons.social_distance,
                      label: 'Share my distance',
                      subtitle: 'Others can see how far you are from them',
                      value: _shareDistance,
                      color: const Color(0xFF84CC16),
                      onChanged: (v) => setState(() => _shareDistance = v),
                    ),

                    _section('Visibility', Icons.visibility_outlined),
                    _toggle(
                      icon: Icons.circle,
                      label: 'Show online status',
                      subtitle: 'Others can see when you\'re active',
                      value: _showOnline,
                      color: const Color(0xFF10B981),
                      onChanged: (v) => setState(() => _showOnline = v),
                    ),
                    _toggle(
                      icon: Icons.access_time,
                      label: 'Show last seen',
                      subtitle: 'Others can see when you were last active',
                      value: _showLastSeen,
                      color: const Color(0xFF6366F1),
                      onChanged: (v) => setState(() => _showLastSeen = v),
                    ),
                    _toggle(
                      icon: Icons.bar_chart,
                      label: 'Show profile views',
                      subtitle: 'Others can see your profile view count',
                      value: _showProfileViews,
                      color: const Color(0xFFEC4899),
                      onChanged: (v) => setState(() => _showProfileViews = v),
                    ),

                    _section('Communication', Icons.chat_bubble_outline),
                    _toggle(
                      icon: Icons.videocam_outlined,
                      label: 'Allow random video calls',
                      subtitle: 'Strangers can start video calls with you',
                      value: _allowRandomVideoCall,
                      color: const Color(0xFFF97316),
                      onChanged: (v) => setState(() => _allowRandomVideoCall = v),
                    ),
                    _toggle(
                      icon: Icons.phone_in_talk,
                      label: 'Allow direct call from random video',
                      subtitle:
                          'Users from random video tab can call you directly',
                      value: _allowDirectCall,
                      color: const Color(0xFF8B5CF6),
                      onChanged: (v) => setState(() => _allowDirectCall = v),
                    ),
                    _toggle(
                      icon: Icons.message_outlined,
                      label: 'Allow messages from strangers',
                      subtitle: 'People who don\'t follow you can message you',
                      value: _allowUnknownInbox,
                      color: const Color(0xFF22C55E),
                      onChanged: (v) => setState(() => _allowUnknownInbox = v),
                    ),

                    _section('Content', Icons.photo_library_outlined),
                    _toggle(
                      icon: Icons.repeat,
                      label: 'Allow reposts of my content',
                      subtitle: 'Others can repost your posts and reels',
                      value: _allowRepost,
                      color: _pink,
                      onChanged: (v) => setState(() => _allowRepost = v),
                    ),

                    const SizedBox(height: 32),

                    // ── Finish button ────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _finish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Start using Goreto 🎉',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Center(
                      child: Text(
                        'You can change these anytime in Settings → Privacy',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 32),
                  ];
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: toggleItems.length,
                    itemBuilder: (context, index) => toggleItems[index],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: _pink, size: 14),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _pink,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _neonSwitch(value, color, (v) {
            HapticFeedback.selectionClick();
            onChanged(v);
          }),
        ],
      ),
    );
  }

  Widget _stepDot({required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? _pink : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _neonSwitch(bool value, Color color, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: value
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.8)])
              : null,
          color: value ? null : const Color(0xFF2A2A2A),
          border: Border.all(color: value ? color : Colors.white24, width: 1.5),
          boxShadow: value
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: value
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5), blurRadius: 4)
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
