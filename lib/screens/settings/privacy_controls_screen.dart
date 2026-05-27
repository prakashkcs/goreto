import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/settings/kyc_screen.dart';
import 'package:love_vibe_pro/screens/profile/profile_viewers_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyControlsScreen extends StatefulWidget {
  const PrivacyControlsScreen({super.key});

  @override
  State<PrivacyControlsScreen> createState() => _PrivacyControlsScreenState();
}

class _PrivacyControlsScreenState extends State<PrivacyControlsScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _applying = false;

  // ── Existing toggles ──
  bool _privacyAllowFindId = true;
  bool _privacyAllowDirectCall = true;
  bool _privacyAllowRepost = true;
  bool _privacyAllowUnknownInbox = true;

  // ── Feed action preference (local only) ──
  bool _feedActionSubscribe = false;
  bool _kycVerified = false;

  // ── New toggles (default ON) ──
  bool _privacyShowOnline = true;
  bool _privacyShowLastSeen = true;
  bool _privacyShowProfileViews = true;
  bool _privacyShareDistance = true;
  bool _privacyNearbyVisible = true;
  bool _privacyNearbyAlert = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFeedActionPref();
    _loadKycStatus();
  }

  Future<void> _loadFeedActionPref() async {
    final store = await SettingsStore.getInstance();
    final val = await store.getFeedActionSubscribe();
    if (mounted) setState(() => _feedActionSubscribe = val);
  }

  Future<void> _loadKycStatus() async {
    final store = await SettingsStore.getInstance();
    final verified = await store.getKycVerified();
    if (mounted) setState(() => _kycVerified = verified);
  }

  Future<void> _setFeedActionPref(bool value) async {
    if (value && !_kycVerified) {
      _showKycRequiredDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _feedActionSubscribe = value);
    final store = await SettingsStore.getInstance();
    await store.setFeedActionSubscribe(value);
  }

  void _showKycRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: Color(0xFFD946EF)),
            SizedBox(width: 8),
            Text('KYC Required', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'You need to complete KYC verification before enabling the Subscribe button on posts.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD946EF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KycScreen()),
              );
            },
            child: const Text('Verify Now'),
          ),
        ],
      ),
    );
  }

  static bool _asBool(dynamic v, {bool defaultValue = true}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }
    return defaultValue;
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> response) {
    final user = response['user'];
    if (user is Map<String, dynamic>) return user;
    if (user is Map) return Map<String, dynamic>.from(user);
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return response;
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final raw = await _api.getUserPrivacySettings();
      final user = _unwrap(raw);
      if (mounted) {
        _applying = true;
        setState(() {
          _privacyAllowFindId = _asBool(user['privacy_allow_find_id']);
          _privacyAllowDirectCall = _asBool(user['privacy_allow_direct_call']);
          _cacheDirectCallPref(_privacyAllowDirectCall);
          _privacyAllowRepost = _asBool(user['privacy_allow_repost']);
          _privacyAllowUnknownInbox = _asBool(
            user['privacy_allow_unknown_inbox'],
          );
          _privacyShowOnline = _asBool(user['privacy_show_online']);
          _privacyShowLastSeen = _asBool(user['privacy_show_last_seen']);
          _privacyShowProfileViews = _asBool(
            user['privacy_show_profile_views'],
          );
          _privacyShareDistance = _asBool(user['privacy_share_distance']);
          _privacyNearbyVisible = _asBool(user['privacy_nearby_visible']);
          _privacyNearbyAlert =
              _asBool(user['privacy_nearby_alert'], defaultValue: true);
          _isLoading = false;
        });
        _applying = false;
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _applying = false;
    }
  }

  void _applyServerValues(Map<String, dynamic> response) {
    final user = _unwrap(response);
    _applying = true;
    setState(() {
      _privacyAllowFindId = _asBool(user['privacy_allow_find_id']);
      _privacyAllowDirectCall = _asBool(user['privacy_allow_direct_call']);
      _privacyAllowRepost = _asBool(user['privacy_allow_repost']);
      _privacyAllowUnknownInbox = _asBool(user['privacy_allow_unknown_inbox']);
      _privacyShowOnline = _asBool(user['privacy_show_online']);
      _privacyShowLastSeen = _asBool(user['privacy_show_last_seen']);
      _privacyShowProfileViews = _asBool(user['privacy_show_profile_views']);
      _privacyShareDistance = _asBool(user['privacy_share_distance']);
      _privacyNearbyVisible = _asBool(user['privacy_nearby_visible']);
      _privacyNearbyAlert =
          _asBool(user['privacy_nearby_alert'], defaultValue: true);
    });
    _applying = false;
  }

  Future<void> _cacheDirectCallPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_allow_direct_call', value);
  }

  Future<void> _updateSetting(
    String key,
    bool newValue,
    bool oldValue,
    void Function(bool) setter,
  ) async {
    if (_applying) return;
    HapticFeedback.mediumImpact();
    final result = await _api.updateUserPrivacySettings(<String, dynamic>{
      key: newValue,
    });
    if (!mounted) return;
    if (result != null) {
      // Backend returned the fresh settings — apply them directly
      _applyServerValues(result);
    } else {
      setState(() => setter(oldValue));
      NeonToast.error(context, 'Failed to update. Reverted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Privacy Controls',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Color(0xFFD946EF),
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD946EF)),
              )
            : Builder(
                builder: (_) {
                  final items = _buildPrivacyItems();
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (_, i) => items[i],
                  );
                },
              ),
      ),
    );
  }

  List<Widget> _buildPrivacyItems() {
    return [
      // ── DISCOVERY ──────────────────────────────────────────────
      _buildSectionHeader('Discovery', Icons.search),
      _buildToggle(
        icon: Icons.fingerprint,
        label: 'Allow find by ID',
        subtitle: 'Others can find your profile using your ID',
        value: _privacyAllowFindId,
        color: const Color(0xFF06B6D4),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyAllowFindId;
          setState(() => _privacyAllowFindId = v);
          _updateSetting(
            'privacy_allow_find_id',
            v,
            old,
            (r) => _privacyAllowFindId = r,
          );
        },
      ),

      // ── LOCATION & NEARBY ──────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Location & Nearby', Icons.location_on),
      _buildToggle(
        icon: Icons.near_me,
        label: 'Appear in Nearby',
        subtitle: 'Show your profile to people near your location',
        value: _privacyNearbyVisible,
        color: const Color(0xFF22C55E),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyNearbyVisible;
          setState(() => _privacyNearbyVisible = v);
          _updateSetting(
            'privacy_nearby_visible',
            v,
            old,
            (r) => _privacyNearbyVisible = r,
          );
        },
      ),
      _buildToggle(
        icon: Icons.notifications_active,
        label: 'Nearby alerts as call',
        subtitle:
            'Full-screen ringing alert when someone is near you. Turn off to stop receiving these.',
        value: _privacyNearbyAlert,
        color: const Color(0xFFFF6B9D),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyNearbyAlert;
          setState(() => _privacyNearbyAlert = v);
          _updateSetting(
            'privacy_nearby_alert',
            v,
            old,
            (r) => _privacyNearbyAlert = r,
          );
        },
      ),
      _buildToggle(
        icon: Icons.social_distance,
        label: 'Share my distance',
        subtitle: 'Others can see how far you are from them',
        value: _privacyShareDistance,
        color: const Color(0xFF84CC16),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyShareDistance;
          setState(() => _privacyShareDistance = v);
          _updateSetting(
            'privacy_share_distance',
            v,
            old,
            (r) => _privacyShareDistance = r,
          );
        },
      ),

      // ── COMMUNICATION ──────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Communication', Icons.chat_bubble_outline),
      _buildToggle(
        icon: Icons.phone_in_talk,
        label: 'Show name on random video call',
        subtitle: 'When OFF, people from random video who call you appear as "Stranger" until connected',
        value: _privacyAllowDirectCall,
        color: const Color(0xFF8B5CF6),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyAllowDirectCall;
          setState(() => _privacyAllowDirectCall = v);
          _updateSetting(
            'privacy_allow_direct_call',
            v,
            old,
            (r) {
              _privacyAllowDirectCall = r;
              _cacheDirectCallPref(r);
            },
          );
        },
      ),
      _buildToggle(
        icon: Icons.message_outlined,
        label: 'Allow messages from strangers',
        subtitle: 'People who don\'t follow you can send messages',
        value: _privacyAllowUnknownInbox,
        color: const Color(0xFF22C55E),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyAllowUnknownInbox;
          setState(() => _privacyAllowUnknownInbox = v);
          _updateSetting(
            'privacy_allow_unknown_inbox',
            v,
            old,
            (r) => _privacyAllowUnknownInbox = r,
          );
        },
      ),

      // ── VISIBILITY ─────────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Visibility', Icons.visibility),
      _buildToggle(
        icon: Icons.circle,
        label: 'Show online status',
        subtitle: 'Others can see when you\'re active',
        value: _privacyShowOnline,
        color: const Color(0xFF10B981),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyShowOnline;
          setState(() => _privacyShowOnline = v);
          _updateSetting(
            'privacy_show_online',
            v,
            old,
            (r) => _privacyShowOnline = r,
          );
        },
      ),
      _buildToggle(
        icon: Icons.access_time,
        label: 'Show last seen',
        subtitle: 'Others can see when you were last active',
        value: _privacyShowLastSeen,
        color: const Color(0xFF6366F1),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyShowLastSeen;
          setState(() => _privacyShowLastSeen = v);
          _updateSetting(
            'privacy_show_last_seen',
            v,
            old,
            (r) => _privacyShowLastSeen = r,
          );
        },
      ),
      _buildToggle(
        icon: Icons.bar_chart,
        label: 'Show profile views',
        subtitle: 'Track and view who visited your profile',
        value: _privacyShowProfileViews,
        color: const Color(0xFFEC4899),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyShowProfileViews;
          setState(() => _privacyShowProfileViews = v);
          _updateSetting(
            'privacy_show_profile_views',
            v,
            old,
            (r) => _privacyShowProfileViews = r,
          );
        },
      ),
      if (_privacyShowProfileViews)
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ProfileViewersScreen()),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.remove_red_eye_outlined,
                    color: Color(0xFFEC4899), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'See who viewed your profile',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),

      // ── CONTENT ────────────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Content', Icons.photo_library_outlined),
      _buildToggle(
        icon: Icons.repeat,
        label: 'Allow reposts of my content',
        subtitle: 'Others can repost your posts and reels',
        value: _privacyAllowRepost,
        color: const Color(0xFFD946EF),
        onChanged: (v) {
          if (_applying) return;
          final old = _privacyAllowRepost;
          setState(() => _privacyAllowRepost = v);
          _updateSetting(
            'privacy_allow_repost',
            v,
            old,
            (r) => _privacyAllowRepost = r,
          );
        },
      ),

      // ── FEED EXPERIENCE ────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Feed Experience', Icons.dynamic_feed_outlined),
      _buildToggleWithLock(
        icon: Icons.star_outline_rounded,
        label: 'Show Subscribe button on posts',
        subtitle: _kycVerified
            ? 'When ON, posts show a purple "Subscribe" button instead of "Follow"'
            : 'KYC verification required to enable this option',
        value: _feedActionSubscribe,
        color: const Color(0xFFD946EF),
        isLocked: !_kycVerified,
        onChanged: _setFeedActionPref,
      ),
      const SizedBox(height: 40),
    ];
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD946EF), size: 16),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFD946EF),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildToggleWithLock(
      icon: icon,
      label: label,
      subtitle: subtitle,
      value: value,
      color: color,
      isLocked: false,
      onChanged: onChanged,
    );
  }

  Widget _buildToggleWithLock({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color color,
    required bool isLocked,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isLocked ? 0.03 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isLocked ? 0.10 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isLocked ? 0.08 : 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLocked ? Icons.lock_outline : icon,
              color: isLocked ? Colors.white38 : color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isLocked ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isLocked
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isLocked
              ? GestureDetector(
                  onTap: () => onChanged(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD946EF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'KYC',
                      style: TextStyle(
                        color: Color(0xFFD946EF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : _buildNeonSwitch(value, color, onChanged),
        ],
      ),
    );
  }

  Widget _buildNeonSwitch(
    bool value,
    Color color,
    ValueChanged<bool> onChanged,
  ) {
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
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
