import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:love_vibe_pro/core/theme.dart';
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

  bool _isPrivate = false;
  String? _avatarPath;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file != null && mounted) {
      setState(() => _avatarPath = file.path);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();

    if (name.isEmpty) {
      NeonToast.error(context, 'Please enter a group name');
      return;
    }
    if (username.isEmpty) {
      NeonToast.error(context, 'Please enter a username');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final group = await _service.createGroup(
        name,
        username: username,
        bio: _bioCtrl.text.trim().isNotEmpty ? _bioCtrl.text.trim() : null,
        isPrivate: _isPrivate,
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
      NeonToast.error(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Group',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isCreating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: GalacticTheme.laserPink, strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _submit,
                    child: const Text(
                      'Create',
                      style: TextStyle(
                          color: GalacticTheme.laserPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar ──────────────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _avatarPath == null
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
                          color: const Color(0xFFD946EF).withValues(alpha: 0.5),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFD946EF).withValues(alpha: 0.25),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: _avatarPath != null
                          ? ClipOval(
                              child: Image.file(
                                File(_avatarPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.group,
                                    color: Colors.white,
                                    size: 46),
                              ),
                            )
                          : const Icon(Icons.group,
                              color: Colors.white, size: 46),
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFFD946EF), Color(0xFFFF007F)]),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Tap to add group photo',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
            const SizedBox(height: 32),

            // ── Fields ──────────────────────────────────────────────────────
            _Field(
              controller: _nameCtrl,
              hint: 'Group Name',
              icon: Icons.group_outlined,
              maxLength: 50,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _usernameCtrl,
              hint: 'Username  (e.g. travel_fans)',
              icon: Icons.alternate_email,
              maxLength: 30,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _bioCtrl,
              hint: 'Description (optional)',
              icon: Icons.description_outlined,
              maxLines: 3,
              maxLength: 120,
            ),
            const SizedBox(height: 20),

            // ── Privacy toggle ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (_isPrivate ? Colors.red : Colors.green)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isPrivate ? Icons.lock : Icons.public,
                      color: _isPrivate ? Colors.red : Colors.green,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPrivate ? 'Private Group' : 'Public Group',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                        Text(
                          _isPrivate
                              ? 'Only invited members can join'
                              : 'Anyone can discover and join',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isPrivate,
                    activeThumbColor: GalacticTheme.laserPink,
                    onChanged: (v) => setState(() => _isPrivate = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // ── Create button ────────────────────────────────────────────────
            SizedBox(
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _isCreating
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFFD946EF), Color(0xFFFF007F)],
                        ),
                  color:
                      _isCreating ? const Color(0xFF1E1E1E) : null,
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: _isCreating
                      ? null
                      : [
                          BoxShadow(
                            color: const Color(0xFFD946EF)
                                .withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: TextButton(
                  onPressed: _isCreating ? null : _submit,
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27)),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          'Create Group',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final int? maxLength;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30),
          prefixIcon: Icon(icon,
              color: const Color(0xFFD946EF).withValues(alpha: 0.8), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          counterStyle:
              const TextStyle(color: Colors.white24, fontSize: 11),
        ),
      ),
    );
  }
}
