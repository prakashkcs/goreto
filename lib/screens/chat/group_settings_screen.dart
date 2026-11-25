import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/chat/create_group_screen.dart'
    show GroupTypeSelector;
import 'package:love_vibe_pro/screens/chat/group_invites.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/user_preview_sheet.dart';

/// Result values this screen pops with so the chat screen can react.
class GroupSettingsResult {
  static const left = 'left';
  static const deleted = 'deleted';
  static const cleared = 'cleared';
}

/// Group info & settings.
class GroupSettingsScreen extends StatefulWidget {
  final ChatGroup group;

  /// Called whenever the group changes (name, avatar, settings…), so the
  /// screen underneath can update without a reload.
  final ValueChanged<ChatGroup>? onGroupUpdated;

  const GroupSettingsScreen(
      {super.key, required this.group, this.onGroupUpdated});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupChatService _service = GroupChatService();

  late ChatGroup _group;
  List<ChatGroupMember> _members = [];
  String _myRole = 'member';
  int _ownerId = 0;
  int _myId = 0;
  bool _membersLoading = true;
  bool _showAllMembers = false;

  String? _localAvatar;
  bool _avatarUploading = false;

  bool get _isAdmin => _myRole == 'admin';
  bool get _isOwner => _ownerId != 0 && _ownerId == _myId;
  bool get _canInvite => _isAdmin || _group.membersCanInvite;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myId = int.tryParse(auth.currentUserId ?? '0') ?? 0;
    _group = widget.group;
    _myRole = widget.group.myRole ??
        (widget.group.createdBy == _myId ? 'admin' : 'member');
    _ownerId = widget.group.createdBy;
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.getGroupDetails(_group.id),
      _service.getGroupMembers(_group.id),
    ]);
    if (!mounted) return;
    final g = results[0] as ChatGroup?;
    final m = results[1] as Map<String, dynamic>;
    setState(() {
      if (g != null) _setGroup(g, notify: false);
      _members = (m['members'] as List<ChatGroupMember>?) ?? [];
      _myRole = (m['my_role'] ?? _myRole).toString();
      final owner = m['owner_id'] as int? ?? 0;
      if (owner > 0) _ownerId = owner;
      _membersLoading = false;
    });
    if (g != null) widget.onGroupUpdated?.call(_group);
  }

  void _setGroup(ChatGroup g, {bool notify = true}) {
    _group = g;
    if (g.myRole != null) _myRole = g.myRole!;
    if (g.createdBy > 0) _ownerId = g.createdBy;
    if (notify) widget.onGroupUpdated?.call(g);
  }

  /// Saves settings and applies the fresh server copy. Returns an error
  /// message, or null on success.
  Future<String?> _save({
    String? name,
    String? username,
    String? bio,
    bool? isPrivate,
    bool? joinApproval,
    bool? membersCanInvite,
    int? joinFee,
    int? messageDelay,
    GroupPermissions? permissions,
  }) async {
    final r = await _service.updateSettings(
      _group.id,
      name: name,
      username: username,
      bio: bio,
      isPrivate: isPrivate,
      joinApproval: joinApproval,
      membersCanInvite: membersCanInvite,
      joinFee: joinFee,
      messageDelay: messageDelay,
      permissions: permissions,
    );
    if (!mounted) return null;
    if (!r.success) return r.message.isNotEmpty ? r.message : 'Could not save';
    if (r.group != null) setState(() => _setGroup(r.group!));
    return null;
  }

  Future<void> _quickSave(
      Future<String?> Function() op, ChatGroup optimistic) async {
    final previous = _group;
    setState(() => _group = optimistic);
    final err = await op();
    if (!mounted) return;
    if (err != null) {
      setState(() => _group = previous);
      NeonToast.error(context, err);
    }
  }

  // ── Avatar ────────────────────────────────────────────────────────────────

  void _onAvatarTap() {
    if (!_isAdmin) {
      if (_group.avatarUrl != null) _viewPhoto();
      return;
    }
    showGSheet<void>(context, builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GSheetHeader(title: 'Group photo'),
            GSheetAction(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            GSheetAction(
              icon: Icons.photo_camera_outlined,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.camera);
              },
            ),
            if (_group.avatarUrl != null)
              GSheetAction(
                icon: Icons.fullscreen_rounded,
                label: 'View photo',
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPhoto();
                },
              ),
          ],
        ),
      );
    });
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    // Show the new photo right away; upload in the background.
    setState(() {
      _localAvatar = picked.path;
      _avatarUploading = true;
    });
    final r = await _service.updateSettings(_group.id, avatarPath: picked.path);
    if (!mounted) return;
    setState(() => _avatarUploading = false);
    if (r.success && r.group != null) {
      final url = r.group!.avatarUrl;
      if (url != null) {
        // Warm the cache so every screen shows it instantly.
        await precacheImage(CachedNetworkImageProvider(url), context)
            .catchError((_) {});
      }
      if (!mounted) return;
      setState(() {
        _setGroup(r.group!);
        _localAvatar = null;
      });
      NeonToast.success(context, 'Group photo updated');
    } else {
      setState(() => _localAvatar = null);
      NeonToast.error(context, r.message.isNotEmpty ? r.message : 'Upload failed');
    }
  }

  void _viewPhoto() {
    final url = _group.avatarUrl;
    if (url == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PhotoViewer(url: url, title: _group.name)),
    );
  }

  // ── Editors ───────────────────────────────────────────────────────────────

  Future<void> _editName() async {
    await _showTextEditor(
      title: 'Group name',
      subtitle: 'Everyone in the group will see the new name.',
      initial: _group.name,
      hint: 'Group name',
      maxLength: 60,
      onSave: (v) {
        if (v.trim().isEmpty) return Future.value('Name cannot be empty');
        return _save(name: v.trim());
      },
    );
  }

  Future<void> _editBio() async {
    await _showTextEditor(
      title: 'Description',
      subtitle:
          'Tell people what the group is about. Words here also help it show up in search.',
      initial: _group.bio ?? '',
      hint: 'What is this group about?',
      maxLength: 300,
      maxLines: 5,
      onSave: (v) => _save(bio: v.trim()),
    );
  }

  Future<void> _showTextEditor({
    required String title,
    required String subtitle,
    required String initial,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    required Future<String?> Function(String) onSave,
  }) async {
    final saved = await showGSheet<bool>(
      context,
      builder: (_) => _TextEditorSheet(
        title: title,
        subtitle: subtitle,
        initial: initial,
        hint: hint,
        maxLength: maxLength,
        maxLines: maxLines,
        onSave: onSave,
      ),
    );
    if (saved == true && mounted) NeonToast.success(context, '$title updated');
  }

  Future<void> _editUsername() async {
    final saved = await showGSheet<bool>(
      context,
      builder: (_) => _UsernameEditorSheet(
        group: _group,
        service: _service,
        onSave: (v) => _save(username: v),
      ),
    );
    if (saved == true && mounted) NeonToast.success(context, 'Username updated');
  }

  Future<void> _editGroupType() async {
    bool isPrivate = _group.isPrivate;
    final result = await showGSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GSheetHeader(
                title: 'Group type',
                subtitle: 'Choose who can find and join this group.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: GroupTypeSelector(
                  isPrivate: isPrivate,
                  onChanged: (v) => setSheet(() => isPrivate = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GPrimaryButton(
                  label: 'Save',
                  onPressed: () => Navigator.pop(ctx, isPrivate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result == _group.isPrivate) return;
    await _quickSave(
      () => _save(isPrivate: result),
      _group.copyWith(isPrivate: result),
    );
    if (mounted) {
      NeonToast.success(context,
          result ? 'Group is now private' : 'Group is now public');
    }
  }

  Future<void> _editPermissions() async {
    final result = await showGSheet<GroupPermissions>(
      context,
      builder: (_) => _PermissionsSheet(initial: _group.permissions),
    );
    if (result == null) return;
    await _quickSave(() => _save(permissions: result),
        _group.copyWith(permissions: result));
    if (mounted) NeonToast.success(context, 'Permissions updated');
  }

  Future<void> _editSlowMode() async {
    const options = [0, 5, 10, 30, 60, 300, 900];
    final result = await showGSheet<int>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GSheetHeader(
              title: 'Slow mode',
              subtitle:
                  'Set how long members wait between messages. Admins are not limited.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((s) {
                  final sel = s == _group.messageDelay;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: sel ? GUI.gradient : null,
                        color: sel ? null : GUI.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: sel ? null : Border.all(color: GUI.border),
                      ),
                      child: Text(_delayLabel(s),
                          style: TextStyle(
                              color: sel ? Colors.white : GUI.textMid,
                              fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == _group.messageDelay) return;
    await _quickSave(() => _save(messageDelay: result),
        _group.copyWith(messageDelay: result));
  }

  Future<void> _editJoinFee() async {
    await _showTextEditor(
      title: 'Join fee',
      subtitle:
          'Coins charged when someone joins. People invited by an admin join for free. Use 0 for a free group.',
      initial: _group.joinFee.toString(),
      hint: '0',
      maxLength: 6,
      onSave: (v) {
        final fee = int.tryParse(v.trim());
        if (fee == null || fee < 0) {
          return Future.value('Enter a valid number of coins');
        }
        return _save(joinFee: fee);
      },
    );
  }

  String _delayLabel(int s) {
    if (s == 0) return 'Off';
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m';
  }

  String _permissionSummary(GroupPermissions p) {
    final allowed = <String>[
      if (p.canSendText) 'Text',
      if (p.canSendMedia) 'Media',
      if (p.canSendVoice) 'Voice',
      if (p.canSendStickers) 'Stickers',
    ];
    if (allowed.length == 4) return 'Members can send everything';
    if (allowed.isEmpty) return 'Only admins can send messages';
    return 'Allowed: ${allowed.join(', ')}';
  }

  // ── Members ───────────────────────────────────────────────────────────────

  Future<void> _addMembers() async {
    final n = await AddMembersSheet.show(context, _group);
    if (n != null && n > 0) _load();
  }

  Future<void> _openRequests() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupRequestsScreen(groupId: _group.id, groupName: _group.name),
      ),
    );
    _load();
  }

  String? _roleLabel(ChatGroupMember m) {
    if (m.id == _ownerId) return 'Owner';
    if (m.isAdmin) return 'Admin';
    return null;
  }

  void _openMember(ChatGroupMember m) {
    final isMe = m.id == _myId;
    final targetIsOwner = m.id == _ownerId;
    final canManage = _isAdmin && !isMe && !targetIsOwner && (!m.isAdmin || _isOwner);

    UserPreviewSheet.show(
      context,
      userId: m.id.toString(),
      name: m.name,
      username: m.username,
      avatar: m.avatar,
      isMe: isMe,
      roleLabel: _roleLabel(m),
      extraActions: !canManage
          ? null
          : (ctx) => <Widget>[
                GSheetAction(
                  icon: m.isAdmin
                      ? Icons.remove_moderator_outlined
                      : Icons.add_moderator_outlined,
                  label: m.isAdmin ? 'Remove as admin' : 'Make group admin',
                  subtitle: m.isAdmin
                      ? 'They will become a regular member'
                      : 'Admins can manage members and settings',
                  color: GUI.info,
                  onTap: () {
                    Navigator.pop(ctx);
                    _setRole(m, m.isAdmin ? 'member' : 'admin');
                  },
                ),
                GSheetAction(
                  icon: Icons.person_remove_outlined,
                  label: 'Remove from group',
                  subtitle: 'They can rejoin or be invited again',
                  color: GUI.warning,
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(m, ban: false);
                  },
                ),
                GSheetAction(
                  icon: Icons.block_rounded,
                  label: 'Ban from group',
                  subtitle: 'Removes them and blocks them from rejoining',
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(m, ban: true);
                  },
                ),
              ],
    );
  }

  Future<void> _setRole(ChatGroupMember m, String role) async {
    final r = await _service.setRole(_group.id, m.id, role);
    if (!mounted) return;
    if (r.success) {
      NeonToast.success(context,
          role == 'admin' ? '${m.name} is now an admin' : '${m.name} is no longer an admin');
      _load();
    } else {
      NeonToast.error(context, r.message);
    }
  }

  Future<void> _removeMember(ChatGroupMember m, {required bool ban}) async {
    final ok = await gConfirm(
      context,
      title: ban ? 'Ban ${m.name}?' : 'Remove ${m.name}?',
      message: ban
          ? 'They will be removed and won\'t be able to rejoin this group.'
          : 'They will be removed from the group. They can be invited again later.',
      confirmLabel: ban ? 'Ban' : 'Remove',
      destructive: true,
      icon: ban ? Icons.block_rounded : Icons.person_remove_outlined,
    );
    if (!ok) return;
    final r = ban
        ? await _service.banMember(_group.id, m.id)
        : await _service.kickMember(_group.id, m.id);
    if (!mounted) return;
    if (r.success) {
      setState(() => _members.removeWhere((x) => x.id == m.id));
      NeonToast.success(context, ban ? '${m.name} was banned' : '${m.name} was removed');
      _load();
    } else {
      NeonToast.error(context, r.message);
    }
  }

  // ── Danger zone ───────────────────────────────────────────────────────────

  Future<void> _clearChat() async {
    final ok = await gConfirm(
      context,
      title: 'Clear chat history?',
      message:
          'Messages will be removed for you only. Other members will still see them.',
      confirmLabel: 'Clear',
      destructive: true,
      icon: Icons.cleaning_services_outlined,
    );
    if (!ok) return;
    final done = await _service.clearMyChat(_group.id);
    if (!mounted) return;
    if (done) {
      NeonToast.success(context, 'Chat cleared');
      Navigator.pop(context, GroupSettingsResult.cleared);
    } else {
      NeonToast.error(context, 'Failed to clear chat');
    }
  }

  Future<void> _leave() async {
    final ok = await gConfirm(
      context,
      title: 'Leave ${_group.name}?',
      message: _isAdmin && _members.where((m) => m.isAdmin).length <= 1
          ? 'You are the only admin. Another member will be made admin automatically.'
          : 'You will stop receiving messages from this group.',
      confirmLabel: 'Leave',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok) return;
    final done = await _service.leaveGroup(_group.id);
    if (!mounted) return;
    if (done) {
      Navigator.pop(context, GroupSettingsResult.left);
    } else {
      NeonToast.error(context, 'Failed to leave group');
    }
  }

  Future<void> _delete() async {
    final ok = await gConfirm(
      context,
      title: 'Delete group?',
      message:
          'This permanently deletes ${_group.name}, its messages and members for everyone. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    final done = await _service.deleteGroup(_group.id);
    if (!mounted) return;
    if (done) {
      Navigator.pop(context, GroupSettingsResult.deleted);
    } else {
      NeonToast.error(context, 'Failed to delete group');
    }
  }

  void _copyUsername() {
    final u = _group.username;
    if (u == null || u.isEmpty) return;
    Clipboard.setData(ClipboardData(text: '@$u'));
    NeonToast.success(context, 'Copied @$u');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GUI.bg,
      appBar: AppBar(
        backgroundColor: GUI.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Group info',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: GUI.accent,
        backgroundColor: GUI.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _header(),
            _quickActions(),
            if (_isAdmin) ..._adminSections(),
            ..._memberSection(),
            const GSectionLabel('More'),
            GSection(children: [
              GTile(
                icon: Icons.cleaning_services_outlined,
                iconColor: GUI.warning,
                title: 'Clear chat history',
                subtitle: 'Removes messages for you only',
                onTap: _clearChat,
              ),
              GTile(
                icon: Icons.logout_rounded,
                title: 'Leave group',
                destructive: true,
                onTap: _leave,
              ),
              if (_isOwner)
                GTile(
                  icon: Icons.delete_forever_rounded,
                  title: 'Delete group',
                  subtitle: 'Permanently delete for everyone',
                  destructive: true,
                  onTap: _delete,
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final g = _group;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: _onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, gradient: GUI.gradient),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: GUI.bg),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GroupAvatar.of(g, size: 104, localPath: _localAvatar),
                        if (_avatarUploading)
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_isAdmin)
                  Positioned(
                    right: 2,
                    bottom: 4,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: GUI.gradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: GUI.bg, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(g.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: GUI.textHi,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
          if ((g.username ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _copyUsername,
              child: Text('@${g.username}',
                  style: const TextStyle(color: GUI.accent, fontSize: 14.5)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chip(g.isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                  g.isPrivate ? 'Private' : 'Public',
                  g.isPrivate ? GUI.warning : GUI.success),
              const SizedBox(width: 8),
              _chip(Icons.people_alt_rounded,
                  formatMemberCount(_membersLoading ? g.memberCount : _members.length),
                  GUI.info),
              if (g.joinFee > 0) ...[
                const SizedBox(width: 8),
                _chip(Icons.monetization_on_rounded, '${g.joinFee}', GUI.warning),
              ],
            ],
          ),
          if ((g.bio ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(g.bio!.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: GUI.textMid, fontSize: 14, height: 1.45)),
          ] else if (_isAdmin) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _editBio,
              child: const Text('+ Add a description',
                  style: TextStyle(
                      color: GUI.accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _quickActions() {
    final actions = <Widget>[
      if (_canInvite)
        _QuickAction(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Add',
            onTap: _addMembers),
      _QuickAction(
          icon: Icons.alternate_email_rounded,
          label: 'Copy @',
          onTap: _copyUsername),
      if (_isAdmin)
        _QuickAction(
            icon: Icons.how_to_reg_rounded,
            label: 'Requests',
            badge: _group.pendingRequests,
            onTap: _openRequests),
      _QuickAction(
          icon: Icons.logout_rounded,
          label: 'Leave',
          color: GUI.danger,
          onTap: _leave),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }

  List<Widget> _adminSections() {
    final g = _group;
    return [
      const GSectionLabel('Group details'),
      GSection(children: [
        GTile(
          icon: Icons.drive_file_rename_outline_rounded,
          title: 'Name',
          value: g.name,
          onTap: _editName,
        ),
        GTile(
          icon: Icons.alternate_email_rounded,
          iconColor: GUI.info,
          title: 'Username',
          value: (g.username ?? '').isEmpty ? 'Not set' : '@${g.username}',
          onTap: _editUsername,
        ),
        GTile(
          icon: Icons.notes_rounded,
          iconColor: GUI.success,
          title: 'Description',
          subtitle: (g.bio ?? '').trim().isEmpty ? 'Add a description' : g.bio!.trim(),
          onTap: _editBio,
        ),
      ]),
      const GSectionLabel('Privacy & access'),
      GSection(children: [
        GTile(
          icon: g.isPrivate ? Icons.lock_rounded : Icons.public_rounded,
          iconColor: g.isPrivate ? GUI.warning : GUI.success,
          title: 'Group type',
          subtitle: g.isPrivate
              ? 'Hidden from Discover · invite or approval only'
              : 'Visible in Discover · anyone can find it',
          value: g.isPrivate ? 'Private' : 'Public',
          onTap: _editGroupType,
        ),
        if (!g.isPrivate)
          GSwitchTile(
            icon: Icons.verified_user_outlined,
            iconColor: GUI.info,
            title: 'Approve new members',
            subtitle: 'Review join requests before people get in',
            value: g.joinApproval,
            onChanged: (v) => _quickSave(
                () => _save(joinApproval: v), g.copyWith(joinApproval: v)),
          ),
        GSwitchTile(
          icon: Icons.group_add_outlined,
          iconColor: GUI.accent2,
          title: 'Members can invite',
          subtitle: 'Let everyone send invitations, not just admins',
          value: g.membersCanInvite,
          onChanged: (v) => _quickSave(() => _save(membersCanInvite: v),
              g.copyWith(membersCanInvite: v)),
        ),
        GTile(
          icon: Icons.how_to_reg_rounded,
          iconColor: GUI.success,
          title: 'Requests & invites',
          subtitle: 'Approve join requests, manage sent invites',
          badge: g.pendingRequests,
          onTap: _openRequests,
        ),
      ]),
      const GSectionLabel('Messaging'),
      GSection(children: [
        GTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Member permissions',
          subtitle: _permissionSummary(g.permissions),
          onTap: _editPermissions,
        ),
        GTile(
          icon: Icons.timer_outlined,
          iconColor: GUI.warning,
          title: 'Slow mode',
          value: _delayLabel(g.messageDelay),
          onTap: _editSlowMode,
        ),
        GTile(
          icon: Icons.monetization_on_outlined,
          iconColor: GUI.warning,
          title: 'Join fee',
          value: g.joinFee > 0 ? '${g.joinFee} coins' : 'Free',
          onTap: _editJoinFee,
        ),
      ]),
    ];
  }

  List<Widget> _memberSection() {
    final count = _members.length;
    final visible =
        _showAllMembers || count <= 8 ? _members : _members.take(8).toList();
    return [
      GSectionLabel(
        _membersLoading ? 'Members' : 'Members · $count',
      ),
      GSection(children: [
        if (_canInvite)
          GTile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Add members',
            subtitle: 'Invite friends by name or @username',
            onTap: _addMembers,
            trailing: const SizedBox.shrink(),
          ),
        if (_membersLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(
                    color: GUI.accent, strokeWidth: 2)),
          )
        else
          ...visible.map(_memberRow),
        if (!_membersLoading && count > 8)
          InkWell(
            onTap: () => setState(() => _showAllMembers = !_showAllMembers),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  _showAllMembers ? 'Show less' : 'See all $count members',
                  style: const TextStyle(
                      color: GUI.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ]),
    ];
  }

  Widget _memberRow(ChatGroupMember m) {
    final role = _roleLabel(m);
    final isMe = m.id == _myId;
    return InkWell(
      onTap: () => _openMember(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            UserAvatar(url: m.avatarUrl, name: m.name, seed: m.id, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isMe ? '${m.name} (You)' : m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: GUI.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  if (m.username.isNotEmpty)
                    Text('@${m.username}',
                        style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
                ],
              ),
            ),
            if (role != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (role == 'Owner' ? GUI.warning : GUI.accent)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(role,
                    style: TextStyle(
                        color: role == 'Owner' ? GUI.warning : GUI.accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pieces
// ═══════════════════════════════════════════════════════════════════════════

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final int badge;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = GUI.accent,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GUI.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GUI.border),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 23),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: GUI.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$badge',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: color == GUI.danger ? GUI.danger : GUI.textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic single-field editor (name, description, join fee).
class _TextEditorSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String initial;
  final String hint;
  final int maxLength;
  final int maxLines;
  final Future<String?> Function(String) onSave;

  const _TextEditorSheet({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.hint,
    required this.maxLength,
    required this.maxLines,
    required this.onSave,
  });

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isNumber => widget.title == 'Join fee';

  Future<void> _submit() async {
    if (_ctrl.text.trim() == widget.initial.trim()) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await widget.onSave(_ctrl.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GSheetHeader(title: widget.title, subtitle: widget.subtitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: GTextField(
              controller: _ctrl,
              hint: widget.hint,
              autofocus: true,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,
              errorText: _error,
              keyboardType: _isNumber ? TextInputType.number : null,
              formatters:
                  _isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: GUI.textMid, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GPrimaryButton(
                      label: 'Save', loading: _saving, onPressed: _submit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Username editor with live availability.
class _UsernameEditorSheet extends StatefulWidget {
  final ChatGroup group;
  final GroupChatService service;
  final Future<String?> Function(String) onSave;

  const _UsernameEditorSheet(
      {required this.group, required this.service, required this.onSave});

  @override
  State<_UsernameEditorSheet> createState() => _UsernameEditorSheetState();
}

class _UsernameEditorSheetState extends State<_UsernameEditorSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.group.username ?? '');
  late final UsernameChecker _checker;
  UsernameState _state = UsernameState.idle;
  String? _msg;
  String? _suggestion;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checker = UsernameChecker(
      service: widget.service,
      groupId: widget.group.id,
      onResult: (s, m, sug) {
        if (mounted) {
          setState(() {
            _state = s;
            _msg = m;
            _suggestion = sug;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _checker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _use(String v) {
    _ctrl.value = TextEditingValue(
        text: v, selection: TextSelection.collapsed(offset: v.length));
    _checker.check(v, original: widget.group.username);
  }

  bool get _unchanged =>
      _ctrl.text.trim().toLowerCase() ==
      (widget.group.username ?? '').toLowerCase();

  Future<void> _submit() async {
    final v = _ctrl.text.trim().toLowerCase();
    if (_unchanged) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    final err = await widget.onSave(v);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _state = UsernameState.taken;
        _msg = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving &&
        _ctrl.text.trim().isNotEmpty &&
        _state != UsernameState.taken &&
        _state != UsernameState.invalid &&
        _state != UsernameState.checking;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GSheetHeader(
            title: 'Username',
            subtitle:
                'People can find and mention the group with its @username.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GTextField(
              controller: _ctrl,
              autofocus: true,
              hint: 'group_username',
              formatters: usernameFormatter,
              onChanged: (v) => _checker.check(v, original: widget.group.username),
              prefix: const Padding(
                padding: EdgeInsets.only(left: 16, right: 2),
                child: Text('@',
                    style: TextStyle(
                        color: GUI.textLo,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: UsernameStatusLine(
              state: _state,
              message: _msg,
              suggestion: _suggestion,
              onUseSuggestion: _use,
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GUI.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Rule('3 to 30 characters'),
                _Rule('Lowercase letters, numbers, underscores and dots'),
                _Rule('Can\'t start or end with _ or .'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GPrimaryButton(
              label: 'Save username',
              loading: _saving,
              onPressed: canSave ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 14, color: GUI.textLo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// Member permissions editor.
class _PermissionsSheet extends StatefulWidget {
  final GroupPermissions initial;
  const _PermissionsSheet({required this.initial});

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late GroupPermissions _p = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GSheetHeader(
            title: 'Member permissions',
            subtitle:
                'Choose what regular members can send. Admins can always send everything.',
          ),
          const SizedBox(height: 8),
          GSection(children: [
            GSwitchTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Send messages',
              subtitle: 'Text messages',
              value: _p.canSendText,
              onChanged: (v) => setState(() => _p = _p.copyWith(canSendText: v)),
            ),
            GSwitchTile(
              icon: Icons.photo_library_outlined,
              iconColor: GUI.info,
              title: 'Send photos & videos',
              subtitle: 'Images and video clips',
              value: _p.canSendMedia,
              onChanged: (v) =>
                  setState(() => _p = _p.copyWith(canSendMedia: v)),
            ),
            GSwitchTile(
              icon: Icons.mic_none_rounded,
              iconColor: GUI.success,
              title: 'Send voice messages',
              subtitle: 'Recorded audio notes',
              value: _p.canSendVoice,
              onChanged: (v) =>
                  setState(() => _p = _p.copyWith(canSendVoice: v)),
            ),
            GSwitchTile(
              icon: Icons.emoji_emotions_outlined,
              iconColor: GUI.warning,
              title: 'Send stickers & GIFs',
              subtitle: 'Stickers, GIFs and emoji reactions',
              value: _p.canSendStickers,
              onChanged: (v) =>
                  setState(() => _p = _p.copyWith(canSendStickers: v)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: GPrimaryButton(
              label: 'Save permissions',
              onPressed: () => Navigator.pop(context, _p),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String url;
  final String title;
  const _PhotoViewer({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(fontSize: 16)),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 5,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(
                color: GUI.accent, strokeWidth: 2),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 56),
          ),
        ),
      ),
    );
  }
}
