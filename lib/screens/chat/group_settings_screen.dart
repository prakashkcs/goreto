import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final ChatGroup group;
  const GroupSettingsScreen({super.key, required this.group});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupChatService _service = GroupChatService();
  bool _isLoading = true;
  String _myRole = 'member';
  List<ChatGroupMember> _members = [];
  int _myId = 0;

  late TextEditingController _nameCtrl;
  late TextEditingController _feeCtrl;
  late TextEditingController _monthlyFeeCtrl;
  late TextEditingController _delayCtrl;

  bool _isPrivate = false;
  late GroupPermissions _permissions;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myId = int.tryParse(auth.currentUserId ?? '0') ?? 0;
    _nameCtrl = TextEditingController(text: widget.group.name);
    _feeCtrl = TextEditingController(text: widget.group.joinFee.toString());
    _monthlyFeeCtrl = TextEditingController(
      text: widget.group.monthlyFee.toString(),
    );
    _delayCtrl = TextEditingController(
      text: widget.group.messageDelay.toString(),
    );
    _isPrivate = widget.group.isPrivate;
    _permissions = widget.group.permissions;
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _feeCtrl.dispose();
    _monthlyFeeCtrl.dispose();
    _delayCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getGroupMembers(widget.group.id);
      if (mounted) {
        String role = data['my_role']?.toString() ?? 'member';
        if (widget.group.createdBy == _myId && role == 'member') {
          role = 'admin';
        }
        setState(() {
          _myRole = role;
          _members = (data['members'] as List<ChatGroupMember>?) ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String role = 'member';
        if (widget.group.createdBy == _myId) {
          role = 'admin';
        }
        setState(() {
          _myRole = role;
          _members = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_myRole != 'admin') return;
    final fee = int.tryParse(_feeCtrl.text) ?? 0;
    final monthlyFee = int.tryParse(_monthlyFeeCtrl.text) ?? 0;
    final delay = int.tryParse(_delayCtrl.text) ?? 0;

    setState(() => _isLoading = true);
    await _service.updateSettings(
      widget.group.id,
      name: _nameCtrl.text.trim(),
      joinFee: fee,
      monthlyFee: monthlyFee,
      isPrivate: _isPrivate,
      messageDelay: delay,
      permissions: _permissions,
    );
    _showSnackBar('Settings updated');
    _loadData();
  }

  Future<void> _editUsername() async {
    if (_myRole != 'admin') return;
    final ctrl = TextEditingController(text: widget.group.username);
    final newUsername = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Edit Username',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter username',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newUsername != null && newUsername.isNotEmpty) {
      setState(() => _isLoading = true);
      await _service.updateSettings(widget.group.id, username: newUsername);
      _showSnackBar('Username updated');
      _loadData();
    }
  }

  Future<void> _editBio() async {
    if (_myRole != 'admin') return;
    final ctrl = TextEditingController(text: widget.group.bio);
    final newBio = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Edit Bio', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 100,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter bio (keywords for search)',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newBio != null) {
      setState(() => _isLoading = true);
      await _service.updateSettings(widget.group.id, bio: newBio);
      _showSnackBar('Bio updated');
      _loadData();
    }
  }

  Future<void> _updateAvatar() async {
    if (_myRole != 'admin') return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      setState(() => _isLoading = true);
      await _service.updateSettings(
        widget.group.id,
        avatarPath: pickedFile.path,
      );
      _showSnackBar('Avatar updated');
      _loadData();
    }
  }

  Future<void> _deleteGroup() async {
    if (_myRole != 'admin') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete Group',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this group? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final success = await _service.deleteGroup(widget.group.id);
      if (success && mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      } else {
        _showSnackBar('Failed to delete group');
        _loadData();
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Leave Group', style: TextStyle(color: Colors.white)),
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
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok = await _service.leaveGroup(widget.group.id);
      if (ok && mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      } else {
        _showSnackBar('Failed to leave group');
      }
    }
  }

  Future<void> _clearMyChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Clear Chat', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Delete all your messages from this group? This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await _service.clearMyChat(widget.group.id);
      if (ok && mounted) {
        _showSnackBar('Chat cleared');
        Navigator.pop(context);
        Navigator.pop(context);
      } else {
        _showSnackBar('Failed to clear chat');
      }
    }
  }

  Future<void> _inviteUserDialog() async {
    if (!mounted) return;
    final memberIds = _members.map((m) => m.id).toSet();

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InviteSheet(
        groupId: widget.group.id,
        memberIds: memberIds,
        service: _service,
        onInvited: (msg) {
          _showSnackBar(msg);
          _loadData();
        },
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.pink));
  }

  void _manageMember(ChatGroupMember m) {
    if (_myRole != 'admin' || m.role == 'admin') return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (c) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: const Text(
                  'Make Admin',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(c);
                  await _service.setRole(widget.group.id, m.id, 'admin');
                  _loadData();
                },
              ),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                title: const Text(
                  'Kick Member',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(c);
                  await _service.kickMember(widget.group.id, m.id);
                  _loadData();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text(
                  'Ban Permanently',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(c);
                  await _service.banMember(widget.group.id, m.id);
                  _loadData();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPermissionsDialog() {
    if (_myRole != 'admin') return;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Member Permissions',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text(
                  'Send Text',
                  style: TextStyle(color: Colors.white),
                ),
                value: _permissions.canSendText,
                activeThumbColor: GalacticTheme.laserPink,
                onChanged: (v) => setDialogState(
                  () => _permissions = GroupPermissions(
                    canSendText: v,
                    canSendMedia: _permissions.canSendMedia,
                    canSendVoice: _permissions.canSendVoice,
                    canSendStickers: _permissions.canSendStickers,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text(
                  'Send Media',
                  style: TextStyle(color: Colors.white),
                ),
                value: _permissions.canSendMedia,
                activeThumbColor: GalacticTheme.laserPink,
                onChanged: (v) => setDialogState(
                  () => _permissions = GroupPermissions(
                    canSendText: _permissions.canSendText,
                    canSendMedia: v,
                    canSendVoice: _permissions.canSendVoice,
                    canSendStickers: _permissions.canSendStickers,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text(
                  'Send Voice',
                  style: TextStyle(color: Colors.white),
                ),
                value: _permissions.canSendVoice,
                activeThumbColor: GalacticTheme.laserPink,
                onChanged: (v) => setDialogState(
                  () => _permissions = GroupPermissions(
                    canSendText: _permissions.canSendText,
                    canSendMedia: _permissions.canSendMedia,
                    canSendVoice: v,
                    canSendStickers: _permissions.canSendStickers,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text(
                  'Send Stickers',
                  style: TextStyle(color: Colors.white),
                ),
                value: _permissions.canSendStickers,
                activeThumbColor: GalacticTheme.laserPink,
                onChanged: (v) => setDialogState(
                  () => _permissions = GroupPermissions(
                    canSendText: _permissions.canSendText,
                    canSendMedia: _permissions.canSendMedia,
                    canSendVoice: _permissions.canSendVoice,
                    canSendStickers: v,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                _saveSettings();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: GalacticTheme.laserPink,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color iconColor = GalacticTheme.laserPink,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: Colors.white38)
              : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _myRole == 'admin';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text(
          'Group Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: GalacticTheme.laserPink),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: isAdmin ? _updateAvatar : null,
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  GalacticTheme.laserPink,
                                  Color(0xFF8B5CF6),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: GalacticTheme.laserPink.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white12,
                              backgroundImage: widget.group.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      widget.group.avatarUrl!,
                                    )
                                  : null,
                              child: widget.group.avatarUrl == null
                                  ? const Icon(
                                      Icons.group,
                                      size: 50,
                                      color: Colors.white54,
                                    )
                                  : null,
                            ),
                          ),
                          if (isAdmin)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: GalacticTheme.laserPink,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      widget.group.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.group.username != null)
                    Center(
                      child: Text(
                        '@${widget.group.username}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (isAdmin) ...[
                    _buildCard(
                      title: 'GROUP INFO',
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Group Name',
                              labelStyle: const TextStyle(
                                color: Colors.white54,
                              ),
                              prefixIcon: const Icon(
                                Icons.edit,
                                color: GalacticTheme.laserPink,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _feeCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Join Fee',
                                    labelStyle: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.monetization_on,
                                      color: Colors.amber,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.05,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _delayCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Message Delay (seconds)',
                              labelStyle: const TextStyle(
                                color: Colors.white54,
                              ),
                              prefixIcon: const Icon(
                                Icons.timer,
                                color: Colors.orange,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                    _buildCard(
                      title: 'PRIVACY',
                      children: [
                        SwitchListTile(
                          title: const Text(
                            'Private Group',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _isPrivate
                                ? 'Only admins can see group info'
                                : 'Anyone can discover this group',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: _isPrivate,
                          activeThumbColor: GalacticTheme.laserPink,
                          onChanged: (v) => setState(() => _isPrivate = v),
                        ),
                      ],
                    ),
                    _buildCard(
                      title: 'MANAGE',
                      children: [
                        _buildListTile(
                          icon: Icons.alternate_email,
                          title: 'Username',
                          subtitle: widget.group.username ?? 'Not set',
                          onTap: _editUsername,
                        ),
                        _buildListTile(
                          icon: Icons.description,
                          title: 'Bio',
                          subtitle: widget.group.bio ?? 'Not set',
                          onTap: _editBio,
                        ),
                        _buildListTile(
                          icon: Icons.security,
                          title: 'Permissions',
                          subtitle: 'Manage member permissions',
                          onTap: _showPermissionsDialog,
                        ),
                        _buildListTile(
                          icon: Icons.person_add,
                          title: 'Invite Members',
                          subtitle: 'Add users to group',
                          onTap: _inviteUserDialog,
                          iconColor: Colors.green,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GalacticTheme.laserPink,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Save Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildCard(
                    title: 'MEMBERS (${_members.length})',
                    children: [
                      ..._members.map(
                        (m) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundImage: m.avatarUrl != null
                                ? CachedNetworkImageProvider(m.avatarUrl!)
                                : null,
                            backgroundColor: Colors.white12,
                            child: m.avatar == null
                                ? Text(
                                    m.name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            m.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '@${m.username}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: m.role == 'admin'
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: GalacticTheme.laserPink.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Admin',
                                    style: TextStyle(
                                      color: GalacticTheme.laserPink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : (isAdmin
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white54,
                                      ),
                                      onPressed: () => _manageMember(m),
                                    )
                                  : null),
                        ),
                      ),
                    ],
                  ),
                  _buildCard(
                    title: 'ACTIONS',
                    children: [
                      _buildListTile(
                        icon: Icons.delete_sweep,
                        title: 'Clear My Chat',
                        subtitle: 'Delete your messages',
                        onTap: _clearMyChat,
                        iconColor: Colors.orange,
                      ),
                      _buildListTile(
                        icon: Icons.exit_to_app,
                        title: 'Leave Group',
                        subtitle: 'Exit this group',
                        onTap: _leaveGroup,
                        iconColor: Colors.red,
                      ),
                      if (isAdmin)
                        _buildListTile(
                          icon: Icons.delete_forever,
                          title: 'Delete Group',
                          subtitle: 'Permanently delete',
                          onTap: _deleteGroup,
                          iconColor: Colors.red,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Live-search invite sheet ──────────────────────────────────────────────────

class _InviteSheet extends StatefulWidget {
  final int groupId;
  final Set<int> memberIds;
  final GroupChatService service;
  final void Function(String msg) onInvited;

  const _InviteSheet({
    required this.groupId,
    required this.memberIds,
    required this.service,
    required this.onInvited,
  });

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final Set<int> _invited = {};
  bool _searching = false;
  dynamic _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    if (_debounce != null) (_debounce as Future).ignore();
    setState(() => _searching = v.trim().isNotEmpty);
    if (v.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchCtrl.text.trim() != v.trim()) return;
      final res = await widget.service.searchUsers(v.trim());
      if (!mounted || _searchCtrl.text.trim() != v.trim()) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    });
  }

  Future<void> _invite(Map<String, dynamic> user) async {
    final uid = int.tryParse(user['id'].toString()) ?? 0;
    if (uid == 0) return;
    setState(() => _invited.add(uid));
    final res = await widget.service.inviteByUserId(widget.groupId, uid);
    if (!mounted) return;
    widget.onInvited(res['msg'] ?? 'Invited');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Invite Members',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search by name or username...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Colors.white30, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white30, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          // Results
          Expanded(
            child: _searching
                ? const Center(
                    child: CircularProgressIndicator(
                        color: GalacticTheme.laserPink, strokeWidth: 2),
                  )
                : _results.isEmpty && _searchCtrl.text.trim().isNotEmpty
                    ? Center(
                        child: Text(
                          'No users found for "${_searchCtrl.text.trim()}"',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: Text(
                              'Type to search users',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final u = _results[i];
                              final uid =
                                  int.tryParse(u['id'].toString()) ?? 0;
                              final isMember =
                                  widget.memberIds.contains(uid);
                              final justInvited = _invited.contains(uid);
                              final name = u['name']?.toString() ?? '';
                              final username =
                                  u['username']?.toString() ?? '';
                              final avatar = u['avatar']?.toString();

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.white12,
                                  backgroundImage: (avatar != null &&
                                          avatar.isNotEmpty)
                                      ? CachedNetworkImageProvider(avatar)
                                      : null,
                                  child: (avatar == null || avatar.isEmpty)
                                      ? Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: username.isNotEmpty
                                    ? Text(
                                        '@$username',
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12),
                                      )
                                    : null,
                                trailing: (isMember || justInvited)
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isMember ? 'Added' : 'Invited',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12),
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: () => _invite(u),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 7),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFD946EF),
                                                Color(0xFF8B5CF6),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Invite',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                              );
                            },
                          ),
          ),
          SizedBox(
              height: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 24),
        ],
      ),
    );
  }
}
