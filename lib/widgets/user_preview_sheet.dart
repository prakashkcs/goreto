import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/screens/chat/chat_screen.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/profile_service.dart';

/// Compact profile card shown when tapping a person inside a chat.
///
/// It opens instantly with the name/avatar already known from the chat, then
/// fills in bio and stats once the profile loads.
class UserPreviewSheet extends StatefulWidget {
  final String userId;
  final String name;
  final String? username;
  final String? avatar;
  final bool isMe;
  final String? roleLabel;

  /// Extra actions (e.g. group admin tools) shown under the main buttons.
  final List<Widget> Function(BuildContext sheetContext)? extraActions;

  const UserPreviewSheet({
    super.key,
    required this.userId,
    required this.name,
    this.username,
    this.avatar,
    this.isMe = false,
    this.roleLabel,
    this.extraActions,
  });

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String name,
    String? username,
    String? avatar,
    bool isMe = false,
    String? roleLabel,
    List<Widget> Function(BuildContext sheetContext)? extraActions,
  }) {
    return showGSheet<void>(
      context,
      builder: (_) => UserPreviewSheet(
        userId: userId,
        name: name,
        username: username,
        avatar: avatar,
        isMe: isMe,
        roleLabel: roleLabel,
        extraActions: extraActions,
      ),
    );
  }

  @override
  State<UserPreviewSheet> createState() => _UserPreviewSheetState();
}

class _UserPreviewSheetState extends State<UserPreviewSheet> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ProfileService().getUserProfile(widget.userId);
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // Keep the basic card; the full profile is one tap away.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }

  void _openProfile() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: widget.userId)));
  }

  void _openChat() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        userId: widget.userId,
        userName: _profile?.name ?? widget.name,
        userAvatar: _avatarUrl,
      ),
    ));
  }

  String? get _avatarUrl {
    final fromProfile = _profile?.profilePicUrl ?? '';
    if (fromProfile.isNotEmpty) return resolveUserAvatar(fromProfile);
    return resolveUserAvatar(widget.avatar);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final name = p?.name ?? widget.name;
    final username = (p?.username ?? widget.username ?? '').trim();
    final bio = (p?.bio ?? '').trim();
    final location = (p?.location ?? '').trim();
    final seed = int.tryParse(widget.userId) ?? 0;
    final extras = widget.extraActions?.call(context) ?? const <Widget>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient ring
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: GUI.gradient),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: GUI.surface),
              child: UserAvatar(
                  url: _avatarUrl, name: name, seed: seed, size: 84),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: GUI.textHi,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
              if (widget.roleLabel != null) ...[
                const SizedBox(width: 8),
                _RoleChip(widget.roleLabel!),
              ],
            ],
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('@$username',
                style: const TextStyle(color: GUI.textLo, fontSize: 14)),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: GUI.textLo, size: 14),
                const SizedBox(width: 3),
                Text(location,
                    style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
              ],
            ),
          ],
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: GUI.textMid, fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: 18),

          // Stats
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: GUI.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: GUI.border),
            ),
            child: Row(
              children: [
                _stat(p == null ? '–' : _fmt(p.postsCount), 'Posts'),
                _divider(),
                _stat(p == null ? '–' : _fmt(p.followersCount), 'Followers'),
                _divider(),
                _stat(p == null ? '–' : _fmt(p.followingCount), 'Following'),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                  minHeight: 2,
                  color: GUI.accent,
                  backgroundColor: Colors.transparent),
            ),
          const SizedBox(height: 18),

          // Primary actions
          Row(
            children: [
              if (!widget.isMe) ...[
                Expanded(
                  child: GPrimaryButton(
                    label: 'Message',
                    icon: Icons.chat_bubble_rounded,
                    onPressed: _openChat,
                    height: 48,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _openProfile,
                    icon: const Icon(Icons.person_outline_rounded,
                        color: GUI.textHi, size: 19),
                    label: const Text('View profile',
                        style: TextStyle(
                            color: GUI.textHi,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (extras.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: GUI.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GUI.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: extras),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: GUI.textHi,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: GUI.textLo, fontSize: 12)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 28, color: const Color(0x14FFFFFF));
}

class _RoleChip extends StatelessWidget {
  final String label;
  const _RoleChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: GUI.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(
              color: GUI.accent, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
