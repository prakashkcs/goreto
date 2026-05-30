import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/chat_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class ShareBottomSheet extends StatefulWidget {
  final dynamic postId;
  final String username;
  final BuildContext hostContext;
  final VoidCallback? onShared;

  const ShareBottomSheet({
    super.key,
    required this.postId,
    required this.username,
    required this.hostContext,
    this.onShared,
  });

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();

  static void show({
    required BuildContext context,
    required dynamic postId,
    String username = '',
    VoidCallback? onShared,
  }) {
    SoundService().playTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareBottomSheet(
        postId: postId,
        username: username,
        hostContext: context,
        onShared: onShared,
      ),
    );
  }

  String get postUrl {
    final u = username.isNotEmpty ? username : 'user';
    return 'https://goreto.org/$u/$postId';
  }
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  final TextEditingController _captionController = TextEditingController();
  bool _isReposting = false;

  // "Send to message" state
  bool _showMessagePicker = false;
  bool _loadingConversations = false;
  List<dynamic> _conversations = [];
  final Set<String> _sentTo = {};

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  // ── Copy link ─────────────────────────────────────────────────────────────

  Future<void> _copyLink() async {
    final ctx = widget.hostContext;
    await Clipboard.setData(ClipboardData(text: widget.postUrl));
    if (!mounted) return;
    Navigator.pop(context);
    NeonToast.success(ctx, 'Link copied!');
  }

  // ── External share ────────────────────────────────────────────────────────

  Future<void> _shareExternal() async {
    Navigator.pop(context);
    await SharePlus.instance.share(
      ShareParams(
        text: '${widget.postUrl}\n\nShared via Goreto',
        subject: 'Check this out on Goreto',
      ),
    );
  }

  // ── Repost to feed ────────────────────────────────────────────────────────

  Future<void> _submitRepost() async {
    if (_isReposting) return;
    final ctx = widget.hostContext;
    setState(() => _isReposting = true);
    final result = await ApiService().shareOnProfile(
      widget.postId,
      _captionController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isReposting = false);
    if (result != null) {
      Navigator.pop(context);
      if (ctx.mounted) NeonToast.success(ctx, 'Reposted to your feed');
      widget.onShared?.call();
    } else {
      if (ctx.mounted) NeonToast.error(ctx, 'Repost failed. Try again.');
    }
  }

  // ── Send to message ───────────────────────────────────────────────────────

  Future<void> _openMessagePicker() async {
    setState(() {
      _showMessagePicker = true;
      _loadingConversations = true;
    });
    try {
      final convs = await ChatService.instance.getConversations();
      if (mounted) setState(() => _conversations = convs);
    } catch (_) {}
    if (mounted) setState(() => _loadingConversations = false);
  }

  Future<void> _sendToUser(dynamic conv) async {
    final id = (conv.otherUserId ?? conv.id ?? '').toString();
    if (id.isEmpty || _sentTo.contains(id)) return;
    final ctx = widget.hostContext;
    try {
      await ChatService.instance.sendMessage(
        receiverId: id,
        content: widget.postUrl,
      );
      if (mounted) setState(() => _sentTo.add(id));
      if (ctx.mounted) NeonToast.success(ctx, 'Sent!');
    } catch (e) {
      if (ctx.mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        NeonToast.error(ctx, msg.isNotEmpty ? msg : 'Failed to send');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                const Text(
                  'Share Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.postUrl,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),

                // Quick-action row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QuickAction(
                      icon: Icons.copy_rounded,
                      label: 'Copy Link',
                      color: const Color(0xFF00E5FF),
                      onTap: _copyLink,
                    ),
                    _QuickAction(
                      icon: Icons.ios_share_rounded,
                      label: 'Share App',
                      color: const Color(0xFFFF007F),
                      onTap: _shareExternal,
                    ),
                    _QuickAction(
                      icon: Icons.send_rounded,
                      label: 'Message',
                      color: const Color(0xFFD946EF),
                      onTap: _showMessagePicker ? null : _openMessagePicker,
                    ),
                  ],
                ),

                // ── Message picker ─────────────────────────────────────────
                if (_showMessagePicker) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Send to',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingConversations)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF007F),
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else if (_conversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No conversations yet',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 13),
                      ),
                    )
                  else
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final conv = _conversations[i];
                          final name = (conv.otherUserName ??
                                  conv.name ??
                                  'User')
                              .toString();
                          final avatar = (conv.otherUserAvatar ??
                                  conv.avatar ??
                                  '')
                              .toString();
                          final id =
                              (conv.otherUserId ?? conv.id ?? '').toString();
                          final sent = _sentTo.contains(id);
                          return GestureDetector(
                            onTap: sent ? null : () => _sendToUser(conv),
                            child: SizedBox(
                              width: 60,
                              child: Column(
                                children: [
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundImage: avatar.isNotEmpty
                                            ? NetworkImage(avatar)
                                            : null,
                                        backgroundColor:
                                            const Color(0xFF2A2A3E),
                                        child: avatar.isEmpty
                                            ? Text(
                                                name.isNotEmpty
                                                    ? name[0].toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              )
                                            : null,
                                      ),
                                      if (sent)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                Icons.check_rounded,
                                                color: Colors.white,
                                                size: 18),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    name.split(' ').first,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],

                // ── Repost divider ─────────────────────────────────────────
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Repost to your feed',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _captionController,
                  maxLines: 2,
                  maxLength: 280,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a caption (optional)…',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isReposting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isReposting ? null : _submitRepost,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF007F),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isReposting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Repost'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
