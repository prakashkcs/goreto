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

  // ── Discovery ──
  bool _privacyAllowFindId = true;         // ON by default

  // ── Nearby / Location ──
  bool _privacyNearbyVisible = true;        // ON by default
  bool _privacyNearbyAlert = true;          // ON by default
  bool _privacyShareDistance = false;       // OFF by default

  // ── Communication ──
  bool _subscriberOnlyDm = false;           // OFF by default
  bool _privacyDirectRandomCall = false;    // OFF by default
  bool _privacyAllowDirectCall = false;     // "show name on random call" — OFF by default
  bool _privacyAllowUnknownInbox = true;    // ON by default

  // ── Visibility ──
  bool _privacyShowOnline = true;           // ON by default
  bool _privacyShowLastSeen = true;         // ON by default
  bool _privacyShowProfileViews = true;     // ON by default

  // ── Content ──
  bool _privacyAllowRepost = true;          // ON by default

  // ── Feed Experience (local pref) ──
  bool _feedActionSubscribe = false;
  bool _kycVerified = false;

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
          _applyFromMap(user);
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
    setState(() => _applyFromMap(user));
    _applying = false;
  }

  void _applyFromMap(Map<String, dynamic> user) {
    _privacyAllowFindId    = _asBool(user['privacy_allow_find_id'],    defaultValue: true);
    _privacyNearbyVisible  = _asBool(user['privacy_nearby_visible'],   defaultValue: true);
    _privacyNearbyAlert    = _asBool(user['privacy_nearby_alert'],     defaultValue: true);
    _privacyShareDistance  = _asBool(user['privacy_share_distance'],   defaultValue: false);
    _subscriberOnlyDm      = _asBool(user['subscriber_only_dm'],       defaultValue: false);
    _privacyDirectRandomCall = _asBool(user['privacy_direct_random_call'], defaultValue: false);
    _privacyAllowDirectCall  = _asBool(user['privacy_allow_direct_call'],  defaultValue: false);
    _privacyAllowUnknownInbox = _asBool(user['privacy_allow_unknown_inbox'], defaultValue: true);
    _privacyShowOnline     = _asBool(user['privacy_show_online'],      defaultValue: true);
    _privacyShowLastSeen   = _asBool(user['privacy_show_last_seen'],   defaultValue: true);
    _privacyShowProfileViews = _asBool(user['privacy_show_profile_views'], defaultValue: true);
    _privacyAllowRepost    = _asBool(user['privacy_allow_repost'],     defaultValue: true);
    _cacheDirectCallPref(_privacyAllowDirectCall);
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
    // Helper to avoid repeating the same 5-line pattern for each toggle.
    Widget tog(String key, String label, String subtitle, IconData icon,
        Color color, bool current, bool defaultVal,
        [void Function(bool)? extraEffect]) {
      return _buildToggle(
        icon: icon,
        label: label,
        subtitle: subtitle,
        value: current,
        color: color,
        onChanged: (v) {
          if (_applying) return;
          final old = current;
          setState(() {
            switch (key) {
              case 'privacy_allow_find_id':     _privacyAllowFindId = v;
              case 'privacy_nearby_visible':    _privacyNearbyVisible = v;
              case 'privacy_nearby_alert':      _privacyNearbyAlert = v;
              case 'privacy_share_distance':    _privacyShareDistance = v;
              case 'subscriber_only_dm':        _subscriberOnlyDm = v;
              case 'privacy_direct_random_call':_privacyDirectRandomCall = v;
              case 'privacy_allow_direct_call': _privacyAllowDirectCall = v;
              case 'privacy_allow_unknown_inbox':_privacyAllowUnknownInbox = v;
              case 'privacy_show_online':       _privacyShowOnline = v;
              case 'privacy_show_last_seen':    _privacyShowLastSeen = v;
              case 'privacy_show_profile_views':_privacyShowProfileViews = v;
              case 'privacy_allow_repost':      _privacyAllowRepost = v;
            }
            extraEffect?.call(v);
          });
          _updateSetting(key, v, old, (r) {
            setState(() {
              switch (key) {
                case 'privacy_allow_find_id':     _privacyAllowFindId = r;
                case 'privacy_nearby_visible':    _privacyNearbyVisible = r;
                case 'privacy_nearby_alert':      _privacyNearbyAlert = r;
                case 'privacy_share_distance':    _privacyShareDistance = r;
                case 'subscriber_only_dm':        _subscriberOnlyDm = r;
                case 'privacy_direct_random_call':_privacyDirectRandomCall = r;
                case 'privacy_allow_direct_call': _privacyAllowDirectCall = r;
                case 'privacy_allow_unknown_inbox':_privacyAllowUnknownInbox = r;
                case 'privacy_show_online':       _privacyShowOnline = r;
                case 'privacy_show_last_seen':    _privacyShowLastSeen = r;
                case 'privacy_show_profile_views':_privacyShowProfileViews = r;
                case 'privacy_allow_repost':      _privacyAllowRepost = r;
              }
              extraEffect?.call(r);
            });
          });
        },
      );
    }

    return [
      // ── DISCOVERY ──────────────────────────────────────────────
      _buildSectionHeader('Discovery', Icons.search),
      tog('privacy_allow_find_id',
          'Allow find by ID',
          'ON — people can find your profile by searching your user ID.',
          Icons.fingerprint, const Color(0xFF06B6D4),
          _privacyAllowFindId, true),

      // ── LOCATION & NEARBY ──────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Location & Nearby', Icons.location_on),
      tog('privacy_nearby_visible',
          'Appear in Nearby',
          'ON — your profile appears in the Nearby tab for people around you.',
          Icons.near_me, const Color(0xFF22C55E),
          _privacyNearbyVisible, true),
      tog('privacy_nearby_alert',
          'Nearby alerts as call',
          'ON — someone being nearby triggers a full-screen ringing alert.',
          Icons.notifications_active, const Color(0xFFFF6B9D),
          _privacyNearbyAlert, true),
      tog('privacy_share_distance',
          'Share my distance',
          'OFF — turn ON to let others see exactly how far you are from them.',
          Icons.social_distance, const Color(0xFF84CC16),
          _privacyShareDistance, false),

      // ── COMMUNICATION ──────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Communication', Icons.chat_bubble_outline),
      tog('subscriber_only_dm',
          'Subscriber-only messages',
          'OFF — turn ON so only your subscribers can send you messages.',
          Icons.lock_outline, const Color(0xFFFF007F),
          _subscriberOnlyDm, false),
      tog('privacy_direct_random_call',
          'Direct random video calls',
          'OFF — turn ON so random matches connect straight to video without a confirm step.',
          Icons.videocam_outlined, const Color(0xFF00E5FF),
          _privacyDirectRandomCall, false),
      tog('privacy_allow_direct_call',
          'Show name on random video call',
          'OFF — turn ON to show your name during random video calls (otherwise shown as Stranger).',
          Icons.badge_outlined, const Color(0xFF8B5CF6),
          _privacyAllowDirectCall, false,
          (r) => _cacheDirectCallPref(r)),
      tog('privacy_allow_unknown_inbox',
          'Allow messages from strangers',
          'ON — people who don\'t follow you can still send you a message request.',
          Icons.message_outlined, const Color(0xFF22C55E),
          _privacyAllowUnknownInbox, true),

      // ── VISIBILITY ─────────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Visibility', Icons.visibility),
      tog('privacy_show_online',
          'Show online status',
          'ON — others see a green dot or "Online" label when you\'re active.',
          Icons.circle, const Color(0xFF10B981),
          _privacyShowOnline, true),
      tog('privacy_show_last_seen',
          'Show last seen',
          'ON — others see when you were last active in the app.',
          Icons.access_time, const Color(0xFF6366F1),
          _privacyShowLastSeen, true),
      tog('privacy_show_profile_views',
          'Show profile views',
          'ON — track who visited your profile and let them know you can see it.',
          Icons.bar_chart, const Color(0xFFEC4899),
          _privacyShowProfileViews, true),
      if (_privacyShowProfileViews)
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileViewersScreen())),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.remove_red_eye_outlined, color: Color(0xFFEC4899), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text('See who viewed your profile',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),

      // ── CONTENT ────────────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Content', Icons.photo_library_outlined),
      tog('privacy_allow_repost',
          'Allow reposts of my content',
          'ON — others can repost or share your posts and reels. Turn OFF to block reposts.',
          Icons.repeat, const Color(0xFFD946EF),
          _privacyAllowRepost, true),

      // ── FEED EXPERIENCE ────────────────────────────────────────
      const SizedBox(height: 20),
      _buildSectionHeader('Feed Experience', Icons.dynamic_feed_outlined),
      _buildToggleWithLock(
        icon: Icons.star_outline_rounded,
        label: 'Show Subscribe button on posts',
        subtitle: _kycVerified
            ? 'ON — posts show a Subscribe button. Requires an active subscription plan to be useful.'
            : 'KYC verification required to enable Subscribe button on your posts.',
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
