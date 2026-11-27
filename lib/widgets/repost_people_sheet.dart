import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// One person shown in [RepostPeopleSheet].
class RepostPerson {
  final String id;
  final String name;
  final String avatar;
  final String role; // "Reposted" / "Original creator"
  const RepostPerson(
      {required this.id,
      required this.name,
      required this.avatar,
      required this.role});
}

/// Bottom sheet for a reposted post: both the person who reposted it and the
/// original creator, each with Visit profile + Follow, and a link to the
/// original post.
class RepostPeopleSheet extends StatelessWidget {
  final List<RepostPerson> people;
  final String? originalPostId;

  const RepostPeopleSheet(
      {super.key, required this.people, this.originalPostId});

  static void show(
    BuildContext context, {
    required RepostPerson resharer,
    required RepostPerson original,
    String? originalPostId,
  }) {
    final people = <RepostPerson>[
      resharer,
      if (original.id.isNotEmpty && original.id != resharer.id) original,
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RepostPeopleSheet(people: people, originalPostId: originalPostId),
    );
  }

  /// Opens the original post a repost points at.
  static void openOriginal(BuildContext context, String? postId) {
    if (postId == null || postId.isEmpty || postId == '0') return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12101C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0x55D946EF), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.repeat_rounded, color: Color(0xFFD946EF), size: 18),
                  SizedBox(width: 8),
                  Text('Repost',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              for (final p in people) _PersonRow(person: p),
              if (originalPostId != null &&
                  originalPostId!.isNotEmpty &&
                  originalPostId != '0') ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute(
                        builder: (_) =>
                            PostDetailScreen(postId: originalPostId!)));
                  },
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('View original post',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatefulWidget {
  final RepostPerson person;
  const _PersonRow({required this.person});

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _busy = false;
  bool _followed = false;

  bool get _isMe => widget.person.id == (UserPrefsCache.instance.userId ?? '');

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = _followed
        ? await ApiService().unfollowUser(widget.person.id)
        : await ApiService().followUser(widget.person.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _followed = !_followed;
    });
    if (r == null) NeonToast.error(context, 'Could not update follow');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final hasPic = p.avatar.startsWith('http');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: _visit,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF2A1A3E),
              backgroundImage:
                  hasPic ? CachedNetworkImageProvider(p.avatar) : null,
              child: hasPic
                  ? null
                  : Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _visit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name.isNotEmpty ? p.name : 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(p.role,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
          _pill('Profile', const Color(0xFF06B6D4), _visit),
          if (!_isMe) ...[
            const SizedBox(width: 8),
            _pill(
              _busy ? '...' : (_followed ? 'Following' : 'Follow'),
              const Color(0xFFFF007F),
              _follow,
              filled: !_followed,
            ),
          ],
        ],
      ),
    );
  }

  void _visit() {
    if (widget.person.id.isEmpty || widget.person.id == '0') return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: widget.person.id)));
  }

  Widget _pill(String label, Color color, VoidCallback onTap,
      {bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? Colors.white : color,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ),
    );
  }
}
