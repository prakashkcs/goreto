import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/widgets/login_required_sheet.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/models/match_user.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/utils/formatters.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Global profile preview — used from match swipe, nearby, group chat, etc.
class ProfilePreviewScreen extends StatefulWidget {
  final MatchUser user;

  /// Called after a proposal is sent (or the swipe-right action fires).
  final VoidCallback? onProposal;

  /// Called when the user taps Reject / swipe-left action.
  final VoidCallback? onReject;

  /// If true the proposal button starts in "sent" state.
  final bool proposalSent;

  const ProfilePreviewScreen({
    super.key,
    required this.user,
    this.onProposal,
    this.onReject,
    this.proposalSent = false,
  });

  @override
  State<ProfilePreviewScreen> createState() => _ProfilePreviewScreenState();
}

class _ProfilePreviewScreenState extends State<ProfilePreviewScreen> {
  bool _proposalSent = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _proposalSent = widget.proposalSent;
  }

  // ── Tier helper ──────────────────────────────────────────────────────────
  (Color, String) _tier(double r) {
    if (r >= 9.0) return (const Color(0xFFFF9500), 'Legendary');
    if (r >= 7.5) return (const Color(0xFFBF5AF2), 'Elite');
    if (r >= 6.0) return (const Color(0xFF0A84FF), 'Premium');
    if (r >= 4.5) return (const Color(0xFF30D158), 'Popular');
    if (r >= 3.0) return (const Color(0xFFFF6B9D), 'Rising');
    return (const Color(0xFF8E8E93), 'New');
  }

  // ── Send proposal ─────────────────────────────────────────────────────────
  Future<void> _sendProposal() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated) {
      LoginRequiredSheet.show(context, feature: 'send proposals');
      return;
    }
    if (_proposalSent || _sending) return;
    setState(() => _sending = true);
    try {
      final result =
          await ApiService().sendProposal(targetUserId: widget.user.id);
      if (!mounted) return;
      setState(() {
        _proposalSent = true;
        _sending = false;
      });
      widget.onProposal?.call();
      final matched = result['matched'] == true;
      if (matched) {
        NeonToast.success(context, "It's a Match! 💕");
      } else {
        NeonToast.success(context, 'Proposal sent! 🌹');
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _handleReject() {
    Navigator.pop(context);
    widget.onReject?.call();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final (tierColor, tierLabel) = _tier(user.rating);
    final size = MediaQuery.of(context).size;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      body: Stack(
        children: [
          // ── Full-screen photo (top 62%) ──────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.62,
            child: user.photoUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.photoUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _photoFallback(),
                  )
                : _photoFallback(),
          ),

          // ── Photo → dark gradient ────────────────────────────────────
          Positioned(
            top: size.height * 0.38,
            left: 0,
            right: 0,
            height: size.height * 0.26,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF060610)],
                ),
              ),
            ),
          ),

          // ── Scrollable content ───────────────────────────────────────
          Positioned(
            top: size.height * 0.52,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + age + match%
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.age > 0
                                  ? '${user.name}, ${user.age}'
                                  : user.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            if (user.city.isNotEmpty || user.country.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded,
                                        color: Color(0xFF8E8E93), size: 13),
                                    const SizedBox(width: 3),
                                    Text(
                                      [
                                        if (user.city.isNotEmpty) user.city,
                                        if (user.country.isNotEmpty &&
                                            user.country != 'World')
                                          user.country,
                                      ].join(', '),
                                      style: const TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            if (user.distanceKm != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  children: [
                                    const Icon(Icons.near_me_rounded,
                                        color: Color(0xFF30D158), size: 13),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${Formatters.formatDistance(user.distanceKm)} away',
                                      style: const TextStyle(
                                          color: Color(0xFF30D158),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      _pill(
                        '${user.matchPercent}%',
                        Icons.bolt_rounded,
                        const Color(0xFF00E5FF),
                        subtitle: 'Match',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Stats row
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _statChip(tierColor, Icons.auto_awesome_rounded,
                          tierLabel, user.rating.toStringAsFixed(1)),
                      if (user.gender.isNotEmpty)
                        _statChip(
                          const Color(0xFFFF6B9D),
                          user.gender.toLowerCase() == 'male'
                              ? Icons.male_rounded
                              : Icons.female_rounded,
                          'Gender',
                          user.gender[0].toUpperCase() +
                              user.gender.substring(1),
                        ),
                      if (user.isOnline)
                        _statChip(const Color(0xFF30D158), Icons.circle,
                            'Status', 'Online'),
                      if (user.incomeStatus == 'verified')
                        _statChip(const Color(0xFF00E5FF), Icons.verified,
                            'Income', 'Verified'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Interests
                  if (user.interests.isNotEmpty) ...[
                    _sectionLabel('Interests'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: user.interests
                          .map((i) => _tag(i, const Color(0xFFFF6B9D)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Looking For
                  if (user.lookingFor.isNotEmpty) ...[
                    _sectionLabel('Looking For'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: user.lookingFor
                          .map((l) => _tag(l, const Color(0xFF00E5FF)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Qualities
                  if (user.qualities.isNotEmpty) ...[
                    _sectionLabel('Qualities'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: user.qualities
                          .map((q) => _tag(q, const Color(0xFFBF5AF2)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Social links
                  if (user.socialLinks.isNotEmpty) ...[
                    _sectionLabel('Social'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: user.socialLinks.entries
                          .where((e) => e.value.isNotEmpty)
                          .map((e) => _socialChip(e.key, e.value))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),

          // ── Top bar ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _circleBtn(
                      Icons.arrow_back_ios_new_rounded,
                      () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (user.isOnline)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF30D158).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFF30D158)
                                  .withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                color: Color(0xFF30D158), size: 7),
                            SizedBox(width: 5),
                            Text('Online',
                                style: TextStyle(
                                    color: Color(0xFF30D158),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Tier badge ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [tierColor, tierColor.withValues(alpha: 0.7)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: tierColor.withValues(alpha: 0.45), blurRadius: 14)
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    '${user.rating.toStringAsFixed(1)} · $tierLabel',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom action bar ────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF060610).withValues(alpha: 0.0),
                    const Color(0xFF060610).withValues(alpha: 0.98),
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Full Profile button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: user.id)),
                      ),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_rounded,
                                color: Colors.white70, size: 18),
                            SizedBox(width: 6),
                            Text('Profile',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Reject button — only shown when onReject is provided
                  if (widget.onReject != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _handleReject,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.redAccent, size: 22),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  // Send Proposal button
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _proposalSent ? null : _sendProposal,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: _proposalSent
                              ? null
                              : const LinearGradient(colors: [
                                  Color(0xFFFF2D55),
                                  Color(0xFFBF5AF2),
                                ]),
                          color: _proposalSent ? const Color(0xFF1E8E5A) : null,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _proposalSent
                              ? null
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFFF2D55)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_sending)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            else
                              Icon(
                                _proposalSent
                                    ? Icons.check_rounded
                                    : Icons.favorite_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _proposalSent ? 'Sent ✓' : 'Send Proposal',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _photoFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D1B4E), Color(0xFF060610)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, color: Color(0xFF4A3060), size: 90),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _pill(String value, IconData icon, Color color,
      {String subtitle = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statChip(Color color, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF8E8E93),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _socialChip(String platform, String handle) {
    dynamic iconData;
    Color iconColor;
    switch (platform.toLowerCase()) {
      case 'instagram':
        iconData = FontAwesomeIcons.instagram;
        iconColor = const Color(0xFFE1306C);
        break;
      case 'tiktok':
        iconData = FontAwesomeIcons.tiktok;
        iconColor = Colors.white;
        break;
      case 'facebook':
        iconData = FontAwesomeIcons.facebook;
        iconColor = const Color(0xFF1877F2);
        break;
      case 'twitter':
      case 'x':
        iconData = FontAwesomeIcons.xTwitter;
        iconColor = Colors.white;
        break;
      case 'youtube':
        iconData = FontAwesomeIcons.youtube;
        iconColor = const Color(0xFFFF0000);
        break;
      default:
        iconData = Icons.link;
        iconColor = Colors.white70;
    }

    return GestureDetector(
      onTap: () async {
        String urlStr = handle;
        if (!urlStr.startsWith('http')) {
          if (platform.toLowerCase() == 'instagram') {
            urlStr = 'https://instagram.com/$urlStr';
          } else if (platform.toLowerCase() == 'tiktok') {
            urlStr = 'https://tiktok.com/@$urlStr';
          } else {
            urlStr = 'https://$urlStr';
          }
        }
        final uri = Uri.tryParse(urlStr);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: iconColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconData is IconData
                ? Icon(iconData, color: iconColor, size: 14)
                : Icon(Icons.link, color: iconColor, size: 14),
            const SizedBox(width: 6),
            Text(
              handle,
              style: TextStyle(
                  color: iconColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
