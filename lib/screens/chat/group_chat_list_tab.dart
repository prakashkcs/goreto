import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/screens/chat/group_chat_screen.dart';
import 'package:love_vibe_pro/screens/chat/create_group_screen.dart';
import 'package:love_vibe_pro/screens/chat/discover_groups_screen.dart';
import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupChatListTab extends StatefulWidget {
  const GroupChatListTab({super.key});

  @override
  State<GroupChatListTab> createState() => _GroupChatListTabState();
}

class _GroupChatListTabState extends State<GroupChatListTab> {
  late GroupChatService _service;
  List<ChatGroup> _myGroups = [];
  bool _isLoading = true;
  Timer? _timer;
  int _myUserId = 0;

  @override
  void initState() {
    super.initState();
    _service = GroupChatService();
    SharedPreferences.getInstance().then((p) {
      final id = int.tryParse(p.getString('user_id') ?? '') ?? 0;
      if (mounted) setState(() => _myUserId = id);
    });
    _service.getCachedGroups().then((cached) {
      if (cached.isNotEmpty && mounted) {
        setState(() { _myGroups = cached; _isLoading = false; });
      }
    });
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadData(showLoading: false);
    });
  }

  /// Returns a human-readable last-message preview with sender prefix.
  String _previewText(ChatGroup g) {
    final raw = g.lastMessage;
    if (raw == null || raw.isEmpty) return 'No messages yet';

    var type = g.lastMessageType ?? 'text';

    // URL-based fallback: detect media type from file extension when the
    // type field is unreliable (e.g. old rows stored before the ENUM migration).
    if ((type == 'text' || type.isEmpty) && raw.contains('/uploads/')) {
      final lower = raw.toLowerCase();
      if (lower.endsWith('.m4a') || lower.endsWith('.mp3') ||
          lower.endsWith('.aac') || lower.endsWith('.ogg') ||
          lower.endsWith('.wav')) {
        type = 'audio';
      } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
          lower.endsWith('.png') || lower.endsWith('.gif') ||
          lower.endsWith('.webp')) {
        type = 'image';
      } else if (lower.endsWith('.mp4') || lower.endsWith('.mov') ||
          lower.endsWith('.avi')) {
        type = 'video';
      }
    }

    final senderId = g.lastMessageSenderId ?? 0;
    final senderName = senderId == _myUserId
        ? 'You'
        : (g.lastMessageSender ?? '');
    final prefix = senderName.isNotEmpty ? '$senderName: ' : '';

    if (type == 'system') return raw;

    switch (type) {
      case 'image':
        return '$prefix📷 Photo';
      case 'video':
        return '$prefix🎥 Video';
      case 'audio':
        return '$prefix🎤 Voice message';
      default:
        return '$prefix$raw';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading && _myGroups.isEmpty && mounted) setState(() => _isLoading = true);
    try {
      final groups = await _service.getMyGroups();
      if (mounted) {
        setState(() {
          _myGroups = groups;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGroupOptions(ChatGroup g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.orange),
              title: const Text(
                'Clear My Chat',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text(
                      'Clear Chat',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Delete all your messages from this group?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final ok = await _service.clearMyChat(g.id);
                  if (ok && mounted) {
                    NeonToast.success(context, 'Chat cleared');
                    _loadData();
                  } else if (mounted) {
                    NeonToast.error(context, 'Failed to clear chat');
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text(
                'Leave Group',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text(
                      'Leave Group',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Are you sure you want to leave this group?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text(
                          'Leave',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final ok = await _service.leaveGroup(g.id);
                  if (ok && mounted) {
                    NeonToast.success(context, 'Left group');
                    _loadData();
                  } else if (mounted) {
                    NeonToast.error(context, 'Failed to leave group');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    final group = await Navigator.push<ChatGroup>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (group != null && mounted) {
      await _loadData();
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
      );
    }
  }

  void _discoverGroups() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DiscoverGroupsScreen()),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GalacticTheme.laserPink),
      );
    }
    return Column(
      children: [
        // ── Action buttons ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(child: _ActionBtn(
                label: 'New Group',
                icon: Icons.add_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFD946EF), Color(0xFFFF007F)],
                ),
                onTap: _createGroup,
              )),
              const SizedBox(width: 10),
              Expanded(child: _ActionBtn(
                label: 'Discover',
                icon: Icons.explore_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                ),
                onTap: _discoverGroups,
              )),
            ],
          ),
        ),
        // ── Group list ────────────────────────────────────────────────────
        Expanded(
          child: _myGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD946EF).withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFD946EF).withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(Icons.group_outlined,
                            color: Color(0xFFD946EF), size: 42),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No groups yet',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create a group or discover\npublic communities to join',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: GalacticTheme.laserPink,
                  backgroundColor: const Color(0xFF1A1A1A),
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _myGroups.length,
                    itemBuilder: (ctx, i) {
                      final g = _myGroups[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GroupChatScreen(group: g)),
                        ).then((_) => _loadData()),
                        onLongPress: () => _showGroupOptions(g),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: g.unreadCount > 0
                                  ? const Color(0xFFD946EF).withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.07),
                            ),
                            boxShadow: g.unreadCount > 0
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFD946EF)
                                          .withValues(alpha: 0.08),
                                      blurRadius: 10,
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: g.avatarUrl == null
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF7C3AED),
                                            Color(0xFFD946EF)
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  border: Border.all(
                                    color: const Color(0xFFD946EF)
                                        .withValues(alpha: 0.35),
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.transparent,
                                  backgroundImage: g.avatarUrl != null
                                      ? CachedNetworkImageProvider(g.avatarUrl!)
                                      : null,
                                  child: g.avatarUrl == null
                                      ? Text(
                                          g.name[0].toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            g.name,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (g.lastMessageTime != null)
                                          Text(
                                            DateUtil.formatShortDate(
                                                g.lastMessageTime!),
                                            style: TextStyle(
                                              color: g.unreadCount > 0
                                                  ? const Color(0xFFD946EF)
                                                  : Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _previewText(g),
                                      style: TextStyle(
                                        color: g.unreadCount > 0
                                            ? Colors.white70
                                            : Colors.white38,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Unread badge
                              if (g.unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFD946EF),
                                        Color(0xFFFF007F)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${g.unreadCount}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
