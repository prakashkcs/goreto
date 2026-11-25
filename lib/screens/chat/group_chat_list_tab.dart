import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/screens/chat/group_chat_screen.dart';
import 'package:love_vibe_pro/screens/chat/create_group_screen.dart';
import 'package:love_vibe_pro/screens/chat/discover_groups_screen.dart';
import 'package:love_vibe_pro/screens/chat/group_invites.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupChatListTab extends StatefulWidget {
  const GroupChatListTab({super.key});

  @override
  State<GroupChatListTab> createState() => _GroupChatListTabState();
}

class _GroupChatListTabState extends State<GroupChatListTab> {
  final GroupChatService _service = GroupChatService();
  List<ChatGroup> _myGroups = [];
  bool _isLoading = true;
  Timer? _timer;
  int _myUserId = 0;
  int _pendingInvites = GroupChatService.lastPendingInvites;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final id = int.tryParse(p.getString('user_id') ?? '') ?? 0;
      if (mounted) setState(() => _myUserId = id);
    });
    _service.getCachedGroups().then((cached) {
      if (cached.isNotEmpty && mounted && _myGroups.isEmpty) {
        setState(() {
          _myGroups = cached;
          _isLoading = false;
        });
      }
    });
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadData(showLoading: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Human-readable last-message preview with sender prefix.
  String _previewText(ChatGroup g) {
    final raw = g.lastMessage;
    if (raw == null || raw.isEmpty) return 'No messages yet';

    var type = g.lastMessageType ?? 'text';
    if ((type == 'text' || type.isEmpty) && raw.contains('/uploads/')) {
      final lower = raw.toLowerCase();
      if (RegExp(r'\.(m4a|mp3|aac|ogg|wav)$').hasMatch(lower)) {
        type = 'audio';
      } else if (RegExp(r'\.(jpe?g|png|gif|webp)$').hasMatch(lower)) {
        type = 'image';
      } else if (RegExp(r'\.(mp4|mov|avi|webm|m4v)$').hasMatch(lower)) {
        type = 'video';
      }
    }
    if (type == 'system') return raw;

    final senderId = g.lastMessageSenderId ?? 0;
    final senderName =
        senderId == _myUserId ? 'You' : (g.lastMessageSender ?? '').split(' ').first;
    final prefix = senderName.isNotEmpty ? '$senderName: ' : '';

    switch (type) {
      case 'image':
        return '${prefix}Photo';
      case 'video':
        return '${prefix}Video';
      case 'audio':
        return '${prefix}Voice message';
      default:
        return '$prefix$raw';
    }
  }

  IconData? _previewIcon(ChatGroup g) {
    switch (g.lastMessageType) {
      case 'image':
        return Icons.photo_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'audio':
        return Icons.mic_rounded;
      default:
        return null;
    }
  }

  String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat.jm().format(t);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(t);
    return DateFormat('d/M/yy').format(t);
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading && _myGroups.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final groups = await _service.getMyGroups();
      if (mounted) {
        setState(() {
          _myGroups = groups;
          _pendingInvites = GroupChatService.lastPendingInvites;
          _isLoading = false;
        });
      }
    } catch (_) {
      // Keep whatever is on screen (cached list) on a network hiccup.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGroupOptions(ChatGroup g) {
    showGSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GSheetHeader(
              title: g.name,
              subtitle: formatMemberCount(g.memberCount),
              leading: GroupAvatar.of(g, size: 44),
            ),
            GSheetAction(
              icon: Icons.cleaning_services_outlined,
              label: 'Clear chat history',
              subtitle: 'Removes messages for you only',
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await gConfirm(context,
                    title: 'Clear chat history?',
                    message:
                        'Messages will be removed for you only. Other members will still see them.',
                    confirmLabel: 'Clear',
                    destructive: true);
                if (!ok) return;
                final done = await _service.clearMyChat(g.id);
                if (!mounted) return;
                if (done) {
                  NeonToast.success(context, 'Chat cleared');
                  _loadData();
                } else {
                  NeonToast.error(context, 'Failed to clear chat');
                }
              },
            ),
            GSheetAction(
              icon: Icons.logout_rounded,
              label: 'Leave group',
              destructive: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await gConfirm(context,
                    title: 'Leave ${g.name}?',
                    message: 'You will stop receiving messages from this group.',
                    confirmLabel: 'Leave',
                    destructive: true);
                if (!ok) return;
                final done = await _service.leaveGroup(g.id);
                if (!mounted) return;
                if (done) {
                  NeonToast.success(context, 'Left group');
                  _loadData();
                } else {
                  NeonToast.error(context, 'Failed to leave group');
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
      _loadData(showLoading: false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
      ).then((_) => _loadData(showLoading: false));
    }
  }

  void _discoverGroups() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DiscoverGroupsScreen()),
    ).then((_) => _loadData(showLoading: false));
  }

  void _openInvites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupInvitesScreen()),
    ).then((_) => _loadData(showLoading: false));
  }

  void _openGroup(ChatGroup g) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(group: g)),
    ).then((_) => _loadData(showLoading: false));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: GUI.accent, strokeWidth: 2));
    }
    return RefreshIndicator(
      color: GUI.accent,
      backgroundColor: GUI.surface,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: 'New group',
                      icon: Icons.add_rounded,
                      primary: true,
                      onTap: _createGroup,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Discover',
                      icon: Icons.explore_outlined,
                      onTap: _discoverGroups,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_pendingInvites > 0)
            SliverToBoxAdapter(child: _invitesBanner()),
          if (_myGroups.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
              sliver: SliverList.builder(
                itemCount: _myGroups.length,
                itemBuilder: (_, i) => _groupRow(_myGroups[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _invitesBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Material(
        color: GUI.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openInvites,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: GUI.accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const GIconBox(Icons.mail_outline_rounded, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pendingInvites == 1
                            ? '1 group invitation'
                            : '$_pendingInvites group invitations',
                        style: const TextStyle(
                            color: GUI.textHi,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700),
                      ),
                      const Text('Tap to accept or decline',
                          style: TextStyle(color: GUI.textLo, fontSize: 12.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: GUI.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GIconBox(Icons.groups_rounded, size: 64),
          const SizedBox(height: 18),
          const Text('No groups yet',
              style: TextStyle(
                  color: GUI.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Create a group for your friends or discover public communities to join.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GUI.textLo, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            child: GPrimaryButton(
                label: 'Create a group',
                icon: Icons.add_rounded,
                onPressed: _createGroup),
          ),
        ],
      ),
    );
  }

  Widget _groupRow(ChatGroup g) {
    final hasUnread = g.unreadCount > 0;
    final icon = _previewIcon(g);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openGroup(g),
        onLongPress: () => _showGroupOptions(g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              GroupAvatar.of(g, size: 54),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(g.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: GUI.textHi,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5)),
                        ),
                        if (g.isPrivate) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.lock_rounded,
                              size: 13, color: GUI.textLo),
                        ],
                        const Spacer(),
                        if (g.lastMessageTime != null)
                          Text(_timeLabel(g.lastMessageTime!),
                              style: TextStyle(
                                  color: hasUnread ? GUI.accent : GUI.textLo,
                                  fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 14, color: GUI.textLo),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            _previewText(g),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: hasUnread ? GUI.textMid : GUI.textLo,
                                fontSize: 13.5),
                          ),
                        ),
                        if (g.isAdmin && g.pendingRequests > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: GUI.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.how_to_reg_rounded,
                                    size: 12, color: GUI.warning),
                                const SizedBox(width: 3),
                                Text('${g.pendingRequests}',
                                    style: const TextStyle(
                                        color: GUI.warning,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        if (hasUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: GUI.gradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${g.unreadCount}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: primary ? GUI.gradient : null,
            color: primary ? null : GUI.surface,
            borderRadius: BorderRadius.circular(14),
            border: primary ? null : Border.all(color: GUI.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
