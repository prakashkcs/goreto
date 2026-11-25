import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _service = GroupChatService();
  late final UsernameChecker _checker;

  bool _isPrivate = false;
  bool _joinApproval = false;
  String? _avatarPath;
  bool _isCreating = false;

  /// While true the username follows the group name automatically. It stops
  /// as soon as the user edits the username themselves.
  bool _usernameAuto = true;
  UsernameState _uState = UsernameState.idle;
  String? _uMessage;
  String? _uSuggestion;

  @override
  void initState() {
    super.initState();
    _checker = UsernameChecker(
      service: _service,
      onResult: (s, m, sug) {
        if (!mounted) return;
        setState(() {
          _uState = s;
          _uMessage = m;
          _uSuggestion = sug;
        });
        // Auto mode: silently swap a taken suggestion for a free one.
        if (_usernameAuto && s == UsernameState.taken && sug != null) {
          _setUsername(sug, auto: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _checker.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged(String v) {
    setState(() {});
    if (!_usernameAuto) return;
    _setUsername(slugifyGroupName(v), auto: true);
  }

  void _setUsername(String v, {bool auto = false}) {
    _usernameCtrl.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    if (!auto) _usernameAuto = false;
    _checker.check(v);
  }

  void _onUsernameChanged(String v) {
    // Any manual edit stops the name → username auto-fill.
    setState(() => _usernameAuto = false);
    _checker.check(v);
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _avatarPath = file.path);
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _usernameCtrl.text.trim().isNotEmpty &&
      _uState != UsernameState.taken &&
      _uState != UsernameState.invalid &&
      !_isCreating;

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty) {
      NeonToast.error(context, 'Please enter a group name');
      return;
    }
    if (username.isEmpty) {
      NeonToast.error(context, 'Please choose a username');
      return;
    }
    if (_uState == UsernameState.taken || _uState == UsernameState.invalid) {
      NeonToast.error(context, _uMessage ?? 'Please choose another username');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isCreating = true);
    try {
      final group = await _service.createGroup(
        name,
        username: username,
        bio: _bioCtrl.text.trim().isNotEmpty ? _bioCtrl.text.trim() : null,
        isPrivate: _isPrivate,
        joinApproval: _isPrivate ? true : _joinApproval,
        avatarPath: _avatarPath,
      );
      if (!mounted) return;
      if (group != null) {
        Navigator.pop(context, group);
      } else {
        NeonToast.error(context, 'Failed to create group');
      }
    } catch (e) {
      if (!mounted) return;
      NeonToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    return Scaffold(
      backgroundColor: GUI.bg,
      appBar: AppBar(
        backgroundColor: GUI.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New group',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // ── Avatar ────────────────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
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
                              child: _avatarPath != null
                                  ? ClipOval(
                                      child: Image.file(File(_avatarPath!),
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover))
                                  : Container(
                                      width: 100,
                                      height: 100,
                                      decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: GUI.surface2),
                                      child: name.isEmpty
                                          ? const Icon(Icons.groups_rounded,
                                              color: GUI.textLo, size: 44)
                                          : Center(
                                              child: Text(
                                                  name[0].toUpperCase(),
                                                  style: const TextStyle(
                                                      color: GUI.textHi,
                                                      fontSize: 40,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: GUI.gradient,
                                shape: BoxShape.circle,
                                border: Border.all(color: GUI.bg, width: 3),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _avatarPath == null ? 'Add a group photo' : 'Change photo',
                      style: const TextStyle(color: GUI.textLo, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // ── Details ───────────────────────────────────────────
                  GTextField(
                    controller: _nameCtrl,
                    label: 'Group name',
                    hint: 'e.g. Travel Fans',
                    maxLength: 60,
                    onChanged: _onNameChanged,
                  ),
                  const SizedBox(height: 6),
                  GTextField(
                    controller: _usernameCtrl,
                    label: 'Username',
                    hint: 'travel_fans',
                    formatters: usernameFormatter,
                    onChanged: _onUsernameChanged,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 2),
                      child: Text('@',
                          style: TextStyle(
                              color: GUI.textLo,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                    suffix: _usernameAuto && _usernameCtrl.text.isNotEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Center(
                              widthFactor: 1,
                              child: Text('Suggested',
                                  style: TextStyle(
                                      color: GUI.accent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          )
                        : null,
                  ),
                  UsernameStatusLine(
                    state: _uState,
                    message: _uMessage,
                    suggestion: _uSuggestion,
                    onUseSuggestion: (s) => _setUsername(s),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 6),
                    child: Text(
                      'Suggested from the group name. Tap it to change. People can find the group with this @username.',
                      style: TextStyle(color: GUI.textLo, fontSize: 12, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 18),
                  GTextField(
                    controller: _bioCtrl,
                    label: 'Description (optional)',
                    hint: 'What is this group about?',
                    maxLines: 3,
                    maxLength: 300,
                  ),

                  // ── Group type ────────────────────────────────────────
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('Group type',
                        style: TextStyle(
                            color: GUI.textMid,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  GroupTypeSelector(
                    isPrivate: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v),
                  ),
                  if (!_isPrivate) ...[
                    const SizedBox(height: 12),
                    GSection(
                      margin: EdgeInsets.zero,
                      children: [
                        GSwitchTile(
                          icon: Icons.how_to_reg_rounded,
                          iconColor: GUI.info,
                          title: 'Approve new members',
                          subtitle:
                              'Admins review join requests before people get in',
                          value: _joinApproval,
                          onChanged: (v) => setState(() => _joinApproval = v),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: GPrimaryButton(
                label: 'Create group',
                loading: _isCreating,
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two explicit cards instead of an ambiguous on/off switch. The old switch
/// read "Public Group" next to a toggle, so turning it ON made the group private.
class GroupTypeSelector extends StatelessWidget {
  final bool isPrivate;
  final ValueChanged<bool> onChanged;
  const GroupTypeSelector(
      {super.key, required this.isPrivate, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TypeCard(
            selected: !isPrivate,
            icon: Icons.public_rounded,
            color: GUI.success,
            title: 'Public',
            subtitle: 'Shows in Discover. Anyone can find and join.',
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TypeCard(
            selected: isPrivate,
            icon: Icons.lock_rounded,
            color: GUI.warning,
            title: 'Private',
            subtitle: 'Hidden. Join by invite or admin approval.',
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeCard({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : GUI.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : GUI.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GIconBox(icon, color: color, size: 32),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? color : Colors.transparent,
                    border: Border.all(
                        color: selected ? color : GUI.textLo, width: 1.6),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: GUI.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    color: GUI.textLo, fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
